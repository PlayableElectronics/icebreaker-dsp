module scanned_voice #(
    parameter N = 32
)(
    input wire clk,
    input wire audio_tick,

    input wire strike,
    input wire [7:0] strike_amp,
    input wire [7:0] strike_width,
    input wire [4:0] strike_pos,

    input wire [23:0] scan_inc,

    input wire [7:0] kn,
    input wire [7:0] ke,
    input wire [7:0] damping,

    output reg signed [15:0] sample
);
