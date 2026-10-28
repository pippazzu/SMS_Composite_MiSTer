"""Lines up the Master System encoder with the Mark III one: luma 50% point of
the first bar edge after the active picture starts, from tb_align.sv."""
import numpy as np
a = np.loadtxt('align.txt', dtype=np.int64, skiprows=100)  # the first clocks are still X
n, bl, m3, ms = a.T
V = lambda x: x / 2**21
k = np.ones(15) / 15
m3f = np.convolve(V(m3), k, 'same'); msf = np.convolve(V(ms), k, 'same')
print('jack range after settling: Mark III %.3f..%.3f V, Master System %.3f..%.3f V' %
      (V(m3[100000:]).min(), V(m3[100000:]).max(), V(ms[100000:]).min(), V(ms[100000:]).max()))
st = np.flatnonzero((bl[:-1] == 1) & (bl[1:] == 0)) + 1
st = st[st > 100000]
for f, name in ((m3f, 'Mark III'), (msf, 'Master System')):
    r = []
    for s in st[:40]:
        x = f[s - 200:s + 400]; base = x[:100].mean(); top = x[300:350].mean()
        c = np.flatnonzero(x > (base + top) / 2); c = c[c > 150][0]
        r.append((c - 200, base, top))
    r = np.array(r)
    print('%-14s 50%% at %+.1f clk after de, blank %.3f V, white bar %.3f V' % (name, *r.mean(0)))
