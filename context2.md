# Project Context: Web-Controlled FPGA Sine Resynthesizer

## Goal

Build a real-time spectral/sine resynthesis instrument consisting of:

- a web application performing audio analysis;
- USB MIDI communication;
- an FPGA performing deterministic additive/modal synthesis;
- a Freeze function that captures and sustains the current spectral state.

The project should initially support approximately 16–32 sine oscillators, with an architecture that can later scale or time-multiplex oscillators.

---

# High-Level Architecture

```text
Audio Input / WAV / Microphone
             │
             ▼
      Browser Web Application
             │
             ▼
      WebAudio API Analysis
             │
             ├── FFT / STFT
             ├── Peak Detection
             ├── Frequency Tracking
             └── Amplitude Extraction
             │
             ▼
       Smoothed Modal Frame
             │
             ▼
            Web MIDI
             │
             ▼
           USB MIDI
══════════════════════════════════════
             FPGA
══════════════════════════════════════
             │
             ▼
          MIDI Parser
             │
             ▼
      Parameter Write Buffer
             │
             ▼
       Frame Complete Signal
             │
             ▼
      Double Buffer / Atomic Swap
             │
             ▼
        Active Parameters
             │
       ┌─────┼─────┐
       ▼     ▼     ▼
      OSC0  OSC1  OSC31
       │     │     │
       └─────┼─────┘
             ▼
         Adder Tree
             │
             ▼
        Limiter / DAC
             │
             ▼
           Audio
```

---

# Browser Responsibilities

The browser performs computationally expensive analysis.

Input sources:

- microphone;
- WAV/audio file;
- potentially Faust-generated audio.

Analysis:

1. Perform FFT/STFT.
2. Detect spectral peaks.
3. Track peaks between frames.
4. Extract:

```text
frequency
amplitude
optional phase
```

5. Smooth parameter changes.
6. Send parameters to FPGA using Web MIDI.

The browser should update analysis approximately 20–100 times per second.

The FPGA does not need to perform FFT analysis.

---

# FPGA Responsibilities

The FPGA implements a real-time additive synthesizer.

Each oscillator has:

```text
frequency
amplitude
phase accumulator
```

Basic synthesis equation:

```text
output =
SUM(
    amplitude[k] *
    sin(phase[k])
)
```

Phase update:

```text
phase[k] = phase[k] + phase_increment[k]
```

Frequency may be converted into a DDS phase increment:

```text
phase_increment =
frequency * 2^PHASE_BITS / SAMPLE_RATE
```

Recommended initial configuration:

```text
Sample rate:       48 kHz
Oscillators:       16 or 32
Phase accumulator: 32 bits
Audio samples:     24 bits
Internal DSP:      32–40 bits
```

---

# MIDI Parameter Protocol

Avoid relying only on standard MIDI CC mappings for all parameters.

Define a simple custom protocol using MIDI messages or SysEx.

A spectral frame contains:

```text
FRAME_START

MODE 0:
frequency
amplitude

MODE 1:
frequency
amplitude

...

MODE N:
frequency
amplitude

FRAME_END
```

The FPGA writes incoming values into a write buffer.

Only after `FRAME_END`:

```text
write_buffer → active_buffer
```

This prevents partially updated spectra.

---

# Double Buffering

Maintain:

```text
buffer_A
buffer_B
```

One buffer is active:

```text
ACTIVE BUFFER → oscillator bank
```

The other receives MIDI updates:

```text
MIDI → WRITE BUFFER
```

When a complete frame arrives:

```text
swap(active_buffer, write_buffer)
```

This allows atomic spectral updates.

---

# Freeze Feature

The FPGA implements Freeze locally.

Normal operation:

```text
LIVE MODE

Browser → MIDI → Write Buffer → Active Buffer → Oscillators
```

When FREEZE is pressed:

```text
FREEZE MODE

Stop accepting/swapping new parameter frames.

Keep current active parameters.

Oscillators continue running.
```

Important:

Freeze does NOT stop phase accumulators.

Only parameter updates are frozen.

Therefore:

```text
frequency = frozen
amplitude = frozen
phase accumulator = continues running
```

This creates a sustained spectral snapshot.

---

# Freeze Modes

Implement at least:

## LIVE

Continuously accept and swap parameter frames.

## FREEZE

Keep the current active spectral frame indefinitely.

Ignore new frames or continue receiving them into the inactive buffer without swapping.

