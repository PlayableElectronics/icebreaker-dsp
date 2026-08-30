# iCEBreaker DSP - Project Context

## Project Goal

This project explores implementing a playable physical/scanned-synthesis instrument on an iCEBreaker FPGA.

The long-term target is a handpan-like digital instrument with approximately 9-10 independently triggered resonant voices. Each voice should have its own tuning and physical/strike parameters.

The intended characteristics are:

* individually playable notes
* handpan-like percussive attacks
* multiple simultaneous resonances
* independent tuning per voice
* different strike positions
* different strike strengths
* different strike widths/shapes
* controllable decay and damping
* evolving, complex spectra rather than simple sine oscillators

The synthesis direction is based on scanned synthesis.

---

# Hardware

## FPGA

Target board:

* iCEBreaker FPGA development board

Main FPGA clock:

* 12 MHz

## DAC

Target DAC:

* PCM5102A

Connection through PMOD1A.

Current assumed signals:

* `bclk`
* `lrck`
* `dout`
* `xmute`

Current pin assignments should remain compatible with the existing project constraints.

The DAC soft mute signal is:

```verilog
assign xmute = 1'b1;
```

meaning audio output should be enabled.

---

# Existing Project

Repository:

https://github.com/PlayableElectronics/icebreaker-dsp/

The project previously contained a bank of oscillators producing audio.

The current goal is to gradually replace those oscillators with a scanned synthesis engine.

The existing oscillator/DAC path should be treated as useful hardware reference, but new synthesis code should be developed independently and kept simple enough to verify incrementally.

---

# Current Source Files

Current architecture:

```text
src/
    top.sv
    uart.v
    scanned_voice.sv
```

Potential future architecture:

```text
src/
    top.sv
    uart.v

    audio/
        i2s_tx.sv

    synthesis/
        scanned_voice.sv
        scanned_membrane.sv
        strike.sv
        scanner.sv

    voices/
        voice_bank.sv
```

For now, keep the design simple and avoid unnecessary module fragmentation.

---

# UART Control Protocol

Communication with the host uses UART.

Current UART framing:

```text
[0xEE] [PARAM] [VALUE]
```

Where:

* `0xEE` is the synchronization byte
* `PARAM` selects a parameter
* `VALUE` is an 8-bit value

The UART is configured for:

```text
Clock: 12 MHz
Baud:  115200
```

The UART module interface is currently:

```verilog
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
```

The FPGA currently echoes received parameter values as a simple confirmation.

---

# Current Parameter Map

```text
0x40  STRIKE

0x41  STRIKE_AMP
0x42  STRIKE_WIDTH
0x43  STRIKE_POS

0x44  SCAN_HI
0x45  SCAN_MID
0x46  SCAN_LO

0x47  KN
0x48  KE
0x49  DAMP
```

Definitions:

## P_STRIKE

Writing any value generates a strike event.

```text
0x40
```

The value itself is currently ignored.

---

## P_STRIKE_AMP

Strike amplitude.

```text
0x41
```

Controls how strongly the physical model is excited.

---

## P_STRIKE_WIDTH

Strike width.

```text
0x42
```

Eventually this should control the spatial width of the excitation.

A narrow strike produces more high-frequency content.

A wide strike produces a smoother excitation.

---

## P_STRIKE_POS

Strike position.

```text
0x43
```

Controls where on the simulated physical structure the strike occurs.

---

## P_SCAN_HI / MID / LO

24-bit scanner increment.

```text
0x44
0x45
0x46
```

Combined as:

```verilog
wire [23:0] scan_inc;

assign scan_inc = {
    params[P_SCAN_HI],
    params[P_SCAN_MID],
    params[P_SCAN_LO]
};
```

The scanner phase moves independently from the physical simulation.

This is one of the fundamental concepts of scanned synthesis.

---

## P_KN

Neighbour coupling / spring strength.

```text
0x47
```

Controls coupling between neighbouring masses.

---

## P_KE

Earth/restoring stiffness.

```text
0x48
```

Controls restoring force toward the equilibrium position.

---

## P_DAMP

Damping.

```text
0x49
```

Controls energy loss and therefore decay time.

---

# Current top.sv Architecture

The top-level module currently contains:

```text
UART
 |
 v
Parameter storage
 |
 v
Strike generation
 |
 v
scanned_voice
 |
 v
sample_latched
 |
 v
I2S serializer
 |
 v
PCM5102A
```

The scanned voice interface is:

```verilog
module scanned_voice #(
    parameter N = 32
)(
    input wire clk,
    input wire audio_tick,

    input wire strike,
    input wire [7:0] strike_amp,
    input wire [7:0] strike_width,
    input wire [4:0] strike_pos,

    input wire [23:0] scan_inc,

    input wire [7:0] kn,
    input wire [7:0] ke,
    input wire [7:0] damping,

    output reg signed [15:0] sample
);
```

