"""Decode model output like a TV (burst-referenced) and compare bars to standard NTSC."""
import math, model
st = model.stimulus()
for std in (0, 1):
    out = model.run(st, std)
    t0 = 3420  # line 1 (settled), colour bars
    # carrier phase per sample from sc_ref
    ph = []; p = 0
    for e in st:
        p = 0 if e[0] else (0 if p == 14 else p + 1); ph.append(p)
    def demod(a, b):
        I = Q = Y = 0.0; n = b - a
        for t in range(a, b):
            w = 2*math.pi*(ph[t-model.LAT+4] + 0.5)/15  # phase as seen by the modulator
            x = out[t] - 64
            I += x*math.sin(w)*2/n; Q += x*math.cos(w)*2/n; Y += x/n
        return Y, I, Q
    # burst (gate starts 32 after HS end at 240, delayed to output)
    _, bI, bQ = demod(t0+240+32+40+model.LAT, t0+240+32+40+90+model.LAT)
    bamp = math.hypot(bI, bQ); bph = math.atan2(bQ, bI)
    print(f"chroma_std={std}  burst amp {bamp:.1f} counts (IRE pp {2*bamp/127.5*100:.1f}), phase {math.degrees(bph):.1f} deg")
    names = ['red','green','blue','yellow','cyan','magenta','white','black']
    cols = [(1,0,0),(0,1,0),(0,0,1),(1,1,0),(0,1,1),(1,0,1),(1,1,1),(0,0,0)]
    for i in range(8):
        # bars are 320 clocks wide starting at x=0 but de starts at 620
        a = i*320 + 60; b = a + 210
        if a < 620 or b > 3180: continue
        Y, I, Q = demod(t0+a+model.LAT+15, t0+b+model.LAT+15)
        amp = math.hypot(I, Q); hue = math.degrees(math.atan2(Q, I) - bph) % 360
        R,G,B = cols[i]; y = .299*R+.587*G+.114*B; u = .492*(B-y); v = .877*(R-y)
        sh = math.degrees(math.atan2(v, u) - math.pi) % 360  # std hue vs burst (-U)
        # TV with ACC: chroma scaled so burst = 40 IRE pp (20 IRE amplitude)
        acc = 20/(bamp/127.5*100)
        sat = amp/127.5*acc; ssat = math.hypot(u, v)
        print(f"  {names[i]:8s} Y {Y/127.5:.3f} (std {y:.3f})  hue {hue:6.1f} (std {sh:6.1f})  sat after ACC {sat:.3f} (std {ssat:.3f}, x{sat/ssat:.2f})" if ssat > 0.01 else f"  {names[i]:8s} Y {Y/127.5:.3f} (std {y:.3f})  chroma {amp:.2f} counts (std 0)")
