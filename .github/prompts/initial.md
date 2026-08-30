Please analyse this repository before making any changes.

I want to extend this existing IceBreaker DSP FPGA project into a real-time sine/modal resynthesizer controlled externally from a web application over USB MIDI.

Please investigate:

1. The top-level FPGA architecture.
2. The current audio input/output pipeline.
3. Sample rate and clock domains.
4. Existing DSP blocks and oscillator implementations.
5. Existing USB functionality and whether USB MIDI already exists or can be added.
6. The build pipeline and synthesis tools.
7. How new SystemVerilog modules should be integrated into the existing project.

Do not modify any files yet.

Create a detailed implementation plan identifying the exact files that should be modified or added.

The first target is:

External parameter input
→ parameter registers
→ 8 DDS sine oscillators
→ mixer
→ existing audio output.

Later this will expand to 32 oscillators, Web MIDI control, double-buffered spectral frames, and a Freeze feature.
