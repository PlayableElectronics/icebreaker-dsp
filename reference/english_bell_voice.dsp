import("stdfaust.lib");

declare name "English Bell Voice";
declare description "Single position-sensitive modal bell voice";

trigger = button("strike");
strikePosition = hslider("strike/position", 3, 0, 6, 1) : int;
strikeCutoff = hslider("strike/cutoff[unit:Hz]", 6500, 1000, 12000, 1);
strikeSharpness = hslider("strike/sharpness", 0.5, 0.05, 1, 0.001);
strikeGain = hslider("strike/gain", 1, 0, 1, 0.001);
decay = hslider("body/t60[unit:s]", 8, 0.1, 30, 0.01);
bodyGain = hslider("body/gain", 0.8, 0, 1, 0.001);

exciter = trigger : pm.strikeModel(10, strikeCutoff,
                                    strikeSharpness, strikeGain);
body = exciter : pm.englishBellModel(10, strikePosition, decay, 1, 3);

process = bodyGain * body <: _,_;