---

# Current Audio Timing

The FPGA master clock is:

```text
12 MHz
```

The current simple timing divider is:

```verilog
reg [5:0] i2s_count;

always @(posedge CLK)
    i2s_count <= i2s_count + 6'd1;
```

Current signals:

```verilog
assign bclk = i2s_count[0];
assign lrck = i2s_count[5];
```

Therefore:

```text
BCLK = 6 MHz
LRCK = 187.5 kHz
```

This is currently a development configuration.

It is not necessarily the desired final audio sample rate.

Future work may use an FPGA PLL to generate a more standard audio clock.

Possible future targets:

```text
48 kHz
96 kHz
```

The existing simple clocking should not be changed until the basic DAC path and synthesis engine are verified.

---

# Important I2S Note

The audio sample is latched once per frame:

```verilog
always @(posedge CLK) begin
    if (audio_tick)
        sample_latched <= voice_sample;
end
```

This avoids changing the sample while it is being serialized.

The current system duplicates mono audio to both channels.

Conceptually:

```text
LEFT  = sample
RIGHT = sample
```

The serializer should be tested independently if audio problems occur.

---

# Current scanned_voice Implementation

The current `scanned_voice.sv` is only a bootstrap implementation.

It is NOT yet the final scanned synthesis engine.

Its purpose is:

1. allow `top.sv` to compile
2. verify the FPGA -> PCM5102A audio path
3. verify UART strike events
4. verify scanner control
5. provide a starting point for physical modelling

The current implementation uses:

```text
32-node ring
```

with:

* displacement values
* local strike excitation
* simple neighbour coupling
* simple damping
* moving scanner

This should be considered experimental.

---

# Scanned Synthesis Concept

The intended synthesis method is based on scanned synthesis.

A physical model exists in memory:

```text
x[0]
x[1]
x[2]
...
x[N-1]
```

The physical model evolves over time.

Separately, a scanner moves through this structure.

Conceptually:

```text
Physical structure:

 x0 -- x1 -- x2 -- x3 -- ... -- xN
  ^                                |
  |________________________________|
               ring


Scanner:

        *
        |
        v

 x0 -- x1 -- x2 -- x3 -- ... -- xN
```

The scanner position is controlled by a phase accumulator.

For example:

```verilog
scan_phase <= scan_phase + scan_inc;
```

The scanner reads the physical structure independently of the physical update.

This separation is important.

The physical structure does not directly define the final audible pitch.

The scanner speed can strongly affect the resulting pitch.

---

# Future Proper Physics Model

The desired model should eventually include at least:

```text
x[i] = position
v[i] = velocity
```

For a one-dimensional structure:

```text
force[i] =
    kn * (
        x[i-1]
        - 2*x[i]
        + x[i+1]
    )
    - ke*x[i]
```

Then:

```text
v[i] = v[i] + force[i] - damping
x[i] = x[i] + v[i]
```

The final implementation will need fixed-point scaling.

Important requirements:

* stable numerical behaviour
* no uncontrolled overflow
* explicit fixed-point formats
* parameter ranges chosen for FPGA hardware

---

# Memory Considerations

The iCEBreaker FPGA has limited resources.

A first implementation should remain small.

Recommended progression:

```text
Stage 1
32 nodes
1 voice

Stage 2
64 nodes
1 voice

Stage 3
32 nodes
multiple voices

Stage 4
larger or more complex structures
```

Do not immediately attempt:

```text
10 voices
x 256 nodes
x multiple state variables
```

until resource usage and audio behaviour are known.

---

# Handpan Target

The final instrument does not need to be a literal physical simulation of a handpan.

A better approach is probably a hybrid model.

Each note can be represented as an independently triggered resonant structure.

For example:

```text
                 HANDPAN INSTRUMENT

                 [ DING ]

        [ N1 ]             [ N2 ]

    [ N3 ]                     [ N4 ]

        [ N5 ]             [ N6 ]

             [ N7 ] [ N8 ]
```

Each note may have:

```text
frequency
scanner speed
strike amplitude
strike position
strike width
damping
coupling
brightness
inharmonicity
```

The important aspect is playability rather than strict physical accuracy.

---

# Recommended Voice Architecture

A future voice could contain:

```text
Strike event
    |
    v
Spatial excitation
    |
    v
Physical state update
    |
    v
Scanned structure
    |
    v
Interpolation
    |
    v
Output gain
```

For multiple voices:

