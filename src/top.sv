module top (
    input  wire CLK,
    output wire LEDR_N
);

    reg [23:0] counter = 24'd0;

    always @(posedge CLK) begin
        counter <= counter + 1'b1;
    end

    assign LEDR_N = ~counter[23];

endmodule
