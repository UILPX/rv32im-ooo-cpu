module cacheline_adapter (
    input   logic           clk,
    input   logic           rst,

    // cache side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic           ufp_read,
    input   logic           ufp_write,
    output  logic   [255:0] ufp_rdata,
    input   logic   [255:0] ufp_wdata,
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    output  logic   [63:0]  dfp_wdata,
    input   logic           dfp_ready,
    input   logic   [31:0]  dfp_raddr,
    input   logic   [63:0]  dfp_rdata,
    input   logic           dfp_rvalid
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_READ_REQ,
        ST_READ_WAIT,
        ST_WRITE_REQ,
        ST_WRITE_BURST
    } state_t;

    state_t state_q, state_d;

    logic           read_seen_q;
    logic           write_seen_q;
    logic   [31:0]  req_addr_q;
    logic   [255:0] req_wdata_q;
    logic   [255:0] resp_data_q;
    logic   [1:0]   read_beat_count_q;
    logic   [1:0]   write_beat_count_q;

    logic           read_req_valid;
    logic           write_req_valid;
    logic           idle_accept_req;
    logic           issue_read_from_idle;
    logic           issue_write_from_idle;
    logic           read_resp_accept;
    logic   [31:0]  active_req_addr;
    logic   [31:0]  line_addr;
    logic           read_addr_match;
    logic   [255:0] assembled_rdata;
    logic   [255:0] active_write_line;
    logic   [63:0]  write_beat_data;

    assign read_req_valid = ufp_read && !read_seen_q;
    assign write_req_valid = ufp_write && !write_seen_q;

    // 当前版本一次只处理一条 cacheline 请求。
    // 上层如果想发下一条请求，需要等当前 line 完整返回后再继续。
    assign idle_accept_req = (state_q == ST_IDLE) && (read_req_valid || write_req_valid);
    assign issue_read_from_idle = (state_q == ST_IDLE) && read_req_valid && dfp_ready;
    assign issue_write_from_idle = (state_q == ST_IDLE) && !read_req_valid && write_req_valid && dfp_ready;

    // 空闲拍接到新请求时，直接用 live addr/wdata 往下发，少掉首发前的空转拍。
    assign active_req_addr = idle_accept_req ? ufp_addr : req_addr_q;
    assign active_write_line = idle_accept_req ? ufp_wdata : req_wdata_q;

    // 上层即使已经给了对齐地址，这里仍然统一压成 line base address，保证对下层接口始终一致。
    assign line_addr = {active_req_addr[31:5], 5'b0};

    // 只接受当前正在等待的这条 line 的返回 beat。
    assign read_addr_match = (dfp_raddr[31:5] == req_addr_q[31:5]);
    assign read_resp_accept = (state_q == ST_READ_WAIT) && dfp_rvalid && read_addr_match;

    always_comb begin
        assembled_rdata = resp_data_q;
        if (read_resp_accept) begin
            unique case (read_beat_count_q)
                2'd0: assembled_rdata[63:0]    = dfp_rdata;
                2'd1: assembled_rdata[127:64]  = dfp_rdata;
                2'd2: assembled_rdata[191:128] = dfp_rdata;
                2'd3: assembled_rdata[255:192] = dfp_rdata;
                default: assembled_rdata = resp_data_q;
            endcase
        end
    end

    function automatic logic [63:0] line_beat(
        input logic [255:0] line_data,
        input logic [1:0]   beat_idx
    );
        begin
            unique case (beat_idx)
                2'd0: line_beat = line_data[63:0];
                2'd1: line_beat = line_data[127:64];
                2'd2: line_beat = line_data[191:128];
                2'd3: line_beat = line_data[255:192];
                default: line_beat = line_data[63:0];
            endcase
        end
    endfunction

    always_comb begin
        if (state_q == ST_WRITE_BURST) begin
            write_beat_data = line_beat(req_wdata_q, write_beat_count_q);
        end else begin
            write_beat_data = line_beat(active_write_line, 2'd0);
        end
    end

    always_comb begin
        state_d = state_q;

        unique case (state_q)
            ST_IDLE: begin
                if (idle_accept_req) begin
                    if (read_req_valid) begin
                        if (dfp_ready) begin
                            state_d = ST_READ_WAIT;
                        end else begin
                            state_d = ST_READ_REQ;
                        end
                    end else begin
                        if (dfp_ready) begin
                            state_d = ST_WRITE_BURST;
                        end else begin
                            state_d = ST_WRITE_REQ;
                        end
                    end
                end
            end

            ST_READ_REQ: begin
                if (dfp_ready) begin
                    state_d = ST_READ_WAIT;
                end
            end

            ST_READ_WAIT: begin
                if (read_resp_accept && (read_beat_count_q == 2'd3)) begin
                    state_d = ST_IDLE;
                end
            end

            ST_WRITE_REQ: begin
                if (dfp_ready) begin
                    state_d = ST_WRITE_BURST;
                end
            end

            ST_WRITE_BURST: begin
                if (write_beat_count_q == 2'd3) begin
                    state_d = ST_IDLE;
                end
            end

            default: begin
                state_d = ST_IDLE;
            end
        endcase
    end

    always_comb begin
        ufp_rdata = 256'b0;
        ufp_resp  = 1'b0;

        dfp_addr  = 32'b0;
        dfp_read  = 1'b0;
        dfp_write = 1'b0;
        dfp_wdata = 64'b0;

        unique case (state_q)
            ST_IDLE: begin
                if (issue_read_from_idle) begin
                    dfp_addr = line_addr;
                    dfp_read = 1'b1;
                end else if (issue_write_from_idle) begin
                    dfp_addr = line_addr;
                    dfp_write = 1'b1;
                    dfp_wdata = write_beat_data;
                end
            end

            ST_READ_REQ: begin
                dfp_addr = line_addr;
                if (dfp_ready) begin
                    dfp_read = 1'b1;
                end
            end

            ST_READ_WAIT: begin
                if (read_resp_accept && (read_beat_count_q == 2'd3)) begin
                    ufp_rdata = assembled_rdata;
                    ufp_resp = 1'b1;
                end
            end

            ST_WRITE_REQ: begin
                dfp_addr = line_addr;
                dfp_wdata = write_beat_data;
                if (dfp_ready) begin
                    dfp_write = 1'b1;
                end
            end

            ST_WRITE_BURST: begin
                dfp_addr = line_addr;
                dfp_wdata = write_beat_data;
                dfp_write = 1'b1;

                if (write_beat_count_q == 2'd3) begin
                    ufp_resp = 1'b1;
                end
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= ST_IDLE;
            read_seen_q <= 1'b0;
            write_seen_q <= 1'b0;
            req_addr_q <= 32'b0;
            req_wdata_q <= 256'b0;
            resp_data_q <= 256'b0;
            read_beat_count_q <= 2'b00;
            write_beat_count_q <= 2'b00;
        end else begin
            state_q <= state_d;

            if (!ufp_read) begin
                read_seen_q <= 1'b0;
            end else if (read_req_valid && (state_q == ST_IDLE)) begin
                read_seen_q <= 1'b1;
            end

            if (!ufp_write) begin
                write_seen_q <= 1'b0;
            end else if (write_req_valid && (state_q == ST_IDLE)) begin
                write_seen_q <= 1'b1;
            end

            if (idle_accept_req) begin
                req_addr_q <= ufp_addr;
                req_wdata_q <= ufp_wdata;
                resp_data_q <= 256'b0;
                read_beat_count_q <= 2'b00;
                write_beat_count_q <= 2'b00;
            end

            if (read_resp_accept) begin
                // beat0/1/2 先存起来；beat3 在同拍和前 3 个一起拼成完整 line 返回。
                unique case (read_beat_count_q)
                    2'd0: resp_data_q[63:0] <= dfp_rdata;
                    2'd1: resp_data_q[127:64] <= dfp_rdata;
                    2'd2: resp_data_q[191:128] <= dfp_rdata;
                    default: resp_data_q <= resp_data_q;
                endcase

                if (read_beat_count_q != 2'd3) begin
                    read_beat_count_q <= read_beat_count_q + 2'd1;
                end else begin
                    read_beat_count_q <= 2'b00;
                end
            end

            if (issue_write_from_idle || ((state_q == ST_WRITE_REQ) && dfp_ready)) begin
                write_beat_count_q <= 2'd1;
            end else if (state_q == ST_WRITE_BURST) begin
                if (write_beat_count_q == 2'd3) begin
                    write_beat_count_q <= 2'b00;
                end else begin
                    write_beat_count_q <= write_beat_count_q + 2'd1;
                end
            end
        end
    end

endmodule : cacheline_adapter