## CAPTURE

Explicitly capture the next complete spectral frame and make it active.

Possible future modes:

```text
MORPH
DECAY
HOLD
RESONATE
```

---

# Bell / Modal Synthesis Extension

The same FPGA architecture should later support physical modal synthesis.

A bell can be represented as:

```text
x(t) =
SUM(
    A[k] *
    exp(-t/tau[k]) *
    sin(2*pi*f[k]*t + phase[k])
)
```

Each mode has:

```text
frequency
amplitude
decay
phase
```

The modal parameters can be extracted offline from a Faust physical bell model.

Pipeline:

```text
Faust Bell
    │
    ▼
Impulse Response WAV
    │
    ▼
Python Analysis
    │
    ├── FFT peak detection
    ├── I/Q demodulation
    └── decay estimation
    │
    ▼
bell_modes.json
    │
    ▼
FPGA coefficient generator
```

Eventually the live browser analyser and the Faust bell analyser should share a common parameter format.

---

# Recommended Project Structure

```text
fpga-resynth/
│
├── README.md
│
├── web/
│   ├── index.html
│   ├── app.js
│   ├── audio.js
│   ├── analyser.js
│   ├── peak_tracker.js
│   ├── midi.js
│   └── styles.css
│
├── python/
│   ├── extract_bell_modes.py
│   ├── analyze_wav.py
│   └── generate_fpga_coeffs.py
│
├── rtl/
│   ├── top.sv
│   ├── midi_parser.sv
│   ├── parameter_buffer.sv
│   ├── oscillator.sv
│   ├── sine_lut.sv
│   ├── oscillator_bank.sv
│   ├── adder_tree.sv
│   ├── freeze_controller.sv
│   └── audio_output.sv
│
├── sim/
│   ├── tb_oscillator.sv
│   ├── tb_midi_parser.sv
│   └── tb_full_system.sv
│
├── tools/
│   ├── generate_sine_lut.py
│   └── generate_coefficients.py
│
└── docs/
    ├── architecture.md
    ├── midi_protocol.md
    └── modal_synthesis.md
```

---

# Development Plan

## Phase 1: FPGA Oscillator

Implement and simulate one DDS oscillator.

Input:

```text
frequency register
amplitude register
```

Output:

```text
audio sample
```

Verify using a SystemVerilog testbench.

---

## Phase 2: Oscillator Bank

Implement 8 oscillators.

Then increase to 16/32.

Add:

```text
adder tree
scaling
clipping protection
```

---

## Phase 3: Parameter Interface

Initially avoid USB MIDI complexity.

Use simulation registers or UART to update:

```text
frequency
amplitude
```

Verify live parameter changes.

---

## Phase 4: Double Buffer

Implement:

```text
write_buffer
active_buffer
swap mechanism
```

Ensure parameter updates are atomic.

---

## Phase 5: Freeze

Implement:

```text
LIVE
FREEZE
CAPTURE
```

Freeze should hold the active parameters while oscillators continue running.

---

## Phase 6: USB MIDI

Connect browser Web MIDI to the FPGA USB MIDI device.

Implement the custom spectral frame protocol.

---

## Phase 7: Browser Analyzer

Create a webpage with:

```text
Microphone Input
Audio File Input
Spectrum Display
Peak Display
Oscillator Count
MIDI Device Selection
LIVE button
FREEZE button
CAPTURE button
```

Use WebAudio API.

---

## Phase 8: Bell Model

Analyse the Faust English bell.

Extract approximately:

```text
16 modes
32 modes
64 modes
```

Compare FPGA synthesis against the Faust reference.

---

# Important Design Principle

The FPGA is a hardware synthesis engine.

The browser is an analysis and control engine.

Therefore:

```text
COMPLEX ANALYSIS → Browser/PC
REAL-TIME SYNTHESIS → FPGA
CONTROL DATA → USB MIDI
```

The architecture should allow the same FPGA synthesizer to be used for:

- live microphone sine resynthesis;
- WAV analysis;
- Faust physical models;
- bell/modal synthesis;
- spectral freeze effects;
- experimental additive synthesis.

The first milestone should be:

```text
Browser
   ↓ USB MIDI
FPGA parameter registers
   ↓
8 sine oscillators
   ↓
summed audio output
```

Only after this works reliably should the project expand to 32 oscillators, double buffering, Freeze, and modal bell synthesis.