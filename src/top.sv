module top (
    input  wire clk,
    output wire led
);

    reg [23:0] counter = 24'd0;

    always @(posedge clk) begin
        counter <= counter + 1'b1;
    end

    // iCEBreaker RGB red LED is active-low
    assign led = ~counter[23];

endmodule
