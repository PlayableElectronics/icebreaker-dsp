//////////////////////////////////////////////////////////////////////////////
// iCEBreaker sine oscillator BANK -> PCM5102A (I2S DAC) on PMOD1A
//
//  Multi-voice DDS bank using the clean every-clock phase pattern
//  (mirrors proven ice40_audio architecture; no trough/frame glitch):
//    - each oscillator's phase accumulator advances on EVERY master clock
//    - the single-port BRAM wavetable is time-multiplexed across voices
//      each master clock, accumulated, scaled, and sent to the I2S driver
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
    // Number of voices and NRD_CH tuning words.
    //   tuning word = round(freq * 2^32 / 12e6)  (advance per 12 MHz clock)
    //====================================================================
    localparam integer NVOICE = 8;

    localparam [31:0] TW0 = 32'd39371;    // A2   110.00 Hz
    localparam [31:0] TW1 = 32'd49603;    // C#3  138.59 Hz
    localparam [31:0] TW2 = 32'd58988;    // E3   164.81 Hz
    localparam [31:0] TW3 = 32'd78741;    // A3   220.00 Hz
    localparam [31:0] TW4 = 32'd88383;    // B3   246.94 Hz
    localparam [31:0] TW5 = 32'd93641;    // C4   261.63 Hz
    localparam [31:0] TW6 = 32'd117979;   // E4   329.63 Hz
    localparam [31:0] TW7 = 32'd157482;   // A4   440.00 Hz

    //====================================================================
    // LFO (also an oscillator): slow phasor advancing EVERY clock.
    //   Its sine output scales a "modulation offset" added to every
    //   carrier's per-clock tuning word => each carrier osc is frequency
    //   modulated by a sub-audio LFO osc (audio-rate FM = phase modulation).
    //     TLFO = round(lfo_hz * 2^32 / 12e6)
    //   LFO_SHIFT scales the sine sample down to a tuning-word-sized offset.
    //====================================================================
    localparam [31:0] TLFO      = 32'd2147;   // ~6 Hz
    localparam integer LFO_SHIFT = 4;          // max |offset| ~ +/-2048 TW units

    reg [31:0] lfo_phase = 32'd0;
    always @(posedge CLK) lfo_phase <= lfo_phase + TLFO;

    // LFO is itself an oscillator: its own small 256-entry sine wavetable
    // (kept separate from the carrier table so each keeps a single read port
    //  and the carrier stays in BRAM).
    reg [15:0] lfo_lut [0:255];
    initial $readmemh("src/mem/lfo.mem", lfo_lut);
    wire [15:0] lfo_cos = lfo_lut[lfo_phase[31:24]];

    // Scale the LFO sine (offset-then-shift) to a tuning-word-sized FM offset.
    wire signed [31:0] lfo_off = ($signed({1'b0, lfo_cos}) - 32'sd32768) >>> LFO_SHIFT;

    //====================================================================
    // DDS phase accumulators, each advances EVERY clock.
    //   phase[i][31:22] scans the 1024-entry wavetable at voice i's pitch
    //   Each voice's tuning word is nudged by the LFO offset each clock.
    //====================================================================
    reg [31:0] phase [0:7];
    integer p;
    initial for (p = 0; p < 8; p = p + 1) phase[p] = 32'd0;
    always @(posedge CLK) begin
        phase[0] <= phase[0] + TW0 + lfo_off;
        phase[1] <= phase[1] + TW1 + lfo_off;
        phase[2] <= phase[2] + TW2 + lfo_off;
        phase[3] <= phase[3] + TW3 + lfo_off;
        phase[4] <= phase[4] + TW4 + lfo_off;
        phase[5] <= phase[5] + TW5 + lfo_off;
        phase[6] <= phase[6] + TW6 + lfo_off;
        phase[7] <= phase[7] + TW7 + lfo_off;
    end

    //====================================================================
    // Sine wavetable in BRAM: 1024 x 16, synchronous read.
    //====================================================================
    reg [15:0] sine_table [0:1023];
    initial $readmemh("src/mem/sine.mem", sine_table);

    //====================================================================
    // Time-multiplexed wavetable reads + running sum.
    //   slot  : 0..NVOICE-1, addresses phase[slot] each clock
    //   slot_d: slot delayed 1 clock (waddr latency)
    //   slot_dd: slot delayed 2 clocks (matches wdata's BRAM read latency)
    //   acc   : accumulates each voice's signed sine value
    // One complete NVOICE-voice sum is latched each cycle.
    //====================================================================
    localparam [3:0] NM1 = NVOICE - 1;

    reg [2:0]  slot  = 3'd0;
    reg [2:0]  slot_d= 3'd0;
    reg [2:0]  slot_dd=3'd0;
    reg [9:0]  waddr = 10'd0;
    reg [15:0] wdata = 16'd0;          // synchronous (registered) ROM read -> BRAM
    reg signed [21:0] acc = 22'sd0;
    reg signed [15:0] sample = 16'sd0;

    always @(posedge CLK) begin
        slot   <= slot + 3'd1;
        slot_d <= slot;
        slot_dd<= slot_d;             // matches wdata latency (2 clocks after addr)
        waddr  <= phase[slot][31:22];
        wdata  <= sine_table[waddr];  // BRAM synchronous read port

        if (slot_dd == NM1) begin
            // last voice: acc holds first N-1, add N-1 and scale by 1/N
            acc    <= 22'sd0;          // reset accumulator for next cycle
            sample <= (acc + $signed({1'b0, wdata}) - 17'sd32768) >>> 3;
        end else begin
            acc <= acc + $signed({1'b0, wdata}) - 17'sd32768;
        end
    end

    //====================================================================
    // I2S serializer (proven pattern from ice40_audio PCM5102 module).
    //   frame: 32 bits = 2 channels x 16 bits, MSB first (~62.5 kHz)
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
