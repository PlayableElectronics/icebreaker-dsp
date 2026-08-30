TOP = top
BUILD = build

all: $(BUILD)/$(TOP).bin

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/$(TOP).json: src/$(TOP).sv | $(BUILD)
	yosys -p "read_verilog -sv src/$(TOP).sv; synth_ice40 -top $(TOP) -json $@"

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
