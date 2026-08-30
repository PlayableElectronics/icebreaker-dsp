// src/periph/frame_receiver.sv
// UART-based binary frame receiver for resynthesis frames.
// Protocol (simple):
//  0xF0 START_FRAME
//  1 byte COUNT (number of entries)
//  for i in 0..COUNT-1: ENTRY = [PHASE_INC(4 bytes BE), AMP(2 bytes BE), FLAGS(1 byte)]
//  0xF1 COMMIT command (swap buffers)
//  0xF2 FREEZE toggle (not implemented in depth here)
// After COMMIT the receiver will request a tx ACK (single byte 0x01)

module frame_receiver (
    input  wire        clk,
    input  wire        rx_valid,
    input  wire [7:0]  rx_data,

    // write interface to frame_buffer (inactive buffer)
    output reg         fb_write_en,
    output reg  [4:0]  fb_write_addr,
    output reg [47:0]  fb_write_data,

    // commit request pulse (one clock)
    output reg         commit_req,

    // simple TX ACK request: when tx_req pulses, top should place tx_byte on uart_tx_data
    output reg         tx_req,
    output reg [7:0]   tx_byte
);

    // parser state
    localparam S_IDLE = 0;
    localparam S_COUNT = 1;
    localparam S_ENTRY = 2;
    localparam S_WAIT = 3;

    reg [1:0] state;
    reg [7:0] count;
    reg [7:0] entry_buf [0:6]; // 7 bytes per entry
    reg [2:0] entry_idx;
    reg [7:0] byte_cnt;
    reg [4:0] write_ptr;

    initial begin
        state = S_IDLE;
        count = 0;
        entry_idx = 0;
        byte_cnt = 0;
        write_ptr = 5'd0;
        fb_write_en = 1'b0;
        fb_write_addr = 5'd0;
        fb_write_data = 48'd0;
        commit_req = 1'b0;
        tx_req = 1'b0;
        tx_byte = 8'd0;
    end

    always @(posedge clk) begin
        fb_write_en <= 1'b0;
        commit_req <= 1'b0;
        tx_req <= 1'b0;

        if (rx_valid) begin
            case (state)
                S_IDLE: begin
                    if (rx_data == 8'hF0) begin
                        state <= S_COUNT;
                        write_ptr <= 5'd0;
                    end else if (rx_data == 8'hF1) begin
                        // commit
                        commit_req <= 1'b1;
                        tx_req <= 1'b1;
                        tx_byte <= 8'h01; // ack
                        state <= S_IDLE;
                    end else if (rx_data == 8'hF2) begin
                        // freeze toggle (not fully implemented here)
                        // send ack
                        tx_req <= 1'b1;
                        tx_byte <= 8'h02;
                    end else begin
                        // ignore unknown bytes
                        state <= S_IDLE;
                    end
                end

                S_COUNT: begin
                    count <= rx_data;
                    byte_cnt <= 0;
                    entry_idx <= 0;
                    state <= (rx_data == 0) ? S_IDLE : S_ENTRY;
                end

                S_ENTRY: begin
                    // collect entry bytes: 7 bytes per entry
                    entry_buf[entry_idx] <= rx_data;
                    entry_idx <= entry_idx + 1;
                    if (entry_idx == 3'd6) begin
                        // assemble write_data: bytes 0..6
                        // mapping: PHASE_INC (4 bytes) -> bits [47:16]
                        //          AMP (2 bytes) -> bits [15:0]
                        //          FLAGS (1 byte) -> ignored or kept LSBs of AMP upper
                        reg [47:0] w;
                        w = {entry_buf[0], entry_buf[1], entry_buf[2], entry_buf[3], entry_buf[4], entry_buf[5]};
                        // entry_buf[6] is flags; we ignore for now
                        fb_write_en <= 1'b1;
                        fb_write_addr <= write_ptr;
                        fb_write_data <= w;
                        write_ptr <= write_ptr + 5'd1;
                        // next entry or finish
                        if (write_ptr + 5'd1 >= count) begin
                            state <= S_IDLE;
                            // optional: tx ack of frame received
                            tx_req <= 1'b1;
                            tx_byte <= 8'hAA;
                        end else begin
                            entry_idx <= 3'd0;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
