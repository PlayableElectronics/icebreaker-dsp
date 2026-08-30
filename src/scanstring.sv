//////////////////////////////////////////////////////////////////////////////
// scanstring.sv - 1-D ring scanned string (scanned synthesis)
//
//  A ring of N masses coupled by springs (Verplank / scanned synthesis).
//  Physics (explicit/Jacobi) evolves in the background; an audio-rate scanner
//  reads displacement along the ring with linear interpolation to produce a
//  pitched output whose pitch is independent of the string's internal waves.
//
//  Physics, per node i using positions from the START of the current sweep:
//    TaskA  dv[i] = ( (k_n*(x[i-1]-2x[i]+x[i+1]) - k_e*x[i]) * KV ) >> QK
//    TaskB  v'[i] = v[i] + dv[i] - ((v[i]*CD) >> QCD)
//           x'[i] = x[i] + ((v'[i]*KX) >> QK)      (mirrored to xscan)
//
//  Storage: xram (positions), vram (velocities), aram (dv scratch), xscan
//  (scanner mirror). The scanner reads only xscan, so there is no read/write
//  contention with the physics.
//////////////////////////////////////////////////////////////////////////////
module scanstring #(
    parameter integer N      = 256,
    parameter integer W      = 16,   // BRAM word width
    parameter integer QK     = 28,   // KV/KX folded-coefficient scale
    parameter integer QCD    = 24    // damping scale
)(
    input  wire clk,
    input  wire rst,
    input  wire pluck,                 // impulse excitation (edge-armed)
    input  wire [7:0]  knq,            // neighbour stiffness
    input  wire [7:0]  keq,            // earth stiffness
    input  wire [11:0] kv,             // v coeff  KVC = dt*2^(QK-3)  (Q14->Q11)
    input  wire [17:0] kx,             // x coeff  KXC = dt*2^(QK+3)  (Q11->Q14)
    input  wire [15:0] qcd,            // damping folded        QCD
    input  wire [31:0] s_inc,          // scanner phase increment (nodes/sample)
    output reg  signed [15:0] out
);
    localparam integer AW = $clog2(N);      // 8 for N=256
    localparam integer AP = 16;             // scanner phase fraction bits
    localparam signed [15:0] PLUCK_X = 16'h6000; // plucked displacement (~0.375)

    //========================================================================
    // BRAMs, each inferred single-port (sync write, sync read)
    //========================================================================
    reg [W-1:0] xram [0:N-1];
    reg [W-1:0] vram [0:N-1];
    reg [W-1:0] aram [0:N-1];
    reg [W-1:0] xscan[0:N-1];
    integer ix;
    initial begin
        for (ix = 0; ix < N; ix = ix + 1) begin
            xram[ix] = 0; vram[ix] = 0; aram[ix] = 0; xscan[ix] = 0;
        end
    end

    reg          xa_we, va_we, aa_we, xs_we;
    reg [AW-1:0] xa_a,  va_a,  aa_a,  xs_a;
    reg [W-1:0]  xa_wd, va_wd, aa_wd, xs_wd;
    wire [W-1:0] xa_rd = xram[xa_a];
    wire [W-1:0] va_rd = vram[va_a];
    wire [W-1:0] aa_rd = aram[aa_a];

    reg  [AW-1:0] sc_a;                      // scanner read port on xscan
    wire [W-1:0]  sc_rd = xscan[sc_a];

    always @(posedge clk) begin
        if (xa_we) xram [xa_a] <= xa_wd;
        if (va_we) vram [va_a] <= va_wd;
        if (aa_we) aram [aa_a] <= aa_wd;
        if (xs_we) xscan[xs_a] <= xs_wd;
    end

    //========================================================================
    // Master 8-clock period: mt==0,1,2 scanner; mt==3..7 physics.
    //========================================================================
    reg [2:0] mt = 3'd0;
    always @(posedge clk) mt <= mt + 3'd1;
    wire phys_slot = (mt >= 3'd3);

    //========================================================================
    // Scanner: linear-interpolated read of xscan at audio rate.
    //   mt0: addr<=i0, frac<=fr, phase+=inc
    //   mt1: scv0<=xscan[i0]; addr<=i0+1
    //   mt2: scv1<=xscan[i0+1]
    //   mt3: out<=scv0+((scv1-scv0)*fr)>>AP
    //========================================================================
    reg [31:0] sc_phase = 32'd0;
    reg [AW-1:0] sc_i0;
    reg [AP-1:0] sc_frac;
    reg signed [W-1:0] scv0, scv1;
    reg signed [W+AP:0] interp;

    always @(posedge clk) begin
        if (mt == 3'd0) begin
            sc_i0   <= sc_phase[AW+AP-1 : AP];
            sc_frac <= sc_phase[AP-1 : 0];
            sc_a    <= sc_phase[AW+AP-1 : AP];
            sc_phase<= sc_phase + s_inc;
        end else if (mt == 3'd1) begin
            scv0 <= $signed(sc_rd);
            sc_a <= sc_i0 + 1'b1;                 // (i0+1 mod N via width)
        end else if (mt == 3'd2) begin
            scv1 <= $signed(sc_rd);
        end else if (mt == 3'd3) begin
            interp <= $signed(scv0)
                    + (($signed(scv1) - $signed(scv0)) * $signed({1'b0,sc_frac}) >>> AP);
            out    <= interp[W-1:0];
        end
    end

    //========================================================================
    // Physics: Task A (compute dv) then Task B (apply). One node per 4 clocks.
    //========================================================================
    localparam S_IDLE=0, S_A0=1, S_A1=2, S_A2=3, S_A3=4,
               S_B0=5, S_B1=6, S_B2=7, S_B3=8;
    reg [3:0] st = S_IDLE;
    reg [AW-1:0] ci = 0;
    reg signed [W-1:0] ma[0:2];          // x[i-1],x[i],x[i+1]
    reg signed [W-1:0] lx, ldv, lv;      // Task B latches
    reg plk_d, plk_arm, plk_sweep;

    always @(posedge clk) begin
        plk_d   <= pluck;
        if (pluck && !plk_d) plk_arm <= 1'b1;   // sticky pluck request
        if (rst) begin plk_arm <= 1'b0; plk_sweep <= 1'b0; end
    end

    // Task-A combinational dv (from latched neighbours)
    wire signed [W+1:0] diff =
        $signed(ma[0]) - ($signed(ma[1]) << 1) + $signed(ma[2]);
    wire signed [34:0] spr =
        ($signed({8'b0,knq}) * diff) - ($signed({8'b0,keq}) * $signed(ma[1]));
    wire signed [63:0] dvw = ($signed(spr) * $signed({4'b0,kv})) >>> QK;
    wire signed [W-1:0] dv  = dvw[W-1:0];

    // Task-B combinational new velocity / position
    wire signed [W+1:0] damp = ($signed(lv) * $signed({16'b0,qcd})) >>> QCD;
    wire signed [W+1:0] vnew = $signed(lv) + $signed(ldv) - damp;

    // pluck segment forcing: displace the whole ring into a half/half square
    // pattern (strong fundamental + harmonics), released from rest so the
    // string evolves from this distributed shape -> scanner reads a tone.
    wire in_plk = plk_sweep;
    wire signed [W-1:0] plk_shape = (ci < (N>>1)) ? PLUCK_X : -PLUCK_X;
    wire signed [W-1:0] vwrite = in_plk ? 16'sd0 : vnew[W-1:0];
    wire signed [63:0]  xn2    = ($signed(vwrite) * $signed({6'b0,kx})) >>> QK;
    wire signed [W-1:0] xnew   = in_plk ? plk_shape : ($signed(lx) + xn2[W-1:0]);

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; ci <= 0;
            xa_we <= 0; va_we <= 0; aa_we <= 0; xs_we <= 0;
        end else if (phys_slot) begin
            xa_we <= 1'b0; va_we <= 1'b0; aa_we <= 1'b0; xs_we <= 1'b0;
            case (st)
            //========================== Task A ==========================
            S_IDLE: begin
                ci  <= 0;
                xa_a<= N-1;                       // x[-1] = x[N-1]
                if (plk_arm) plk_sweep <= 1'b1;   // arm the pluck sweep
                st  <= S_A0;
            end
            S_A0: begin
                ma[0] <= $signed(xa_rd);          // x[i-1]
                xa_a  <= ci;                      // x[i]
                st    <= S_A1;
            end
            S_A1: begin
                ma[1] <= $signed(xa_rd);          // x[i]
                xa_a  <= (ci==N-1)? 8'd0 : (ci+1'b1);  // x[i+1]
                st    <= S_A2;
            end
            S_A2: begin
                ma[2] <= $signed(xa_rd);          // x[i+1]
                st    <= S_A3;
            end
            S_A3: begin
                aa_we <= 1'b1;
                aa_a  <= ci;
                aa_wd <= $unsigned(dv);
                if (ci == N-1) begin
                    ci <= 0; st <= S_B0;
                end else begin
                    ci <= ci + 1'b1;
                    st <= S_A0;
                    xa_a <= ci;                   // next node i-1 (== this ci)
                end
            end
            //========================== Task B ==========================
            S_B0: begin
                xa_a <= ci; aa_a <= ci; va_a <= ci;   // read x,dv,v for node ci
                st   <= S_B1;
            end
            S_B1: begin
                lx  <= $signed(xa_rd);
                ldv <= $signed(aa_rd);
                lv  <= $signed(va_rd);
                st  <= S_B2;
            end
            S_B2: begin
                va_we <= 1'b1; va_a <= ci; va_wd <= $unsigned(vwrite);
                xa_we <= 1'b1; xa_a <= ci; xa_wd <= $unsigned(xnew);
                xs_we <= 1'b1; xs_a <= ci; xs_wd <= $unsigned(xnew);
                // the whole-ring pluck lasts one Task-B pass
                if (plk_sweep && ci == N-1) begin
                    plk_arm   <= 1'b0;
                    plk_sweep <= 1'b0;
                end
                st    <= S_B3;
            end
            S_B3: begin
                if (ci == N-1) begin
                    st <= S_IDLE;
                end else begin
                    ci <= ci + 1'b1;
                    st <= S_B0;
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
