//////////////////////////////////////////////////////////////////////////////
// tb_scanstring.sv - simulation of the scanned string
//////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
module tb;
    localparam N=256, W=16, QK=28, QCD=24;
    reg clk=0; always #5 clk=~clk;       // 100 MHz sim (fast)
    reg rst=1, pluck=0;
    reg [7:0]  knq=220, keq=8, qcd=0;
    reg [11:0] kv=2796;
    reg [17:0] kx=178957;
    reg [31:0] s_inc;
    wire signed [15:0] out;

    // physics runs ~ quantum; scanner s_inc for ~440Hz at the module's scan
    // cadence (module emits out once per 8 clocks; scanner advances by s_inc
    // that often). s_inc = nodes/tick; tick rate = clk/8. For out-freq F:
    //   F = (clk/8) * (s_inc/N)   => s_inc = F*N*8/clk
    // With clk=100MHz, F=440 => s_inc = 440*256*8/100e6 = 0.009011 * 2^AP
    localparam real SF = 2.0**16;
    initial s_inc = $rtoi(440.0*256.0*8.0/100.0e6 * SF);
    integer fd;

    scanstring #(.N(N),.W(W),.QK(QK),.QCD(QCD)) dut(
        .clk(clk),.rst(rst),.pluck(pluck),
        .knq(knq),.keq(keq),.kv(kv),.kx(kx),.qcd(qcd),
        .s_inc(s_inc),.out(out));

    integer cnt=0;
    always @(posedge clk) begin
        if (cnt[4:0] == 5'd0 && !rst) begin
            $fwrite(fd, "%d\n", $signed(out));
        end
        cnt <= cnt + 1;
    end

    initial begin
        fd = $fopen("/tmp/scan_out.txt","w");
        $dumpfile("/tmp/scan.vcd");
        $dumpvars(0,tb);
        repeat(16) @(posedge clk); rst=0;
        repeat(2000) @(posedge clk);   // let physics settle at rest
        pluck=1;
        repeat(4) @(posedge clk);
        pluck=0;
        repeat(200000) @(posedge clk);
        $fclose(fd);
        $finish;
    end
endmodule
