import("stdfaust.lib");

declare name "English Bell Isolated Strike";

strike = os.impulse;
body = strike : pm.englishBellModel(10, 3, 8, 1, 3);
process = 0.8 * body <: _,_;
