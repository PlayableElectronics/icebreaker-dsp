module top (
    input wire CLK,
    output wire bclk,
    output wire lrck,
    output wire dout,
    output wire xmute,
    output wire LEDR_N,
    input wire uart_rx,
    output wire uart_tx
);

    localparam [7:0] P_SYNC = 8'hEE;

    localparam [7:0] P_STRIKE       = 8'h40;
    localparam [7:0] P_STRIKE_AMP   = 8'h41;
    localparam [7:0] P_STRIKE_WIDTH = 8'h42;
    localparam [7:0] P_STRIKE_POS   = 8'h43;

    localparam [7:0] P_SCAN_HI      = 8'h44;
    localparam [7:0] P_SCAN_MID     = 8'h45;
    localparam [7:0] P_SCAN_LO      = 8'h46;

    localparam [7:0] P_KN           = 8'h47;
    localparam [7:0] P_KE           = 8'h48;
    localparam [7:0] P_DAMP         = 8'h49;

    assign xmute = 1'b1;

    reg [7:0] params [0:127];

    integer i;

    initial begin
        for (i = 0; i < 128; i = i + 1)
            params[i] = 8'd0;

        params[P_STRIKE_AMP]   = 8'd180;
        params[P_STRIKE_WIDTH] = 8'd3;
        params[P_STRIKE_POS]   = 8'd8;

        params[P_SCAN_HI]  = 8'h00;
        params[P_SCAN_MID] = 8'h09;
        params[P_SCAN_LO]  = 8'h9C;

        params[P_KN]   = 8'd120;
        params[P_KE]   = 8'd4;
        params[P_DAMP] = 8'd2;
    end


    wire uart_rx_valid;
    wire [7:0] uart_rx_data;

    wire uart_tx_busy;

    reg uart_tx_go;
    reg [7:0] uart_tx_data;


    uart #(
        .CLK_HZ(12000000),
        .BAUD(115200)
    ) uart_inst (
        .clk(CLK),
        .rx(uart_rx),
        .rx_valid(uart_rx_valid),
        .rx_data(uart_rx_data),
        .tx_go(uart_tx_go),
        .tx_data(uart_tx_data),
        .tx_busy(uart_tx_busy),
        .tx(uart_tx)
    );


    reg [1:0] cmd_state;
    reg [7:0] cmd_param;
    reg param_written;


    initial begin
        cmd_state = 2'd0;
        cmd_param = 8'd0;
        param_written = 1'b0;
        uart_tx_go = 1'b0;
        uart_tx_data = 8'd0;
    end


    always @(posedge CLK) begin

        param_written <= 1'b0;
        uart_tx_go <= 1'b0;

        if (uart_rx_valid) begin

            if (uart_rx_data == P_SYNC) begin

                cmd_state <= 2'd1;

            end
            else begin

                case (cmd_state)

                    2'd0: begin
                        cmd_state <= 2'd0;
                    end

                    2'd1: begin
                        cmd_param <= uart_rx_data;
                        cmd_state <= 2'd2;
                    end

                    2'd2: begin

                        params[cmd_param[6:0]] <= uart_rx_data;

                        param_written <= 1'b1;
                        cmd_state <= 2'd0;

                        if (!uart_tx_busy) begin
                            uart_tx_data <= uart_rx_data;
                            uart_tx_go <= 1'b1;
                        end

                    end

                    default: begin
                        cmd_state <= 2'd0;
                    end

                endcase

            end

        end

    end


    reg strike;

    initial begin
        strike = 1'b0;
    end

    always @(posedge CLK) begin
        strike <= param_written &&
                  (cmd_param == P_STRIKE);
    end


    reg [5:0] i2s_count;

    initial begin
        i2s_count = 6'd0;
    end

    always @(posedge CLK) begin
        i2s_count <= i2s_count + 6'd1;
    end


    assign bclk = i2s_count[0];
    assign lrck = i2s_count[5];


    wire audio_tick;

    assign audio_tick = (i2s_count == 6'd0);


    wire [23:0] scan_inc;

    assign scan_inc = {
        params[P_SCAN_HI],
        params[P_SCAN_MID],
        params[P_SCAN_LO]
    };


    wire signed [15:0] voice_sample;


    scanned_voice #(
        .N(32)
    ) voice_inst (
        .clk(CLK),
        .audio_tick(audio_tick),

        .strike(strike),
        .strike_amp(params[P_STRIKE_AMP]),
        .strike_width(params[P_STRIKE_WIDTH]),
        .strike_pos(params[P_STRIKE_POS][4:0]),

        .scan_inc(scan_inc),

        .kn(params[P_KN]),
        .ke(params[P_KE]),
        .damping(params[P_DAMP]),

        .sample(voice_sample)
    );


    reg signed [15:0] sample_latched;

    initial begin
        sample_latched = 16'sd0;
    end

    always @(posedge CLK) begin
        if (audio_tick)
            sample_latched <= voice_sample;
    end


    reg dout_r;

    always @(*) begin

        dout_r = 1'b0;

        if (i2s_count < 6'd32) begin

            if ((i2s_count >= 6'd1) &&
                (i2s_count <= 6'd16)) begin

                dout_r = sample_latched[16 - i2s_count];

            end

        end
        else begin

            if ((i2s_count >= 6'd33) &&
                (i2s_count <= 6'd48)) begin

                dout_r = sample_latched[48 - i2s_count];

            end

        end

    end


    assign dout = dout_r;

    assign LEDR_N = ~sample_latched[15];

endmodule
