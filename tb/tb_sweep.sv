//////////////////////////////////////////////////////////////////////////////
// tb_sweep.sv - parameterized scanned-string sim (knq/kx/kv via -P)
//////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
module tb;
    parameter integer KNQ = 220;
    parameter integer KXQ = 178957;
    parameter integer KVQ = 2796;
    localparam N=256, W=16, QK=28, QCD=24;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, pluck=0;
    reg [7:0]  knq=KNQ, keq=8, qcd=0;
    reg [11:0] kv=KVQ;
    reg [17:0] kx=KXQ;
    reg [31:0] s_inc;
    wire signed [15:0] out;
    integer cnt=0, fd, fv, fx;
    // scan pitch high enough that the sim window covers many ring revolutions
    localparam real SF = 2.0**16;
    initial s_inc = $rtoi(8000.0*256.0*8.0/100.0e6 * SF);

    scanstring #(.N(N),.W(W),.QK(QK),.QCD(QCD)) dut(
        .clk(clk),.rst(rst),.pluck(pluck),
        .knq(knq),.keq(keq),.kv(kv),.kx(kx),.qcd(qcd),
        .s_inc(s_inc),.out(out));

    always @(posedge clk) begin
        if (cnt[4:0]==5'd0 && !rst) $fwrite(fd,"%d\n",$signed(out));
        if (cnt[8:0]==9'd0 && !rst) begin
            $fwrite(fv,"%d\n",$signed(dut.vram[0]));
            $fwrite(fx,"%d\n",$signed(dut.xram[0]));
        end
        cnt<=cnt+1;
    end
    initial begin
        fd=$fopen("/tmp/sw.txt","w");
        fv=$fopen("/tmp/sw_v.txt","w");
        fx=$fopen("/tmp/sw_x.txt","w");
        repeat(16)@(posedge clk); rst=0;
        repeat(3000)@(posedge clk);
        pluck=1; repeat(4)@(posedge clk); pluck=0;
        repeat(200000)@(posedge clk);
        $fclose(fd); $finish;
    end
endmodule
