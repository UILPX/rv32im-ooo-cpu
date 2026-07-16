module cache_ooo_bridge
import rv32im_types::*;
#(
    parameter integer CACHE_SOURCE = 1,
    parameter logic   WRITE_CRITICAL = 1'b1
)(
    input   logic               clk,
    input   logic               rst,

    input   logic   [31:0]      ufp_addr,
    input   logic               ufp_read,
    input   logic               ufp_write,
    output  logic   [255:0]     ufp_rdata,
    input   logic   [255:0]     ufp_wdata,
    output  logic               ufp_resp,
    input   logic               read_is_prefetch,
    input   logic               read_critical,

    output  logic               mem_req_valid,
    input   logic               mem_req_ready,
    output  cache_mem_req_t     mem_req,
    input   logic               mem_resp_valid,
    output  logic               mem_resp_ready,
    input   cache_mem_resp_t    mem_resp
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_ACCEPT,
        ST_WAIT_RESP
    } state_t;

    state_t             state_q, state_d;
    cache_mem_req_t     req_q;
    logic               read_seen_q;
    logic               write_seen_q;
    logic               read_req_valid;
    logic               write_req_valid;
    logic               new_req_valid;
    logic               new_req_is_read;
    cache_mem_req_t     live_req;

    assign read_req_valid = ufp_read && !read_seen_q;
    assign write_req_valid = ufp_write && !write_seen_q;
    assign new_req_valid = read_req_valid || write_req_valid;
    assign new_req_is_read = read_req_valid;

    always_comb begin
        live_req = '0;
        live_req.src = cache_src_t'(CACHE_SOURCE);
        live_req.line_addr = {ufp_addr[31:5], 5'b0};
        live_req.line_wdata = ufp_wdata;

        if (new_req_is_read) begin
            live_req.kind = read_is_prefetch ? cache_req_prefetch_read : cache_req_demand_read;
            live_req.critical = read_critical;
        end else begin
            live_req.kind = cache_req_writeback;
            live_req.critical = WRITE_CRITICAL;
        end
    end

    always_comb begin
        state_d = state_q;

        unique case (state_q)
            ST_IDLE: begin
                if (new_req_valid) begin
                    if (mem_req_ready) begin
                        state_d = ST_WAIT_RESP;
                    end else begin
                        state_d = ST_WAIT_ACCEPT;
                    end
                end
            end

            ST_WAIT_ACCEPT: begin
                if (mem_req_ready) begin
                    state_d = ST_WAIT_RESP;
                end
            end

            ST_WAIT_RESP: begin
                if (mem_resp_valid) begin
                    state_d = ST_IDLE;
                end
            end

            default: begin
                state_d = ST_IDLE;
            end
        endcase
    end

    always_comb begin
        mem_req_valid = 1'b0;
        mem_req = '0;
        mem_resp_ready = 1'b0;
        ufp_rdata = 256'b0;
        ufp_resp = 1'b0;

        unique case (state_q)
            ST_IDLE: begin
                if (new_req_valid) begin
                    mem_req_valid = 1'b1;
                    mem_req = live_req;
                end
            end

            ST_WAIT_ACCEPT: begin
                mem_req_valid = 1'b1;
                mem_req = req_q;
            end

            ST_WAIT_RESP: begin
                mem_resp_ready = 1'b1;
                if (mem_resp_valid) begin
                    ufp_rdata = mem_resp.line_data;
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
            req_q <= '0;
            read_seen_q <= 1'b0;
            write_seen_q <= 1'b0;
        end else begin
            state_q <= state_d;

            if (!ufp_read) begin
                read_seen_q <= 1'b0;
            end else if ((state_q == ST_IDLE) && read_req_valid) begin
                read_seen_q <= 1'b1;
            end

            if (!ufp_write) begin
                write_seen_q <= 1'b0;
            end else if ((state_q == ST_IDLE) && !read_req_valid && write_req_valid) begin
                write_seen_q <= 1'b1;
            end

            if ((state_q == ST_IDLE) && new_req_valid) begin
                req_q <= live_req;
            end
        end
    end

endmodule : cache_ooo_bridge
