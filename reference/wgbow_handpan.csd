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

instr 1
    kamp = p4
    kfreq = p5
    kpres rspline p6, p7, 0.5, 2
    krat = 0.127236
    kvibf = 4.5
    kvibamp = 0
    asig wgbow kamp, kfreq, kpres, krat, kvibf, kvibamp, gisine, 20

    ; A short attack pulse gives the bowed body a struck/percussive onset.
    aattack expon 0.18, 0.08, 0.001
    asig = asig + (aattack * oscili(0.12, kfreq * 2.01, gisine))

    outs asig, asig
    gaSendL = gaSendL + asig * 0.35
    gaSendR = gaSendR + asig * 0.35
endin

instr 2
    arvbl, arvbr reverbsc gaSendL, gaSendR, 0.88, 6500
    outs arvbl, arvbr
    clear gaSendL, gaSendR
endin
</CsInstruments>
<CsScore>
; amp, frequency, minimum and maximum bow pressure
i 1  0.00 3.0  0.30 110.00 0.025 0.070
i 1  0.55 3.0  0.28 138.59 0.020 0.065
i 1  1.10 3.0  0.26 164.81 0.025 0.075
i 1  1.65 3.0  0.30 220.00 0.030 0.080
i 1  2.20 3.0  0.27 246.94 0.020 0.070
i 1  2.75 3.0  0.25 293.66 0.025 0.075
i 1  3.30 3.0  0.28 329.63 0.030 0.080
i 1  3.85 4.0  0.30 440.00 0.025 0.075
i 2  0.00 8.0
e
</CsScore>
</CsoundSynthesizer>
