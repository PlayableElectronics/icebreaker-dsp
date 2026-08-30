// src/periph/frame_receiver.sv
// UART-based binary frame receiver for resynthesis frames.
// Protocol:
//  0xF0 START_FRAME
//  1 byte COUNT (number of entries)
//  For each entry: PHASE_INC(4 bytes BE), AMP(2 bytes BE), FLAGS(1 byte)
//  0xF1 COMMIT -> swap buffers
//  Replies:
//   - 0xA1 frame accepted (after all entries parsed)
//   - 0xA2 commit accepted
//   - 0xA3 echo first entry (6 bytes: PHASE_INC+AMP)

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

    // States
    typedef enum logic [1:0] {S_IDLE=2'd0, S_COUNT=2'd1, S_ENTRY=2'd2} state_t;
    state_t state;

    reg [7:0] count;            // number of entries expected
    reg [4:0] write_ptr;        // current entry index being written
    reg [2:0] entry_byte_idx;   // 0..6 (7 bytes per entry)
    reg [7:0] entry_buf [0:6];  // temporary storage for one entry

    // For echoing first entry back to host
    reg first_entry_valid;
    reg [47:0] first_entry_data;

    // initialization
    initial begin
        state = S_IDLE;
        count = 8'd0;
        write_ptr = 5'd0;
        entry_byte_idx = 3'd0;
        fb_write_en = 1'b0;
        fb_write_addr = 5'd0;
        fb_write_data = 48'd0;
        commit_req = 1'b0;
        tx_req = 1'b0;
        tx_byte = 8'd0;
        first_entry_valid = 1'b0;
        first_entry_data = 48'd0;
    end

    always @(posedge clk) begin
        // default outputs are deasserted each clock
        fb_write_en <= 1'b0;
        commit_req <= 1'b0;
        tx_req <= 1'b0;

        if (rx_valid) begin
            case (state)
                S_IDLE: begin
                    if (rx_data == 8'hF0) begin
                        // start frame
                        state <= S_COUNT;
                        write_ptr <= 5'd0;
                        first_entry_valid <= 1'b0;
                    end else if (rx_data == 8'hF1) begin
                        // commit request
                        commit_req <= 1'b1;
                        tx_req <= 1'b1;
                        tx_byte <= 8'hA2; // commit ack
                    end else if (rx_data == 8'hF2) begin
                        // freeze toggle (not implemented fully)
                        tx_req <= 1'b1;
                        tx_byte <= 8'hA4; // freeze ack
                    end else begin
                        // ignore
                    end
                end

                S_COUNT: begin
                    count <= rx_data;
                    entry_byte_idx <= 3'd0;
                    write_ptr <= 5'd0;
                    if (rx_data == 8'd0) begin
                        // empty frame: acknowledge and return to idle
                        tx_req <= 1'b1;
                        tx_byte <= 8'hA1; // frame ack
                        state <= S_IDLE;
                    end else begin
                        state <= S_ENTRY;
                    end
                end

                S_ENTRY: begin
                    // collect entry bytes: 7 bytes per entry
                    entry_buf[entry_byte_idx] <= rx_data;
                    entry_byte_idx <= entry_byte_idx + 1'b1;

                    if (entry_byte_idx == 3'd6) begin
                        // we've just written the 7th byte (flags). Assemble the 6-byte write_data
                        // PHASE_INC: entry_buf[0..3], AMP: entry_buf[4..5]
                        fb_write_en <= 1'b1;
                        fb_write_addr <= write_ptr;
                        fb_write_data <= {entry_buf[0], entry_buf[1], entry_buf[2], entry_buf[3], entry_buf[4], entry_buf[5]};

                        // capture first entry for echo
                        if (!first_entry_valid) begin
                            first_entry_valid <= 1'b1;
                            first_entry_data <= fb_write_data;
                        end

                        write_ptr <= write_ptr + 1'b1;

                        // finished one entry; decide next state
                        if (write_ptr + 1'b1 >= count) begin
                            // last entry written
                            tx_req <= 1'b1;
                            tx_byte <= 8'hA1; // frame ack
                            state <= S_IDLE;
                        end else begin
                            // more entries expected
                            entry_byte_idx <= 3'd0;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end

        // If commit happens while in any state, commit_req handling is done in S_IDLE via rx_data==F1
    end

endmodule
