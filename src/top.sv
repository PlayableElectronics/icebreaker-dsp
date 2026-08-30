//////////////////////////////////////////////////////////////////////////////
// iCEBreaker sine oscillator bank -> PCM5102A (I2S DAC) on PMOD1A
//
//  - 8 DDS sine oscillators mixed into mono, 16-bit signed samples
//  - I2S transmitter (BCK / LRCK / DIN) at Fs = 46.875 kHz
//  - sample rate driven from the 12 MHz board clock
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
    // I2S bit/word clock generation
    //   Fs   = 12 MHz / 256 = 46.875 kHz
    //   One sample frame = 256 master clocks = 2 channels x 16 bits
    //   BCK  = 1 bit per 8 master clocks (~3 MHz)
    //   LRCK = 46.875 kHz word clock
    //====================================================================
    reg [7:0] mclk_cnt = 8'd0;
    always @(posedge CLK) mclk_cnt <= mclk_cnt + 8'd1;

    wire byte_clk = (mclk_cnt[2:0] == 3'b0);   // one pulse per 8 clocks
    assign bclk = mclk_cnt[2];                 // 3 MHz bit clock
    assign lrck = mclk_cnt[7];                 // 46.875 kHz word clock

    // one pulse at end of each 256-clock frame (advance DDS phases)
    wire sample_pulse = (mclk_cnt == 8'd255);
    // start the mix lookup one clock later, once all phases have updated
    wire start_mix = (mclk_cnt == 8'd0);

    //====================================================================
    // Sine lookup table: 1024 x 16 bit, synchronous read (inferred BRAM)
    //====================================================================
    reg [9:0]  rd_addr = 10'd0;
    reg [15:0] rd_data = 16'd0;
    reg [15:0] rom_mem [0:1023];
    initial $readmemh("src/mem/sine.mem", rom_mem);
    always @(posedge CLK) rd_data <= rom_mem[rd_addr];

    //====================================================================
    // DDS phase accumulators (8 voices)
    //   tuning word = round(freq * 2^32 / Fs), Fs = 46875 Hz
    //====================================================================
    localparam [31:0] TW0 = 32'd10078857;   // A2   110.00 Hz
    localparam [31:0] TW1 = 32'd12698443;   // C#3  138.59 Hz
    localparam [31:0] TW2 = 32'd15100876;   // E3   164.81 Hz
    localparam [31:0] TW3 = 32'd20157713;   // A3   220.00 Hz
    localparam [31:0] TW4 = 32'd22626117;   // B3   246.94 Hz
    localparam [31:0] TW5 = 32'd23972102;   // C4   261.63 Hz
    localparam [31:0] TW6 = 32'd30202668;   // E4   329.63 Hz
    localparam [31:0] TW7 = 32'd40315426;   // A4   440.00 Hz

    reg [31:0] phase [0:7];
    integer p;
    initial for (p = 0; p < 8; p = p + 1) phase[p] = 32'd0;
    always @(posedge CLK) begin
        if (sample_pulse) begin
            phase[0] <= phase[0] + TW0;
            phase[1] <= phase[1] + TW1;
            phase[2] <= phase[2] + TW2;
            phase[3] <= phase[3] + TW3;
            phase[4] <= phase[4] + TW4;
            phase[5] <= phase[5] + TW5;
            phase[6] <= phase[6] + TW6;
            phase[7] <= phase[7] + TW7;
        end
    end

    //====================================================================
    // Sequential sine lookup over the 8 voices and running sum.
    // Pipeline: set rd_addr[voice] -> next cycle rd_data -> accumulate.
    //====================================================================
    reg [3:0] ri      = 4'd0;    // read index 0..7
    reg       reading = 1'b0;
    reg       finalize= 1'b0;
    reg signed [21:0] acc = 22'sd0;   // sum of 8 signed voices (±262144)
    reg signed [18:0] mix = 19'sd0;   // acc / 8 (16-bit audio + guard)

    always @(posedge CLK) begin
        if (start_mix) begin
            reading  <= 1'b1;
            finalize <= 1'b0;
            ri       <= 4'd0;
            acc      <= 22'sd0;
        end else if (reading) begin
            // convert unsigned[0..65535] sine to signed[-32768..32767], accumulate
            acc <= acc + $signed({1'b0, rd_data}) - 17'sd32768;
            if (ri == 4'd7) begin
                reading  <= 1'b0;
                finalize <= 1'b1;
                ri       <= 4'd0;
            end else begin
                ri <= ri + 4'd1;
            end
        end else if (finalize) begin
            finalize <= 1'b0;
            mix <= $signed(acc) >>> 3;   // divide by 8 (arithmetic shift)
        end

        // address the sine ROM with the phase of the current voice
        case (ri)
            4'd0: rd_addr <= phase[0][31:22];
            4'd1: rd_addr <= phase[1][31:22];
            4'd2: rd_addr <= phase[2][31:22];
            4'd3: rd_addr <= phase[3][31:22];
            4'd4: rd_addr <= phase[4][31:22];
            4'd5: rd_addr <= phase[5][31:22];
            4'd6: rd_addr <= phase[6][31:22];
            default: rd_addr <= phase[7][31:22];
        endcase
    end

    // 16-bit signed sample (saturate to hardware range)
    wire signed [15:0] sample =
        (mix > 19'sd32767) ? 16'sd32767 :
        (mix < -19'sd32768) ? (-16'sd32768) :
        mix[15:0];

    //====================================================================
    // I2S serialiser (mono duplicated on both channels, MSB first)
    //   load a fresh copy of the sample at each channel boundary
    //   (mclk_cnt == 0 and == 128), then shift out 16 bits on byte_clk.
    //====================================================================
    reg [15:0] sreg = 16'd0;
    wire load_sample = (mclk_cnt[6:0] == 7'd0);   // channel start: 0 or 128
    always @(posedge CLK) begin
        if (load_sample) begin
            sreg <= sample;
        end else if (byte_clk) begin
            sreg <= {sreg[14:0], 1'b0};   // shift out MSB first
        end
    end
    assign dout = sreg[15];

    // ------- Status LED (diagnostic, blinks with audio sign) -------
    assign LEDR_N = ~sample[15];

endmodule
