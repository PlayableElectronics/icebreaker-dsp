//////////////////////////////////////////////////////////////////////////////
// iCEBreaker single sine oscillator -> PCM5102A (I2S DAC) on PMOD1A
//
//  Mirror of the proven ice40_audio architecture:
//    - phase accumulator advances on EVERY master clock
//    - synchronous wavetable read, sample re-latched every clock
//      => the sample always tracks the current phase (no frame race)
//    - I2S serializer (BCK / LRCK / DIN) driving the PCM5102
//
//  PMOD1A => DAC wiring (see icebreaker.pcf / README):
//    BCK  <- FPGA pin 4   (PCM5102 bit clock)
//    LRCK <- FPGA pin 2   (PCM5102 word select)
//    DIN  <- FPGA pin 47  (PCM5102 serial data)
//    XSMT <- FPGA pin 3   (PCM5102 soft mute, high = un-muted)
//////////////////////////////////////////////////////////////////////////////

module top (
    input  wire CLK,
    output wire bclk,
    output wire lrck,
    output wire dout,
    output wire xmute,
    output wire LEDR_N
);

    // ------- DAC soft-mute: high = audio output enabled -------
    assign xmute = 1'b1;

    //====================================================================
    // DDS phase accumulator, advances EVERY clock (12 MHz).
    //   tuning word = round(freq * 2^32 / 12e6)
    //   phase[31:22] scans the 1024-entry wavetable -> 220 Hz
    //====================================================================
    localparam [31:0] TW = 32'd78741;   // A3 = 220.00 Hz

    reg [31:0] phase = 32'd0;
    always @(posedge CLK) phase <= phase + TW;

    //====================================================================
    // Sine wavetable in BRAM: 1024 x 16, synchronous read.
    //   adv address = phase top bits; sample re-latched every clock.
    //====================================================================
    reg [15:0] sine_table [0:1023];
    initial $readmemh("src/mem/sine.mem", sine_table);

    reg [9:0]  waddr = 10'd0;
    wire [15:0] wdata = sine_table[waddr];
    always @(posedge CLK) waddr <= phase[31:22];

    reg signed [15:0] sample = 16'sd0;
    always @(posedge CLK) sample <= $signed(wdata);

    //====================================================================
    // I2S serializer (proven pattern from ice40_audio PCM5102 module).
    //   frame: 32 bits = 2 channels x 16 bits, MSB first
    //     62.5 kHz frame rate (12 MHz / 64)
    //   BCK  = frame bit 0  (~6 MHz bit clock)
    //   LRCK = frame bit 5  (word clock), mono sample on both channels
    //   DIN  = active channel bit selected by frame counter
    //====================================================================
    reg [5:0] i2s = 6'd0;
    always @(posedge CLK) i2s <= i2s + 6'd1;

    assign bclk = i2s[0];
    assign lrck = i2s[5];
    assign dout = sample[16 - i2s[4:1]];

    // ------- Status LED (diagnostic, blinks with audio sign) -------
    assign LEDR_N = ~sample[15];

endmodule
