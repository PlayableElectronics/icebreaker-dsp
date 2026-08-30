import("stdfaust.lib");

declare name "Waveguide Voice";
declare description "Single tunable feedback waveguide with body modes";

// Per-strike controls. The gate is intentionally separate from the body so
// the same voice can later be instantiated nine times.
freq = hslider("pitch[unit:Hz]", 220, 50, 1000, 0.01);
level = hslider("strike/amplitude", 0.35, 0, 1, 0.001);
pressure = hslider("strike/pressure", 0.08, 0.01, 0.5, 0.001);
attack = hslider("strike/attack[unit:s]", 0.006, 0.001, 0.1, 0.001);
decay = hslider("strike/decay[unit:s]", 2.5, 0.1, 8, 0.01);
damping = hslider("body/damping", 0.12, 0, 0.9, 0.001);
body = hslider("body/mode-level", 0.35, 0, 1, 0.001);
gate = button("strike");

// Smooth pressure envelope: no full-scale random-noise impulse.
pressure_env = en.adsr(attack, 0.08, 0.7, decay, gate) * pressure;
exciter = pressure_env * (1 + 0.18 * os.osc(freq * 2.01));

// Feedback waveguide. Damping is applied inside the loop, where it controls
// resonance decay rather than merely fading the output.
loop_gain = 0.999 - damping * 0.35;
waveguide = exciter : fi.fbcombfilter(4096, int(ma.SR / freq), loop_gain);

// Two related body modes add inharmonic color around the fundamental.
mode1 = waveguide : fi.resonbp(freq, 8, 1);
mode2 = waveguide : fi.resonbp(freq * 2.01, 10, body);
body_mix = 0.75 * waveguide + mode1 + mode2;

// Keep a mono reference here; stereo body/reverb is added after the voice is
// stable and can then be shared by the nine-voice mixer.
process = level * body_mix <: _,_;
