module dcache
    import rv32im_types::*;
(
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, request / response style for LSQ
    input   logic               ufp_req_valid,
    output  logic               ufp_req_ready,
    input   dcache_cpu_req_t    ufp_req,
    output  logic               ufp_resp_valid,
    input   logic               ufp_resp_ready,
    output  dcache_cpu_resp_t   ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_HIT,
        ST_WRITEBACK,
        ST_ALLOCATE
    } state_t;

    state_t state_q, state_d;

    // 保存请求
    logic   [31:0]  req_addr_q;
    logic   [3:0]   req_rmask_q, req_wmask_q;
    logic   [31:0]  req_wdata_q;
    logic   [DCACHE_REQ_ID_BITS-1:0] req_id_q;

    dcache_cpu_resp_t   resp_q;
    logic               resp_valid_q;

    // 控制信号
    logic   [3:0]   csb_tag, web_tag;
    logic   [3:0]   csb_data, web_data;
    logic   [3:0]   csb_vd, web_vd;
    logic           csb_lru, web_lru;
    logic   [31:0]  wmask_data;

    logic   [1:0]   way_lru;
    logic           hit;
    logic   [1:0]   way_hit;
    logic   [3:0]   way_hit_sel;
    logic           hit_way0, hit_way1, hit_way2, hit_way3;

    logic           lru_update_en;
    logic   [1:0]   lru_update_way;

    // 数据路径
    logic   [3:0]   set;
    logic   [4:0]   offset;
    logic   [22:0]  tag_passin;

    logic   [22:0]  tag_out [4];
    logic   [1:0]   vd_in [4], vd_out [4];
    logic   [2:0]   lru_in, lru_out;
    logic   [1:0]   line_vd;

    logic   [255:0] data_in, data_out [4];
    logic   [255:0] hit_line_data;
    logic   [255:0] dfp_wb_data_q;
    logic   [22:0]  dfp_wb_tag_q;

    logic   [1:0]   dfp_wb_way_q;

    logic   [255:0] alloc_data_line;
    logic           req_accept;
    logic           resp_slot_free;
    logic           resp_bypass;
    logic           hit_load_accept_ok;
    logic           resp_push_valid;
    dcache_cpu_resp_t resp_push_data;

    function automatic logic [31:0] extract_word_data(
        input logic [255:0] line_data,
        input logic [4:0]   byte_offset,
        input logic [3:0]   byte_mask
    );
        logic [31:0] result;
        integer unsigned byte_idx;
        begin
            result = 32'b0;
            for (integer unsigned i = 0; i < 4; i++) begin
                byte_idx = byte_offset + i;
                if (byte_mask[i] && (byte_idx < 32)) begin
                    result[(i * 8) +: 8] = line_data[(byte_idx * 8) +: 8];
                end
            end
            return result;
        end
    endfunction

    function automatic logic [255:0] merge_store_line(
        input logic [255:0] line_data,
        input logic [4:0]   byte_offset,
        input logic [3:0]   byte_mask,
        input logic [31:0]  store_data
    );
        logic [255:0] result;
        integer unsigned byte_idx;
        begin
            result = line_data;
            for (integer unsigned i = 0; i < 4; i++) begin
                byte_idx = byte_offset + i;
                if (byte_mask[i] && (byte_idx < 32)) begin
                    result[(byte_idx * 8) +: 8] = store_data[(i * 8) +: 8];
                end
            end
            return result;
        end
    endfunction

    // ---------------------------------------------------------------------------------
    // SRAM/FF array instances
    // ---------------------------------------------------------------------------------
    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (csb_data[i]),
            .web0       (web_data[i]),
            .wmask0     (wmask_data),
            .addr0      (set),
            .din0       (data_in),
            .dout0      (data_out[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (csb_tag[i]),
            .web0       (web_tag[i]),
            .addr0      (set),
            .din0       (tag_passin),
            .dout0      (tag_out[i])
        );
        // [valid, dirty]
        sp_ff_array #(
            .WIDTH      (2)
        ) valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (csb_vd[i]),
            .web0       (web_vd[i]),
            .addr0      (set),
            .din0       (vd_in[i]),
            .dout0      (vd_out[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (csb_lru),
        .web0       (web_lru),
        .addr0      (set),
        .din0       (lru_in),
        .dout0      (lru_out)
    );

    assign resp_slot_free = !resp_valid_q || ufp_resp_ready;
    assign hit_load_accept_ok = (state_q == ST_HIT) && hit && (req_wmask_q == 4'b0);
    assign ufp_req_ready = resp_slot_free &&
                           ((state_q == ST_IDLE) || hit_load_accept_ok);
    assign req_accept = ufp_req_valid && ufp_req_ready;
    assign resp_bypass = resp_push_valid && !resp_valid_q && ufp_resp_ready;
    assign ufp_resp_valid = resp_valid_q || (resp_push_valid && !resp_valid_q);
    assign ufp_resp = resp_valid_q ? resp_q : resp_push_data;

    // IDLE收到新请求时，SRAM读地址直接看 live req.addr，保证命中仍然只多一拍数组读。
    assign set = req_accept ? ufp_req.addr[8:5] : req_addr_q[8:5];
    assign offset = req_addr_q[4:0];
    assign tag_passin = req_addr_q[31:9];

    assign line_vd = vd_out[way_lru];

    // 命中行选择 + 字偏移
    always_comb begin
        hit_line_data = data_out[0];
        unique case (way_hit)
            2'd0: hit_line_data = data_out[0];
            2'd1: hit_line_data = data_out[1];
            2'd2: hit_line_data = data_out[2];
            2'd3: hit_line_data = data_out[3];
        endcase
    end

    always_comb begin
        way_hit_sel = 4'hF;
        way_hit_sel[way_hit] = 1'b0;
    end

    // 主状态机
    always_comb begin
        state_d = state_q;

        resp_push_valid = 1'b0;
        resp_push_data = '0;

        dfp_read = 1'b0;
        dfp_write = 1'b0;
        dfp_addr = 32'b0;
        dfp_wdata = 256'b0;

        csb_tag = 4'hF;
        csb_data = 4'hF;
        csb_vd = 4'hF;
        csb_lru = 1'b0;

        web_tag = 4'hF;
        web_data = 4'hF;
        web_vd = 4'hF;
        web_lru = 1'b1;

        wmask_data = 32'h0;
        data_in = 256'h0;

        lru_update_en = 1'b0;
        lru_update_way = 2'd0;

        alloc_data_line = dfp_rdata;

        for (integer j = 0; j < 4; j = j + 1) begin
            vd_in[j] = vd_out[j];
        end

        unique case (state_q)
            ST_IDLE: begin
                if (req_accept) begin
                    state_d = ST_HIT;
                    csb_tag = 4'h0;
                    csb_data = 4'h0;
                    csb_vd = 4'h0;
                end
            end

            ST_HIT: begin
                if (hit && resp_slot_free) begin
                    state_d = req_accept ? ST_HIT : ST_IDLE;
                    resp_push_valid = 1'b1;
                    resp_push_data.id = req_id_q;
                    resp_push_data.addr = req_addr_q;
                    resp_push_data.rmask = req_rmask_q;
                    resp_push_data.wmask = req_wmask_q;
                    resp_push_data.rdata = extract_word_data(hit_line_data, offset, req_rmask_q);

                    if (req_accept) begin
                        csb_tag = 4'h0;
                        csb_data = 4'h0;
                        csb_vd = 4'h0;
                    end else begin
                        // 命中就更新lru。若同拍接新请求，单端口lru array留给新地址读取。
                        lru_update_en = 1'b1;
                        lru_update_way = way_hit;
                    end

                    if (req_wmask_q != 4'b0) begin
                        data_in = merge_store_line(hit_line_data, offset, req_wmask_q, req_wdata_q);
                        wmask_data = 32'hFFFF_FFFF;
                        csb_data = way_hit_sel;
                        web_data = way_hit_sel;
                        csb_vd = way_hit_sel;
                        web_vd = way_hit_sel;
                        vd_in[way_hit] = 2'b11;
                    end
                end else if (hit) begin
                    state_d = ST_HIT;
                end else if (line_vd == 2'b11) begin
                    // dirty miss：进入WRITEBACK，由WRITEBACK状态驱动dfp_write
                    state_d = ST_WRITEBACK;
                end else begin
                    // clean miss：进入ALLOCATE，由ALLOCATE状态驱动dfp_read
                    state_d = ST_ALLOCATE;
                end
            end

            ST_WRITEBACK: begin
                // memory_model要求read/write和addr保持稳定直到resp
                dfp_addr = {dfp_wb_tag_q, req_addr_q[8:5], 5'b0};
                dfp_write = 1'b1;
                dfp_wdata = dfp_wb_data_q;
                if (dfp_resp) begin
                    state_d = ST_ALLOCATE;
                end
            end

            ST_ALLOCATE: begin
                // memory_model要求read和addr保持稳定直到resp
                dfp_addr = {req_addr_q[31:5], 5'b0};
                dfp_read = 1'b1;

                if (dfp_resp) begin
                    // 回填后直接完成原请求，不再依赖上层重复发同一条请求。
                    data_in = alloc_data_line;
                    if (req_wmask_q != 4'b0) begin
                        data_in = merge_store_line(alloc_data_line, offset, req_wmask_q, req_wdata_q);
                    end
                    wmask_data = 32'hFFFF_FFFF;
                    csb_data = 4'hF;
                    web_data = 4'hF;
                    csb_data[dfp_wb_way_q] = 1'b0;
                    web_data[dfp_wb_way_q] = 1'b0;

                    // 回填tag
                    csb_tag = 4'hF;
                    web_tag = 4'hF;
                    csb_tag[dfp_wb_way_q] = 1'b0;
                    web_tag[dfp_wb_way_q] = 1'b0;

                    // 更新valid/dirty
                    csb_vd = 4'hF;
                    web_vd = 4'hF;
                    csb_vd[dfp_wb_way_q] = 1'b0;
                    web_vd[dfp_wb_way_q] = 1'b0;
                    vd_in[dfp_wb_way_q] = (req_wmask_q != 4'b0) ? 2'b11 : 2'b01;

                    // 分配成功也算最近使用
                    lru_update_en = 1'b1;
                    lru_update_way = dfp_wb_way_q;

                    resp_push_valid = 1'b1;
                    resp_push_data.id = req_id_q;
                    resp_push_data.addr = req_addr_q;
                    resp_push_data.rmask = req_rmask_q;
                    resp_push_data.wmask = req_wmask_q;
                    resp_push_data.rdata = extract_word_data(alloc_data_line, offset, req_rmask_q);

                    state_d = ST_IDLE;
                end
            end

            default: begin
                state_d = ST_IDLE;
            end
        endcase

        if (lru_update_en) begin
            web_lru = 1'b0;
        end
    end

    // 时序寄存
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= ST_IDLE;
            req_addr_q <= 32'b0;
            req_rmask_q <= 4'b0;
            req_wmask_q <= 4'b0;
            req_wdata_q <= 32'b0;
            req_id_q <= '0;
            resp_q <= '0;
            resp_valid_q <= 1'b0;
            dfp_wb_way_q <= 2'b00;
            dfp_wb_data_q <= 256'b0;
            dfp_wb_tag_q <= 23'b0;
        end else begin
            state_q <= state_d;
            resp_q <= resp_q;
            resp_valid_q <= resp_valid_q;

            if (resp_valid_q && ufp_resp_ready) begin
                resp_valid_q <= 1'b0;
                resp_q <= '0;
            end

            if (resp_push_valid && !resp_bypass) begin
                resp_q <= resp_push_data;
                resp_valid_q <= 1'b1;
            end

            if (req_accept) begin
                req_addr_q <= ufp_req.addr;
                req_rmask_q <= ufp_req.rmask;
                req_wmask_q <= ufp_req.wmask;
                req_wdata_q <= ufp_req.wdata;
                req_id_q <= ufp_req.id;
            end

            // miss时锁存victim/fill信息，后续WRITEBACK/ALLOCATE使用
            if ((state_q == ST_HIT) && !hit) begin
                dfp_wb_way_q <= way_lru;
                unique case (way_lru)
                    2'd0: begin
                        dfp_wb_data_q <= data_out[0];
                        dfp_wb_tag_q <= tag_out[0];
                    end
                    2'd1: begin
                        dfp_wb_data_q <= data_out[1];
                        dfp_wb_tag_q <= tag_out[1];
                    end
                    2'd2: begin
                        dfp_wb_data_q <= data_out[2];
                        dfp_wb_tag_q <= tag_out[2];
                    end
                    2'd3: begin
                        dfp_wb_data_q <= data_out[3];
                        dfp_wb_tag_q <= tag_out[3];
                    end
                    default: begin
                        dfp_wb_data_q <= data_out[0];
                        dfp_wb_tag_q <= tag_out[0];
                    end
                endcase
            end
        end
    end

    // 命中比较
    always_comb begin
        hit_way0 = (tag_passin == tag_out[0]) && vd_out[0][0];
        hit_way1 = (tag_passin == tag_out[1]) && vd_out[1][0];
        hit_way2 = (tag_passin == tag_out[2]) && vd_out[2][0];
        hit_way3 = (tag_passin == tag_out[3]) && vd_out[3][0];

        hit = hit_way0 | hit_way1 | hit_way2 | hit_way3;
        way_hit = 2'd0;
        if (hit_way0) begin
            way_hit = 2'd0;
        end else if (hit_way1) begin
            way_hit = 2'd1;
        end else if (hit_way2) begin
            way_hit = 2'd2;
        end else if (hit_way3) begin
            way_hit = 2'd3;
        end
    end

    // Pseudo-LRU decode (bit order: L2 L1 L0)
    always_comb begin
        way_lru = 2'd0;
        unique casez (lru_out)
            3'b?00: way_lru = 2'd0; // Way A
            3'b?10: way_lru = 2'd1; // Way B
            3'b0?1: way_lru = 2'd2; // Way C
            3'b1?1: way_lru = 2'd3; // Way D
            default: way_lru = 2'd0;
        endcase
    end

    // Pseudo-LRU update
    always_comb begin
        lru_in = lru_out;
        if (lru_update_en) begin
            unique case (lru_update_way)
                2'd0: begin
                    lru_in[1] = 1'b1;
                    lru_in[0] = 1'b1;
                end
                2'd1: begin
                    lru_in[1] = 1'b0;
                    lru_in[0] = 1'b1;
                end
                2'd2: begin
                    lru_in[2] = 1'b1;
                    lru_in[0] = 1'b0;
                end
                2'd3: begin
                    lru_in[2] = 1'b0;
                    lru_in[0] = 1'b0;
                end
            endcase
        end
    end

endmodule
