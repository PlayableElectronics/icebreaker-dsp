<CsoundSynthesizer>
<CsOptions>
-odac
</CsOptions>
<CsInstruments>
sr      =       44100
ksmps   =       32
nchnls  =       2
0dbfs   =       1
        seed    0

gisine  ftgen   0,0,4096,10,1
gaSendL,gaSendR init 0

instr 1
kamp     =        0.3
kfreq    =        p4
ipres1   =        p5
ipres2   =        p6
kpres    rspline  p5,p6,0.5,2
krat     =        0.127236
kvibf    =        4.5
kvibamp  =        0
iminfreq =        20
aSigL    wgbow    kamp,kfreq,kpres,krat,kvibf,kvibamp,gisine,iminfreq
kdel     rspline  0.01,0.1,0.1,0.5
kpres    vdel_k   kpres,kdel,0.2,2
aSigR    wgbow    kamp,kfreq,kpres,krat,kvibf,kvibamp,gisine,iminfreq
         outs     aSigL,aSigR
gaSendL  =        gaSendL + aSigL/3
gaSendR  =        gaSendR + aSigR/3
endin

instr 2
aRvbL,aRvbR reverbsc gaSendL,gaSendR,0.9,7000
            outs aRvbL,aRvbR
            clear gaSendL,gaSendR
endin
</CsInstruments>
<CsScore>
i 1  0 480  70 0.03 0.1
i 1  0 480  85 0.03 0.1
i 1  0 480 100 0.03 0.09
i 1  0 480 135 0.03 0.09
i 1  0 480 170 0.02 0.09
i 1  0 480 202 0.04 0.1
i 1  0 480 233 0.05 0.11
i 2 0 480
e
</CsScore>
</CsoundSynthesizer>
