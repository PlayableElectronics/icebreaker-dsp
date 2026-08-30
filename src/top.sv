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
    output wire LEDR_N,
    // ---- UART to host (onboard FT2232H channel B, virtual COM port) ----
    input  wire uart_rx,        // FPGA pin 6  (PC -> FPGA)
    output wire uart_tx         // FPGA pin 9  (FPGA -> PC)
);

    // ------- DAC soft-mute: high = audio output enabled -------
    assign xmute = 1'b1;

    //====================================================================
    // Number of voices and NRD_CH tuning words.
    //   tuning word = round(freq * 2^32 / 12e6)  (advance per 12 MHz clock)
    //====================================================================
    localparam integer NVOICE = 8;

    //====================================================================
    // Host parameter map (UART -> synth controls). See index.html.
    //   Frame = [SYNC 0xEE][PARAM][VALUE]; params[PARAM] = VALUE.
    //====================================================================
    localparam [7:0] P_SYNC     = 8'hEE;
    localparam [7:0] P_LFO_RATE = 8'h10;   // 0..255: host_tlfo = V * TLFO
    localparam [7:0] P_LFO_DEPTH= 8'h11;   // 0..15 : FM depth (0 deep, 15 shallow)
    localparam [7:0] P_VOICE0   = 8'h20;   // +0..7 : per-osc level (0..255)
    localparam [7:0] P_DETUNE0  = 8'h30;   // +0..7 : per-osc detune (128 = x1.0)

    // Host parameter store: 64 x 8 (covers LFO, levels, detunes). Only the
    // high-5-bit param IDs above are used; 64 keeps the register cost small.
    reg [7:0] params [0:63];
    integer pi;
    initial begin
        for (pi = 0; pi < 64; pi = pi + 1) params[pi] = 8'd0;
        params[P_LFO_RATE]  = 8'd1;    // 1 * TLFO = ~6 Hz
        params[P_LFO_DEPTH] = 8'd4;    // LFO_SHIFT
        for (pi = 0; pi < 8; pi = pi + 1) begin
            params[P_VOICE0 + pi]  = 8'd255;   // level full
            params[P_DETUNE0 + pi] = 8'd128;   // pitch normal (x1.0)
        end
    end

    // UART-related state: we keep track of the last applied parameter so the
    // detune-recompute pipeline can observe writes (uapplied pulses) and the
    // TX echo can confirm the applied value.
    reg [7:0] uparam = 8'd0;
    reg       uapplied = 1'b0;      // pulses after each applied VALUE
    reg [7:0] last_applied = 8'd0;

    //====================================================================
    // LFO (also an oscillator): slow phasor advancing EVERY clock.
    //   Its sine output scales a "modulation offset" added to every
    //   carrier's per-clock tuning word => each carrier osc is frequency
    //   modulated by a sub-audio LFO osc (audio-rate FM = phase modulation).
    //     TLFO = round(lfo_hz * 2^32 / 12e6)
    //   LFO_SHIFT scales the sine sample down to a tuning-word-sized offset.
    //   Both are host-controllable via UART params (see P_LFO_* below).
    //====================================================================
    localparam [31:0] TLFO      = 32'd2147;   // ~6 Hz at depth 4
    localparam integer LFO_SHIFT = 4;          // max |offset| ~ +/-2048 TW units

    // Host-controllable LFO rate/depth (defaults match the #defines above).
    wire [7:0] lfo_rate = params[P_LFO_RATE];              // host_tlfo = rate * TLFO
    wire [3:0] lfo_shift = params[P_LFO_DEPTH][3:0];       // 0 deep .. 15 shallow
    wire [31:0]  host_tlfo = {24'd0, lfo_rate} * TLFO;
    reg [31:0] lfo_phase = 32'd0;
    always @(posedge CLK) lfo_phase <= lfo_phase + host_tlfo;

    // LFO is itself an oscillator: its own small 256-entry sine wavetable
    // (kept separate from the carrier table so each keeps a single read port
    //  and the carrier stays in BRAM).
    reg [15:0] lfo_lut [0:255];
    initial $readmemh("src/mem/lfo.mem", lfo_lut);
    wire [15:0] lfo_cos = lfo_lut[lfo_phase[31:24]];

    // Scale the LFO sine (offset-then-shift) to a tuning-word-sized FM offset.
    //   Narrow signed width: (lfo_cos-32768) is +-32768, shifted down.
    wire signed [16:0] lfo_off = (($signed(lfo_cos) - 17'sd32768) >>> lfo_shift);

    //====================================================================
    // DDS phase accumulators, each advances EVERY clock.
    //   phase[i][31:22] scans the 1024-entry wavetable at voice i's pitch
    //   Per clock: phase[g] <= phase[g] + (scaled[g] >>> 7) + lfo_off
    //   where scaled[g] = tune[g] * detune[g] is PRE-COMPUTED whenever a
    //   detune fader changes (rare), through a single time-multiplexed
    //   multiplier. detune value 128 => scaled = tune*128 => /128 => x1.0.
    //   Keeping the multiply off the audio path keeps LUT / timing cost low
    //   while the 8 accumulators stay cheap adds (DDS wrap mod 2^32).
    //====================================================================
    wire [31:0] tune [0:7];
    assign tune[0] = 32'd39371;   // A2   110.00 Hz
    assign tune[1] = 32'd49603;   // C#3  138.59 Hz
    assign tune[2] = 32'd58988;   // E3   164.81 Hz
    assign tune[3] = 32'd78741;   // A3   220.00 Hz
    assign tune[4] = 32'd88383;   // B3   246.94 Hz
    assign tune[5] = 32'd93641;   // C4   261.63 Hz
    assign tune[6] = 32'd117979;  // E4   329.63 Hz
    assign tune[7] = 32'd157482;  // A4   440.00 Hz

    // Shared detune->scaled recompute pipeline.
    reg [2:0]  rcomp = 3'd0;      // which voice we're recomputing
    reg        rbusy = 1'b0;      // recompute sweep in progress
    reg [31:0] scaled [0:7];      // tune[g] * detune[g]

    // A detune param was just applied (uapplied pulses once after a value write).
    wire detune_write =
        uapplied && (uparam >= P_DETUNE0) && (uparam <= P_DETUNE0 + 7);

    // One combinational 32x8 multiplier, swept across the 8 voices.
    wire [39:0] mul_r = tune[rcomp] * {8'd0, params[P_DETUNE0 + rcomp]};

    always @(posedge CLK) begin
        if (detune_write && !rbusy) begin
            rbusy  <= 1'b1;
            rcomp  <= 3'd0;           // restart the sweep at voice 0
        end
        if (rbusy) begin
            scaled[rcomp] <= mul_r;               // latch this voice's product
            if (rcomp == 3'd7)
                rbusy <= 1'b0;
            else
                rcomp <= rcomp + 3'd1;
        end
    end

    reg [31:0] phase [0:7];
    integer p;
    initial begin
        for (p = 0; p < 8; p = p + 1) begin
            phase[p] = 32'd0;
            scaled[p] = tune[p] << 7;   // detune 128 => x1.0
        end
    end

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : osc
            always @(posedge CLK)
                phase[g] <= phase[g] + (scaled[g] >>> 7) + lfo_off;
        end
    endgenerate

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
    reg signed [27:0] acc = 28'sd0;
    reg signed [15:0] sample = 16'sd0;

    // Per-oscillator output level (0..255, default 255 = full) from host param.
    wire [7:0] vlev = params[P_VOICE0 + slot_dd];

    // Scale the current voice by its level: (sine-32768) * level.
    //   signed 24-bit result: ±32767*255 ≈ ±8.36M
    wire signed [23:0] mixsample =
        ($signed({1'b0, wdata}) - 17'sd32768) * {8'd0, vlev};

    always @(posedge CLK) begin
        slot   <= slot + 3'd1;
        slot_d <= slot;
        slot_dd<= slot_d;             // matches wdata latency (2 clocks after addr)
        waddr  <= phase[slot][31:22];
        wdata  <= sine_table[waddr];  // BRAM synchronous read port

        if (slot_dd == NM1) begin
            // last voice: acc holds first N-1; add this voice, scale to 16-bit.
            //   default vlev=255 => mixsample ~ sine*255; sum 8 => /8 /255 => ~ sine
            acc    <= 28'sd0;
            sample <= (acc + mixsample) >>> 11;
        end else begin
            acc <= acc + mixsample;
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

    //====================================================================
    // UART command parser: replaced by midi_over_serial bridge below.
    //   Incoming bytes (uart_rx_valid / uart_rx_data) are fed to the bridge,
    //   which emits single-cycle writes (midi_write + midi_addr + midi_value).
    //====================================================================
    wire        uart_rx_valid;
    wire [7:0]  uart_rx_data;
    wire        uart_tx_go;
    wire [7:0]  uart_tx_data;
    wire        uart_tx_busy;

    uart #(
        .CLK_HZ (12_000_000),
        .BAUD   (115200)
    ) uart_inst (
        .clk       (CLK),
        .rx        (uart_rx),
        .rx_valid  (uart_rx_valid),
        .rx_data   (uart_rx_data),
        .tx_go     (uart_tx_go),
        .tx_data   (uart_tx_data),
        .tx_busy   (uart_tx_busy),
        .tx        (uart_tx)
    );

    // Instantiate the MIDI-over-serial bridge
    wire midi_write;
    wire [5:0] midi_addr;
    wire [7:0] midi_value;

    midi_over_serial midi_bridge (
        .clk      (CLK),
        .rx_valid (uart_rx_valid),
        .rx_data  (uart_rx_data),
        .write    (midi_write),
        .addr     (midi_addr),
        .value    (midi_value)
    );

    // Apply writes emitted by the bridge into the params[] register file.
    always @(posedge CLK) begin
        uapplied <= 1'b0;               // default: no new applied command
        if (midi_write) begin
            params[midi_addr] <= midi_value;
            uparam <= {2'd0, midi_addr};
            last_applied <= midi_value;
            uapplied <= 1'b1;               // echo this value
        end
    end

    // Echo the freshly-applied VALUE back to the host (confirmation of receipt).
    assign uart_tx_data = last_applied;
    assign uart_tx_go   = uapplied && !uart_tx_busy;

    // ------- Status LED (diagnostic, blinks with audio sign) -------
    assign LEDR_N = ~sample[15];

endmodule
