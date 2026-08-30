import("stdfaust.lib");

// Four-key reference voice adapted directly from the supplied SmartKeyboard
// model. Each key drives a shaped strike into a different modal bell body.
kb0k0status = hslider("kb0k0status", 0, 0, 1, 1) : min(1) : int;
kb0k1status = hslider("kb0k1status", 0, 0, 1, 1) : min(1) : int;
kb1k0status = hslider("kb1k0status", 0, 0, 1, 1) : min(1) : int;
kb1k1status = hslider("kb1k1status", 0, 0, 1, 1) : min(1) : int;
x = hslider("x", 1, 0, 1, 0.001);
y = hslider("y", 1, 0, 1, 0.001);

strikeCutoff = 6500;
strikeSharpness = 0.5;
strikeGain = 1;
nModes = 10;
t60 = 30;
nExPos = 7;
exPos = min((x * 2 - 1 : abs), (y * 2 - 1 : abs)) * (nExPos - 1) : int;

bells =
    (kb0k0status : pm.strikeModel(10, strikeCutoff, strikeSharpness, strikeGain)
        : pm.englishBellModel(nModes, exPos, t60, 1, 3))
  + (kb0k1status : pm.strikeModel(10, strikeCutoff, strikeSharpness, strikeGain)
        : pm.frenchBellModel(nModes, exPos, t60, 1, 3))
  + (kb1k0status : pm.strikeModel(10, strikeCutoff, strikeSharpness, strikeGain)
        : pm.germanBellModel(nModes, exPos, t60, 1, 2.5))
  + (kb1k1status : pm.strikeModel(10, strikeCutoff, strikeSharpness, strikeGain)
        : pm.russianBellModel(nModes, exPos, t60, 1, 3)) :> *(0.2);

process = bells <: _,_;
