// src/periph/frame_buffer.sv
// Dual ping-pong buffer for resynthesis frames. Simple atomic swap on commit.
module frame_buffer #(
    parameter integer DEPTH = 32
) (
    input  wire           clk,

    // write interface (writes always target the inactive buffer)
    input  wire           write_en,
    input  wire  [4:0]    write_addr, // 0..31
    input  wire [47:0]    write_data,

    // commit: pulse to swap inactive -> active atomically
    input  wire           commit_req,
    output reg            commit_ack,

    // read interface (reads always come from the active buffer)
    input  wire  [4:0]    read_addr,
    output reg  [47:0]    read_data,

    // status
    output reg            active_sel // 0 => buf0 active, 1 => buf1 active
);

    // internal memory
    reg [47:0] buf0 [0:DEPTH-1];
    reg [47:0] buf1 [0:DEPTH-1];

    // inactive selector
    wire inactive_sel = ~active_sel;

    integer i;
    initial begin
        active_sel = 1'b0;
        commit_ack = 1'b0;
        for (i = 0; i < DEPTH; i = i + 1) begin
            buf0[i] = 48'd0;
            buf1[i] = 48'd0;
        end
    end

    // Write port: target inactive buffer
    always @(posedge clk) begin
        if (write_en) begin
            if (inactive_sel == 1'b0) begin
                buf0[write_addr] <= write_data;
            end else begin
                buf1[write_addr] <= write_data;
            end
        end
    end

    // Commit: toggle active_sel on rising edge of commit_req
    reg commit_req_d;
    always @(posedge clk) begin
        commit_ack <= 1'b0;
        commit_req_d <= commit_req;
        if (commit_req && !commit_req_d) begin
            // commit rising edge: swap buffers
            active_sel <= ~active_sel;
            commit_ack <= 1'b1;
        end
    end

    // Read port: synchronous read of active buffer
    always @(posedge clk) begin
        if (active_sel == 1'b0)
            read_data <= buf0[read_addr];
        else
            read_data <= buf1[read_addr];
    end

endmodule
