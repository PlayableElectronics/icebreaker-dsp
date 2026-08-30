`timescale 1ns/1ps
module tb;
    localparam N=256, W=16, QK=28, QCD=24;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, pluck=0;
    reg [7:0]  knq=220, keq=8, qcd=0;
    reg [11:0] kv=2796;
    reg [17:0] kx=178957;
    reg [31:0] s_inc;
    wire signed [15:0] out;
    localparam real SF = 2.0**16;
    initial s_inc = $rtoi(440.0*256.0*8.0/100.0e6 * SF);
    integer cnt=0;
    scanstring #(.N(N),.W(W),.QK(QK),.QCD(QCD)) dut(
        .clk(clk),.rst(rst),.pluck(pluck),
        .knq(knq),.keq(keq),.kv(kv),.kx(kx),.qcd(qcd),
        .s_inc(s_inc),.out(out));
    initial begin
        $dumpfile("/tmp/scan.vcd"); $dumpvars(0,tb);
        repeat(16) @(posedge clk); rst=0;
        repeat(2000) @(posedge clk);
        pluck=1; repeat(4) @(posedge clk); pluck=0;
        repeat(5000) @(posedge clk);
        $display("st=%0d ci=%0d x128=%0d v128=%0d xs128=%0d x129=%0d out=%0d",
            dut.st, dut.ci, $signed(dut.xram[128]),
            $signed(dut.vram[128]), $signed(dut.xscan[128]),
            $signed(dut.xram[129]), $signed(out));
        repeat(200000) @(posedge clk);
        $display("FINAL st=%0d ci=%0d x128=%0d v128=%0d xs128=%0d",
            dut.st,dut.ci,$signed(dut.xram[128]),$signed(dut.vram[128]),
            $signed(dut.xscan[128]));
        $finish;
    end
endmodule
