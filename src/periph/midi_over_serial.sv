// src/periph/midi_over_serial.sv
//
// Parse a byte stream (rx_valid/rx_data) and produce single-cycle parameter
// writes: write pulse + addr[5:0] + value[7:0].
//
// Supports:
//  - Legacy framed protocol: 0xEE PARAM VALUE
//  - MIDI Control Change (0xB0..0xBF) with running status
//
// Mapping (can be adjusted):
//  - CC 0x14..0x1B -> params 0x20..0x27  (P_VOICE0..7)
//  - CC 0x28..0x2F -> params 0x30..0x37  (P_DETUNE0..7)
//  - CC 0x10 -> params 0x10 (P_LFO_RATE)
//  - CC 0x11 -> params 0x11 (P_LFO_DEPTH)
//
module midi_over_serial (
    input  wire        clk,
    input  wire        rx_valid,
    input  wire [7:0]  rx_data,

    output reg         write,      // single-cycle write pulse
    output reg  [5:0]  addr,
    output reg  [7:0]  value
);

    // Legacy framed parser state
    reg [1:0] leg_state = 2'd0; // 0=idle,1=got_sync(expect param),2=got_param(expect value)
    reg [7:0] leg_param = 8'd0;

    // MIDI parser state (we only care about Control Change 0xBn)
    reg [7:0] last_status = 8'd0;
    reg [1:0] midi_state = 2'd0; // 0=idle/no useful status,1=got_status(expect data1),2=got_data1(expect data2)
    reg [7:0] midi_data1 = 8'd0;

    always @(posedge clk) begin
        // default outputs
        write <= 1'b0;
        addr  <= 6'd0;
        value <= 8'd0;

        if (rx_valid) begin
            // Legacy framed mode has priority
            if (leg_state != 2'd0) begin
                if (leg_state == 2'd1) begin
                    leg_param <= rx_data;
                    leg_state <= 2'd2;
                end else begin
                    // leg_state == 2: got value
                    write <= 1'b1;
                    addr  <= rx_data[5:0];   // param index uses low 6 bits
                    value <= rx_data;        // value is the received byte
                    // But correct ordering: for framed protocol we need param then value
                    // So here rx_data is the VALUE; use previously stored leg_param
                    addr  <= leg_param[5:0];
                    value <= rx_data;
                    leg_state <= 2'd0;
                end
            end else begin
                // If this byte is a legacy sync, start legacy frame
                if (rx_data == 8'hEE) begin
                    leg_state <= 2'd1;
                end else begin
                    // MIDI parsing: status or data
                    if (rx_data[7]) begin
                        // status byte
                        last_status <= rx_data;
                        if ((rx_data & 8'hF0) == 8'hB0) begin
                            // Control Change for channel n
                            midi_state <= 2'd1; // expect data1 (controller)
                        end else begin
                            // unsupported status -> ignore until next status
                            midi_state <= 2'd0;
                        end
                    end else begin
                        // data byte
                        if (midi_state == 2'd1) begin
                            midi_data1 <= rx_data;
                            midi_state <= 2'd2;
                        end else if (midi_state == 2'd2) begin
                            // pair complete: midi_data1 = controller, rx_data = value
                            // map controller to parameter addr
                            reg [7:0] mapped;
                            mapped = 8'hFF;

                            // CC 0x14..0x1B -> P_VOICE0..7 (0x20..0x27)
                            if ((midi_data1 >= 8'h14) && (midi_data1 <= 8'h1B)) begin
                                mapped = 8'h20 + (midi_data1 - 8'h14);
                            end
                            // CC 0x28..0x2F -> P_DETUNE0..7 (0x30..0x37)
                            else if ((midi_data1 >= 8'h28) && (midi_data1 <= 8'h2F)) begin
                                mapped = 8'h30 + (midi_data1 - 8'h28);
                            end
                            // LFO mappings
                            else if (midi_data1 == 8'h10) mapped = 8'h10; // P_LFO_RATE
                            else if (midi_data1 == 8'h11) mapped = 8'h11; // P_LFO_DEPTH

                            if (mapped != 8'hFF) begin
                                write <= 1'b1;
                                addr  <= mapped[5:0];
                                value <= rx_data;
                            end
                            // stay in midi_state=1 to allow running status pairs
                            midi_state <= 2'd1;
                        end
                        // else ignore stray data bytes
                    end
                end
            end
        end
    end

endmodule
