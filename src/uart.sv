//////////////////////////////////////////////////////////////////////////////
// uart.sv - minimal 8-N-1 UART RX + TX core
//
//  Single clock domain, parameterised baud rate. Standard asynchronous
//  byte-serial link used to talk to the host over the iCEBreaker's onboard
//  FT2232H (Channel B) -> virtual COM port on the PC.
//
//  RX: oversampled start-bit detect, samples each bit at its centre.
//  TX: shift-out start + 8 data (LSB first) + stop.
//  No FIFO: a new RX byte is presented on rx_valid (one clock pulse).
//  TX accepts one byte when tx_busy is low on tx_go.
//////////////////////////////////////////////////////////////////////////////

module uart #(
    parameter integer CLK_HZ = 12_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,

    // ---- RX ----
    input  wire       rx,
    output reg        rx_valid,          // one-clock pulse when a byte arrives
    output reg  [7:0] rx_data,

    // ---- TX ----
    input  wire       tx_go,             // pulse (when !tx_busy) to send a byte
    input  wire [7:0] tx_data,
    output reg        tx_busy,
    output wire       tx                 // serial out (idle high)
);

    reg tx_line = 1'b1;
    assign tx = tx_line;

    // Ticks per UART bit. 115200 @ 12 MHz -> 104 (0.08% error, fine for UART).
    localparam integer BAUD_TICKS = CLK_HZ / BAUD;
    localparam integer HALF_TICKS = BAUD_TICKS / 2;

    //========================================================================
    // RX
    //========================================================================
    reg [1:0] rx_sync = 2'b11;             // double-synchronise async input
    wire rx_line = rx_sync[1];             // sampled RX line (1 = idle)

    localparam integer RX_IDLE  = 0;
    localparam integer RX_START = 1;
    localparam integer RX_DATA  = 2;
    localparam integer RX_STOP  = 3;
    reg [1:0] rx_state = RX_IDLE;
    reg [10:0] rx_cnt  = 0;
    reg [2:0]  rx_bit  = 0;                // which data bit we're collecting
    reg [7:0]  rx_shr  = 0;

    always @(posedge clk) begin
        rx_sync <= {rx_sync[0], rx};
        rx_valid <= 1'b0;                  // default: no new byte this cycle

        case (rx_state)
            RX_IDLE: begin
                rx_cnt <= 0;
                rx_bit <= 0;
                if (rx_line == 1'b0)       // falling edge = start bit
                    rx_state <= RX_START;
            end

            RX_START: begin
                if (rx_cnt == HALF_TICKS-1) begin
                    rx_cnt <= 0;
                    // Confirm start still low once reached bit centre.
                    if (rx_line == 1'b0)
                        rx_state <= RX_DATA;
                    else
                        rx_state <= RX_IDLE;
                end else begin
                    rx_cnt <= rx_cnt + 1;
                end
            end

            RX_DATA: begin
                if (rx_cnt == BAUD_TICKS-1) begin
                    rx_cnt <= 0;
                    rx_shr <= {rx_line, rx_shr[7:1]};   // LSB first
                    if (rx_bit == 3'd7)
                        rx_state <= RX_STOP;
                    else
                        rx_bit <= rx_bit + 1;
                end else begin
                    rx_cnt <= rx_cnt + 1;
                end
            end

            RX_STOP: begin
                if (rx_cnt == BAUD_TICKS-1) begin
                    rx_cnt   <= 0;
                    rx_state <= RX_IDLE;
                    rx_data  <= rx_shr;
                    rx_valid <= 1'b1;       // frame complete
                end else begin
                    rx_cnt <= rx_cnt + 1;
                end
            end
        endcase
    end

    //========================================================================
    // TX - count off BAUD_TICKS per bit, 10 bits: start, 8 data, stop.
    //========================================================================
    localparam integer TX_IDLE = 0;
    localparam integer TX_ACT  = 1;
    reg       tx_state = TX_IDLE;
    reg [10:0] tx_cnt  = 0;                // ticks elapsed within current bit
    reg [3:0]  tx_bit  = 0;                // bit index 0..9
    reg [7:0]  tx_shr  = 0;

    always @(posedge clk) begin
        case (tx_state)
            TX_IDLE: begin
                tx_line <= 1'b1;
                tx_busy <= 1'b0;
                tx_cnt  <= 0;
                tx_bit  <= 0;
                if (tx_go) begin
                    tx_shr   <= tx_data;
                    tx_busy  <= 1'b1;
                    tx_line  <= 1'b0;      // drive start bit
                    tx_cnt   <= 1;
                    tx_state <= TX_ACT;
                end
            end

            TX_ACT: begin
                // Current bit value:
                //   bit 0 = start (0), bits 1..8 = data, bit 9 = stop (1)
                if (tx_cnt == BAUD_TICKS) begin
                    // Bit period finished: advance, or finish after stop.
                    if (tx_bit == 4'd9) begin
                        tx_state <= TX_IDLE;
                        tx_busy  <= 1'b0;
                        tx_line  <= 1'b1;
                    end else begin
                        tx_bit  <= tx_bit + 1;
                        tx_cnt  <= 1;
                        // Drive next bit's line value.
                        if (tx_bit == 4'd8)
                            tx_line <= 1'b1;          // stop bit
                        else begin
                            tx_shr  <= {1'b0, tx_shr[7:1]};   // advance LSB first
                            tx_line <= tx_shr[0];
                        end
                    end
                end else begin
                    tx_cnt <= tx_cnt + 1;
                end
            end
        endcase
    end

endmodule
