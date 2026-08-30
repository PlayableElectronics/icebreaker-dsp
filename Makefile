TOP = top
BUILD = build

all: $(BUILD)/$(TOP).bin

$(BUILD):
	mkdir -p $(BUILD)

SRCS = src/top.sv src/scanned_voice.sv src/uart.sv

$(BUILD)/$(TOP).json: $(SRCS) | $(BUILD)
	yosys -p "read_verilog -sv $(SRCS); synth_ice40 -top $(TOP) -json $@"

$(BUILD)/$(TOP).asc: $(BUILD)/$(TOP).json icebreaker.pcf
	nextpnr-ice40 \
		--up5k \
		--package sg48 \
		--json $< \
		--pcf icebreaker.pcf \
		--asc $@

$(BUILD)/$(TOP).bin: $(BUILD)/$(TOP).asc
	icepack $< $@

clean:
	rm -rf $(BUILD)

.PHONY: all clean
