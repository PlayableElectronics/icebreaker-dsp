// Small 2-operator FM voice. ROM reads are registered so the sine table maps
// to iCE40 block RAM rather than a large combinational LUT network.
module fm_voice (
    input wire clk,
    input wire audio_tick,
    input wire pluck,
    input wire [31:0] carrier_tw,
    input wire [15:0] strike_amp,
    input wire [7:0] strike_width,
    input wire [7:0] damping,
    output reg signed [15:0] sample
);
    reg [15:0] sine [0:1023];
    reg [9:0] mod_addr, carrier_addr;
    reg [15:0] mod_data, carrier_data;
    reg [31:0] carrier_phase, mod_phase;
    reg [15:0] env, mod_index;
    reg [2:0] state;
    reg pluck_d, pending;
    wire signed [16:0] mod_sine = $signed({1'b0, mod_data}) - 17'sd32768;
    wire signed [31:0] mod_product = mod_sine * $signed({1'b0, mod_index});
    wire signed [31:0] phase_offset = mod_product >>> 8;
    wire [31:0] audible_phase = carrier_phase + phase_offset;
    wire signed [16:0] carrier_sine = $signed({1'b0, carrier_data}) - 17'sd32768;
    integer i;

    initial begin
        carrier_phase = 0;
        mod_phase = 0;
        env = 0;
        mod_index = 0;
        mod_addr = 0;
        carrier_addr = 0;
        mod_data = 0;
        carrier_data = 0;
        state = 0;
        pluck_d = 0;
        pending = 0;
        sample = 0;
    end
    initial $readmemh("src/mem/sine.mem", sine);

    always @(posedge clk) begin
        pluck_d <= pluck;
        if (pluck && !pluck_d)
            pending <= 1'b1;

        if (audio_tick && state == 0) begin
            if (pending) begin
                pending <= 1'b0;
                carrier_phase <= 0;
                mod_phase <= 0;
                env <= strike_amp;
                mod_index <= 16'd4096 + {8'd0, strike_width} * 8'd128;
                sample <= 0;
            end
            mod_addr <= mod_phase[31:22];
            state <= 1;
        end else if (state == 1) begin
            mod_data <= sine[mod_addr];
            state <= 2;
        end else if (state == 2) begin
            carrier_addr <= audible_phase[31:22];
            state <= 3;
        end else if (state == 3) begin
            carrier_data <= sine[carrier_addr];
            state <= 4;
        end else if (state == 4) begin
            carrier_phase <= carrier_phase + carrier_tw;
            mod_phase <= mod_phase + (carrier_tw << 1);
            if (env > {8'd0, damping})
                env <= env - {8'd0, damping} - (env >> 12);
            else
                env <= 0;
            if (mod_index > 16'd32)
                mod_index <= mod_index - 1'b1;
            sample <= (carrier_sine * $signed({1'b0, env})) >>> 15;
            state <= 0;
        end
    end
endmodule
