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

    reg signed [15:0] ring [0:N-1];

    reg [23:0] scan_phase;
    reg strike_pending;

    integer i;

    initial begin
        for (i = 0; i < N; i = i + 1)
            ring[i] = 16'sd0;

        scan_phase = 24'd0;
        strike_pending = 1'b0;
        sample = 16'sd0;
    end


    // Remember a strike until the next audio update
    always @(posedge clk) begin
        if (strike)
            strike_pending <= 1'b1;
    end


    integer j;

    always @(posedge clk) begin

        if (audio_tick) begin

            // Scanner reads one position from the ring
            sample <= ring[scan_phase[20:16]];

            // Move scanner
            scan_phase <= scan_phase + scan_inc;


            // Apply strike
            if (strike_pending) begin

                for (j = 0; j < N; j = j + 1) begin

                    if (j == strike_pos)
                        ring[j] <= $signed({1'b0, strike_amp, 7'd0});

                end

                strike_pending <= 1'b0;

            end

            else begin

                // Simple ring diffusion / coupling.
                // This is only a bootstrap physical model.

                ring[0] <=
                    ring[0]
                    + ((ring[N-1] + ring[1] - (ring[0] <<< 1)) >>> 4)
                    - (ring[0] >>> 8);

                for (j = 1; j < N-1; j = j + 1) begin

                    ring[j] <=
                        ring[j]
                        + ((ring[j-1] + ring[j+1] - (ring[j] <<< 1)) >>> 4)
                        - (ring[j] >>> 8);

                end

                ring[N-1] <=
                    ring[N-1]
                    + ((ring[N-2] + ring[0] - (ring[N-1] <<< 1)) >>> 4)
                    - (ring[N-1] >>> 8);

            end

        end

    end

endmodule
