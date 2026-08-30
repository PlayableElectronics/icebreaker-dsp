# iCEBreaker DSP

Open-source iCEBreaker FPGA DSP project: an **8-voice sine oscillator bank**
streamed over **I2S to a PCM5102A DAC**.

## Target

- FPGA: Lattice iCE40UP5K (SG48)
- Toolchain: Yosys + nextpnr-ice40 + IceStorm

## Functionality

- 8 DDS sine oscillators (A2, C#3, E3, A3, B3, C4, E4, A4) summed into a chord
- Each oscillator's phase accumulator advances on **every** 12 MHz clock;
  the single-port BRAM wavetable is time-multiplexed across voices and
  accumulated, so the output always tracks the current phases (no glitches)
- A **shared LFO** (itself an oscillator with its own phase accumulator and
  a small 256-entry sine wavetable) frequency-modulates all 8 voices:
  `phase[i] += TW[i] + lfo_off`. Audio-rate FM ≡ PM here, so this gives the
  whole chord a slow ~6 Hz vibrato / ensemble wobble.
- 16-bit signed samples, summed mix scaled by 1/8 to avoid clipping
- I2S serializer: 16-bit per channel, mono duplicated on both channels
- Sample/frame rate ≈ 187.5 kHz (12 MHz / 64), BCK ~6 MHz
- Architecture mirrors the proven `noscene/ice40_audio` PCM5102 driver

Change the chord by editing the `TW0..TW7` tuning words in `src/top.sv`:
`tuning = round(freq * 2^32 / 12e6)` (e.g. 220 Hz → 78741).

LFO parameters in `src/top.sv`:
- `TLFO` = round(lfo_hz * 2^32 / 12e6) (default ~6 Hz)
- `LFO_SHIFT` = right-shift applied to the LFO sine to get a tuning-word-sized
  FM offset (smaller shift = deeper modulation). Table: `src/mem/lfo.mem`.

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

## Fast test loop

```bash
openFPGALoader -v -b ice40_generic build/top.bin
```