```text
Strike input
    |
    +---- Voice 1
    |
    +---- Voice 2
    |
    +---- Voice 3
    |
    ...
    |
    +---- Voice 10
            |
            v
          Mixer
            |
            v
         PCM5102A
```

---

# Strike Model

The strike should eventually support more than a single impulse.

Possible parameters:

```text
amplitude
position
width
hardness
velocity
noise
```

A useful strike shape could be:

```text
        *
       ***
      *****
     *******
```

rather than:

```text
*
```

A narrow excitation produces a brighter result.

A wider excitation produces a darker result.

Adding a small noise component may help produce a hand-like percussive attack.

---

# Per-Strike Voice Parameters

Every strike must have an independent parameter set, either carried with the
trigger event or selected from a per-note voice slot. These parameters must
affect the generated sound rather than being placeholder controls:

* pitch / waveguide delay
* strike amplitude and velocity
* strike position
* strike width and shape
* excitation hardness / pressure
* neighbour coupling
* restoring stiffness
* damping / decay
* modal balance and inharmonicity
* body/reverb send and stereo spread

The Csound `wgbow` reference demonstrates the importance of smooth pressure
variation, resonant feedback, multiple related modes, and body reverb. The FPGA
voice should preserve these roles while using smaller fixed-point structures.

---

# Handpan-Like Inharmonicity

A real handpan note is not a simple harmonic oscillator.

Useful future parameters include multiple resonant structures or modes.

For example:

```text
Fundamental      1.00
Mode             2.01
Mode             3.00
Mode             4.18
Mode             5.37
```

These values do not need to be exact harmonic multiples.

A practical FPGA implementation might eventually use:

```text
One scanned physical structure

plus

Several lightweight resonant filters
```

or:

```text
Several smaller scanned structures per note
```

The goal is to produce:

```text
attack
metallic complexity
long decay
slow spectral evolution
inharmonic partials
```

---

# Development Priorities

The correct order of development is:

## Step 1

Compile successfully.

Confirm:

```text
top.sv
uart.v
scanned_voice.sv
```

are all included in the synthesis command.

---

## Step 2

Verify PCM5102A output.

Use a known signal if necessary.

For example temporarily replace the scanned voice with:

```text
simple square wave
```

or:

```text
simple oscillator
```

This confirms:

```text
FPGA
 ->
I2S timing
 ->
PCM5102A
 ->
audio output
```

before debugging physical modelling.

---

## Step 3

Verify strike.

Send:

```text
EE 40 XX
```

and confirm that the voice responds.

---

## Step 4

Verify scanner increment.

Change:

```text
P_SCAN_HI
P_SCAN_MID
P_SCAN_LO
```

and confirm that the audible pitch changes.

---

## Step 5

Improve physical model.

Add:

```text
velocity memory
proper spring forces
stable integration
fixed-point scaling
```

---

## Step 6

Add interpolation.

Scanner output should eventually use:

```text
x0 + fraction * (x1 - x0)
```

rather than simply reading one node.

---

## Step 7

Add multiple voices.

Initially:

```text
2 voices
```

then:

```text
4 voices
```

then measure FPGA resources.

---

## Step 8

Build the handpan instrument.

Target:

```text
9-10 playable notes
```

Each voice independently triggered and tuned.

---

# Important Coding Rules

For compatibility with Yosys/iCE40 synthesis:

Prefer:

```verilog
wire [23:0] signal;

assign signal = {
    a,
    b,
    c
};
```

Avoid relying on declaration assignment such as:

```verilog
wire [23:0] signal = {
    a,
    b,
    c
};
```

unless verified with the exact synthesis toolchain.

Use simple synthesizable Verilog/SystemVerilog.

Avoid unnecessary advanced language features until the design is stable.

---

# Current Status

Current project status:

```text
[+] top-level UART architecture defined
[+] parameter storage defined
[+] strike event interface defined
[+] scanned_voice interface defined
[+] PCM5102A output architecture present

[ ] verify complete synthesis
[ ] verify DAC output
[ ] verify scanned_voice produces audio
[ ] implement proper velocity-based physics
[ ] implement scanner interpolation
[ ] optimize FPGA resource usage
[ ] add polyphonic voice bank
[ ] develop handpan-specific tuning and voicing
```

---

# Main Principle

Do not try to build the complete handpan immediately.

The immediate objective is:

```text
ONE STRIKE
    ->
ONE PHYSICAL STRUCTURE
    ->
ONE MOVING SCANNER
    ->
AUDIBLE SOUND
```

Once that works reliably:

```text
ONE GOOD VOICE
    ->
MULTIPLE VOICES
    ->
HANDPAN INSTRUMENT
```

The quality of one voice and the correctness of the FPGA audio pipeline are more important than adding many voices too early.
