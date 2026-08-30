# iCEBreaker DSP

Open-source iCEBreaker FPGA DSP project: an **8-voice sine oscillator bank**
streamed over **I2S to a PCM5102A DAC**.

## Target

- FPGA: Lattice iCE40UP5K (SG48)
- Toolchain: Yosys + nextpnr-ice40 + IceStorm

## Functionality

- 8 DDS sine oscillators (A2, C#3, E3, A3, B3, C4, E4, A4) mixed to mono
- 16-bit signed samples, 1 kHz-resolution phase accumulators, sine LUT in BRAM
- I2S transmitter: Fs = 46.875 kHz, BCK ~3 MHz, 16-bit per channel (mono on both)
- Sample rate derived directly from the 12 MHz board clock

Edit the `TW0..TW7` tuning words in `src/top.sv` to change frequencies
(`tuning = round(freq * 2^32 / 46875)`).

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
