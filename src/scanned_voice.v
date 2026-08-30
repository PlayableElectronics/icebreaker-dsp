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

    localparam AW = 5;

    reg signed [15:0] ring [0:N-1];

    reg [23:0] scan_phase;

    reg strike_pending;
    reg [4:0] strike_center;

    integer i;

    initial begin

        for (i = 0; i < N; i = i + 1)
            ring[i] = 16'sd0;

        scan_phase = 24'd0;
        strike_pending = 1'b0;
        strike_center = 5'd0;
        sample = 16'sd0;

    end


    //----------------------------------------------------------------------
    // Remember strike
    //
    // A host-generated strike may be much shorter than the audio frame,
    // therefore make it sticky until the next audio_tick.
    //----------------------------------------------------------------------

    always @(posedge clk) begin

        if (strike) begin
            strike_pending <= 1'b1;
            strike_center <= strike_pos;
        end

    end


    //----------------------------------------------------------------------
    // Physics / excitation / scanner
    //
    // This deliberately runs once per audio frame for the first version.
    //----------------------------------------------------------------------

    integer j;

    reg [4:0] scan_index;

    reg signed [15:0] left_value;
    reg signed [15:0] right_value;

    reg signed [17:0] physics_value;

    always @(posedge clk) begin

        if (audio_tick) begin

            //----------------------------------------------------------------
            // Scanner
            //----------------------------------------------------------------

            scan_index = scan_phase[20:16];

            left_value = ring[scan_index];

            if (scan_index == N-1)
                right_value = ring[0];
            else
                right_value = ring[scan_index + 1'b1];


            //----------------------------------------------------------------
            // Simple linear interpolation
            //
            // First prototype uses the upper fractional bits.
            //----------------------------------------------------------------

            sample <= left_value;


            //----------------------------------------------------------------
            // Advance scanner
            //----------------------------------------------------------------

            scan_phase <= scan_phase + scan_inc;


            //----------------------------------------------------------------
            // Strike excitation
            //----------------------------------------------------------------

            if (strike_pending) begin

                for (j = 0; j < N; j = j + 1) begin

                    if (j == strike_center)
                        ring[j] <= $signed({1'b0, strike_amp, 7'd0});

                end

                strike_pending <= 1'b0;

            end

            else begin

                //----------------------------------------------------------------
                // Very simple neighbour coupling
                //
                // ring[j] =
                //
                //   current
                // + neighbour contribution
                // - damping
                //
                //----------------------------------------------------------------

                for (j = 0; j < N; j = j + 1) begin

                    if (j == 0) begin

                        physics_value =
                            $signed(ring[j])
                            + (($signed(ring[N-1])
                              + $signed(ring[1])
                              - ($signed(ring[j]) <<< 1))
                              >>> 4)
                            - ($signed(ring[j]) >>> 8);

                    end

                    else if (j == N-1) begin

                        physics_value =
                            $signed(ring[j])
                            + (($signed(ring[j-1])
                              + $signed(ring[0])
                              - ($signed(ring[j]) <<< 1))
                              >>> 4)
                            - ($signed(ring[j]) >>> 8);

                    end

                    else begin

                        physics_value =
                            $signed(ring[j])
                            + (($signed(ring[j-1])
                              + $signed(ring[j+1])
                              - ($signed(ring[j]) <<< 1))
                              >>> 4)
                            - ($signed(ring[j]) >>> 8);

                    end

                    ring[j] <= physics_value[15:0];

                end

            end

        end

    end

endmodule
