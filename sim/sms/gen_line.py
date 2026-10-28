"""One active SMS line (sc, hs, hb per clock, 3420 clocks) from the real raster
(../mark3/tv_stim.txt, made by ../mark3/run.sh) for tb_falsesync.sv."""
import itertools
buf = [l.split() for l in itertools.islice(open('../mark3/tv_stim.txt'), 0, 200000)]
hs = [int(r[1], 16) for r in buf]; hb = [int(r[3], 16) for r in buf]; vb = [int(r[4], 16) for r in buf]
s = next(t for t in range(100000, 196000) if hs[t] and not hs[t-1] and not vb[t+1500] and not hb[t+1500])
with open('line.txt', 'w') as o:
    for r in buf[s:s+3420]: o.write('%s %s %s\n' % (r[0], r[1], r[3]))
