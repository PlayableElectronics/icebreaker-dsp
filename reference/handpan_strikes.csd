<CsoundSynthesizer>
<CsOptions>
-odac
</CsOptions>
<CsInstruments>
sr = 44100
ksmps = 32
nchnls = 2
0dbfs = 1
seed 0

gisine ftgen 0, 0, 4096, 10, 1
gaSendL init 0
gaSendR init 0

; Each event has its own:
; p4 pitch, p5 level, p6/p7 pressure range, p8 attack time,
; p9 body/reverb send, p10 stereo position, p11 decay time.
instr 1
    kfreq = p4
    kamp = p5
    kpres rspline p6, p7, 0.5, 2
    krat = 0.127236
    kvibf = 4.5
    kvibamp = 0

    ; Smooth pressure-fed waveguide body.
    asig wgbow kamp, kfreq, kpres, krat, kvibf, kvibamp, gisine, 20

    ; A short tonal strike, not a full-scale noise burst.
    aenv expon 1, p8, 0.001
    astrike oscili kamp * 0.22 * aenv, kfreq * 2.01, gisine
    asig = asig + astrike

    ; Individual decay envelope makes each event finite and playable.
    avoice linen asig, 0.005, p11, 0.08
    aleft, aright pan2 avoice, p10
    outs aleft, aright

    gaSendL = gaSendL + aleft * p9
    gaSendR = gaSendR + aright * p9
endin

instr 2
    arvbl, arvbr reverbsc gaSendL, gaSendR, 0.90, 7000
    outs arvbl, arvbr
    clear gaSendL, gaSendR
endin
</CsInstruments>
<CsScore>
; p4=freq p5=amp p6/p7=pressure range p8=attack p9=reverb p10=pan p11=decay
i 1 0.00 3.0  110.00 0.28 0.025 0.070 0.10 0.45 0.38 2.8
i 1 0.35 3.0  164.81 0.24 0.020 0.065 0.08 0.50 0.62 2.8
i 1 0.70 3.0  220.00 0.30 0.030 0.080 0.06 0.40 0.47 3.0
i 1 1.10 3.0  246.94 0.26 0.020 0.070 0.12 0.55 0.54 2.6
i 1 1.55 3.0  329.63 0.22 0.030 0.085 0.05 0.35 0.42 2.4
i 1 2.00 3.0  440.00 0.25 0.025 0.075 0.09 0.60 0.58 2.5
i 2 0 8
e
</CsScore>
</CsoundSynthesizer>
