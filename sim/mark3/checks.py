"""Numeric checks (MiSTer Analogue Output skill, section 4): numbers, not pictures.
Needs video_pins.txt from tb_video.vhd (the core's own rtl/video.vhd)."""
import collections, numpy as np
from scipy import signal
import coeffs, coeffs as K, model, tv

FS = K.FS; US = 1e6 / FS
MV = 714 / 127.5              # mV per DAC count with white at 0.714 V
ok = True
def check(name, cond, txt):
    global ok; ok &= bool(cond); print(('PASS ' if cond else 'FAIL ') + name + ': ' + txt)

# 1. raster from the real VDP timing
hs, vs, hb, vb = tv.load_pins()
rise = np.flatnonzero(hs[1:] & ~hs[:-1]) + 1; fall = np.flatnonzero(~hs[1:] & hs[:-1]) + 1
ll = collections.Counter(np.diff(rise)); hw = collections.Counter((f - r) for r, f in zip(rise, fall[fall > rise[0]]))
vr = np.flatnonzero(vs[1:] & ~vs[:-1]) + 1
check('line length', set(ll) == {3420}, '%s clocks (228 carrier cycles)' % dict(ll))
check('HSync width', set(hw) == {240}, '%s clocks = %.2f us' % (dict(hw), 240 * US))
check('frame', set(np.diff(vr)) == {262 * 3420}, '%s lines' % sorted(set(np.diff(vr) / 3420)))
bp = [f for f in np.flatnonzero(~hb[1:] & hb[:-1]) + 1 if f > fall[3]][0] - fall[3]
check('back porch', bp == 380, '%d clocks = %.2f us after the end of HSync' % (bp, bp * US))

# 2. encoder on the real raster
img = tv.pattern('bars'); st = tv.stimulus(img, hs, vs, hb, vb)
out = np.array(model.run(st, 0)); L = model.LAT
hsx = np.array([e[1] for e in st]); f0 = [i for i in range(1, len(st)) if hsx[i - 1] and not hsx[i]][20]
seg = out[f0 + L: f0 + L + 3000].astype(int)
bur = np.flatnonzero(np.abs(seg - 64) > 3); b0, b1 = bur[0], bur[bur < 300][-1]
check('burst start', abs(b0 * US - 0.6) < 0.1, '%.2f us after the end of HSync (gate 0.60 us)' % (b0 * US))
check('burst width', abs((b1 - b0) * US / (1 / 3.579545) - 9) < 0.6, '%.1f cycles' % ((b1 - b0) * US * 3.579545))
row = [i for i, e in enumerate(st) if e[4] and e[5] == 255 and e[6] == 255 and e[7] == 255]
white = np.median(out[np.array(row[100:150]) + L]); blank = np.median(out[f0 + L + 300: f0 + L + 360])
check('blank', blank == 64, '%d counts' % blank)
check('white', abs(white - 191.5) <= 1, '%d counts (%.0f mV above blank)' % (white, (white - 64) * MV))
vsx = np.array([e[2] for e in st])
ln_vs = [i for i in range(1, len(st) - 400) if hsx[i - 1] and not hsx[i] and vsx[i]]
check('no burst in VSync', all(np.all(np.abs(out[i + L:i + L + 300].astype(int) - 64) <= 1) for i in ln_vs),
      '%d lines' % len(ln_vs))

# 3. fixed point against the float ZOH model
win = st[3420 * 30:3420 * 50]
lv = []; model.run(win, 0, lv); fl = model.run_float(win, 0)
err = np.max(np.abs(np.array([v[0] for v in lv]) / 256 - np.array(fl)))
check('Q16 vs float', err * MV < 0.5, 'max %.3f counts = %.2f mV (output LSB is %.1f mV)' % (err, err * MV, MV))
hdr = max(v[5] for v in lv) / 65536
check('state headroom', hdr < 3.5, 'max |trap state| %.2f of Q3.16 +-4' % hdr)

# 4. networks: the ZOH matrices reproduce the analog circuit at every sample
# for a staircase input, which is what a DAC driven at the master clock is.
# (Their frequency response differs from H(jw) near the notch because a
# staircase is not a sine; the analog notch itself sits at 3.70 MHz.)
Ac, Bc = coeffs.trap_continuous()
sysc = signal.StateSpace(Ac, Bc.reshape(-1, 1), np.array([[0, 0, K.TRAP_C]]), [[0]])
n = 400; tt = np.arange(n) / FS
u = ((np.arange(n) // 10) % 2).astype(float)            # 1-pixel black/white stripes
_, ya, _ = signal.lsim(sysc, u, tt, interp=False)          # exact, zero-order hold
A = np.array(K.QT_A) / 65536; B = np.array(K.QT_B) / 65536; x = np.zeros(3); yq = []
for v in u: yq.append(K.QT_C / 65536 * x[2]); x = A @ x + B * v
e = np.max(np.abs(np.array(yq) - ya))
check('trap vs circuit', e * 714 < 0.5, 'stripes: max %.3f mV (white 714 mV)' % (e * 714))
for f in (1e6, 2e6, 3e6, 3.58e6):
    z = 2j * np.pi * f; ZLC = z * K.L / (1 + z * z * K.L * K.C); Zsh = K.R2 / (1 + z * K.R2 * K.C2)
    print('     trap circuit %.2f MHz: %.1f dB' % (f / 1e6, 20 * np.log10(abs(Zsh / (K.R1 + ZLC + Zsh) * K.TRAP_C))))
print('ALL PASS' if ok else 'SOME FAILED')
