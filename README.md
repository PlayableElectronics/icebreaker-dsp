# iCEBreaker DSP

Open-source iCEBreaker FPGA DSP project: a **single sine oscillator**
streamed over **I2S to a PCM5102A DAC**.

## Target

- FPGA: Lattice iCE40UP5K (SG48)
- Toolchain: Yosys + nextpnr-ice40 + IceStorm

## Functionality

- One DDS sine oscillator (default A3 = 220 Hz), 16-bit signed samples
- Phase accumulator advances on every 12 MHz clock; combinational-ish BRAM
  wavetable read means the sample always tracks the current phase (no glitches)
- I2S serializer: 16-bit per channel, mono duplicated on both channels
- Sample/frame rate ≈ 187.5 kHz (12 MHz / 64), BCK ~6 MHz
- Architecture mirrors the proven `noscene/ice40_audio` PCM5102 driver

Change frequency by editing the `TW` tuning word in `src/top.sv`:
`tuning = round(freq * 2^32 / 12e6)` (e.g. 220 Hz → 78741).

## Wiring: PCM5102A DAC -> PMOD1A

| PMOD1A pin | FPGA pin | DAC signal |
|-----------|----------|------------|
| 1         | 4        | BCK  (bit clock)    |
| 2         | 2        | LRCK (word select)  |
| 3         | 47       | DIN  (serial data)  |
| 7         | 3        | XSMT (soft mute, high = un-muted) |
| 5 / 11    | GND      | GND                 |
| 6 / 12    | 3.3V     | 3V3 (DVDD/AVDD)     |

The PCM5102's on-chip PLL derives its system clock from BCK, so **SCK must be
left unconnected** (do not tie to ground). Drive **FMT low** (I2S format).
XSMT is driven high by the FPGA (active audio).

## Build

```bash
make
```

Bitstream: `build/top.bin` (program with `iceprog`, or via the iCEBreaker FTDI).
GitHub Actions CI builds and uploads the bitstream as an artifact on every push.
