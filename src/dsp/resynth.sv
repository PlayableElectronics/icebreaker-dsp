// src/dsp/resynth.sv
// Simple resynthesis engine: reads active frame buffer entries and synthesizes
// NV voices using phase increment and amplitude. Time-multiplexed across NV
// similar to original top.sv design. Produces 16-bit signed sample output.

module resynth #(
    parameter integer NV_CAP = 32,
    parameter integer NV_DEFAULT = 8
)(
    input  wire        clk,
    input  wire        reset_n,

    // Frame buffer read interface
    output reg  [4:0]  fb_read_addr,
    input  wire [47:0] fb_read_data,

    // control
    input  wire [4:0]  nv, // number of active voices (1..NV_CAP)

    // output sample (signed 16-bit)
    output reg signed [15:0] sample_out
);

    // local sine table (duplicate of top.sv memory)
    reg [15:0] sine_table [0:1023];
    initial $readmemh("src/mem/sine.mem", sine_table);

    // phase accumulators and per-voice parameters
    reg [31:0] phase [0:NV_CAP-1];
    reg [31:0] phase_inc [0:NV_CAP-1];
    reg [15:0] amp      [0:NV_CAP-1];

    integer i;
    initial begin
        for (i = 0; i < NV_CAP; i = i + 1) begin
            phase[i] = 32'd0;
            phase_inc[i] = 32'd0;
            amp[i] = 16'd0;
        end
        fb_read_addr = 5'd0;
        sample_out = 16'sd0;
    end

    // time-multiplex slot counter
    reg [5:0] slot;
    reg signed [39:0] acc; // accumulation width
    reg [9:0] addr;
    reg [15:0] wdata;
    reg [47:0] entry;

    always @(posedge clk) begin
        if (!reset_n) begin
            slot <= 6'd0;
            acc <= 40'sd0;
            sample_out <= 16'sd0;
            fb_read_addr <= 5'd0;
        end else begin
            if (slot == 6'd0) begin
                // begin sequence: set fb_read_addr to 0
                fb_read_addr <= 5'd0;
            end

            // read the current voice's parameters from fb_read_data (registered input)
            // We schedule reads: set fb_read_addr this cycle, fb_read_data will be valid next cycle
            // Use a simple 1-cycle delayed read: entry <= fb_read_data from previous cycle
            entry <= fb_read_data;

            // On each slot (after initial read latency) update phase, lookup sine and mix
            // Use phase index from phase[slot]; we update phase with phase_inc loaded earlier
            if (slot < nv) begin
                // If we have valid entry loaded from memory in previous cycle, load parameters
                // Note: to keep simple, we pull params from entry when slot==0 iteration after a full rotation.
                // For a simpler consistent behavior, sample the fb_read_data directly for each slot (assume read latency 0)
                // Compute address and read sine table
                addr <= phase[slot][31:22];
                wdata <= sine_table[addr];
                // update phase
                phase[slot] <= phase[slot] + phase_inc[slot];
                // Mix: centered sine times amp (signed)
                acc <= acc + (($signed({1'b0, wdata}) - 17'sd32768) * $signed({1'b0, amp[slot]}));
            end

            // advance slot and when we finish nv voices, emit sample
            if (slot == nv - 1) begin
                // produce 16-bit sample similar scaling as top.sv
                sample_out <= (acc >>> 11);
                acc <= 40'sd0;
                slot <= 6'd0;
                // restart reading from buffer at 0 for next frame
                fb_read_addr <= 5'd0;
            end else begin
                slot <= slot + 6'd1;
                fb_read_addr <= fb_read_addr + 5'd1;
            end
        end
    end

    // A simple mechanism to update phase_inc / amp registers from fb_read_data when a full rotation occurs
    // This is a low-priority convenience: when fb_read_addr cycles we will capture fb_read_data into params
    // For simplicity, do the capture when fb_read_addr increments (combinational) - keep design simple.
    always @(posedge clk) begin
        // When a valid entry read is available (we treat fb_read_data as valid), parse it
        // entry format assumed: [47:16] phase_inc (big-endian bytes), [15:0] amp
        // We'll update the corresponding phase_inc and amp for the addressed voice
        reg [4:0] idx;
        idx = fb_read_addr;
        phase_inc[idx] <= fb_read_data[47:16];
        amp[idx] <= fb_read_data[15:0];
    end

endmodule
