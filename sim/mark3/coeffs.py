"""Mark III board networks as exact zero-order-hold state-space systems at the
master clock (53.693175 MHz), and their Q16 fixed-point coefficients.

  A = exp(Ac T), B = Ac^-1 (A - I) Bc

Components from the Mark III schematic (171-5304):
  luma trap  Y OUT -R63 270- (L64 56u || C65 33p) -+- C66 18p -> GND
                                                   +- R67 470 -> GND, -> Y IN
  R-Y / B-Y  R71/R78 1k into C72/C79 270p          (then an emitter follower)
  video out  BA7230LS fV = 6 MHz typ. (-3 dB), modelled as one pole
"""
import numpy as np
from scipy.linalg import expm

FS = 53.693175e6
T = 1 / FS
Q = 1 << 16

R1, L, C, C2, R2 = 270.0, 56e-6, 33e-12, 18e-12, 470.0
RC_CHROMA = 1e3 * 270e-12
F_OUT = 6e6


def zoh(Ac, Bc):
    Ac = np.atleast_2d(Ac); Bc = np.atleast_2d(Bc).reshape(-1, 1)
    A = expm(Ac * T)
    B = np.linalg.solve(Ac, (A - np.eye(len(A))) @ Bc)
    return A, B.ravel()


def trap_continuous():
    # States: x0 = R1*iL (volts), x1 = vC (C65 = L64 voltage), x2 = vC2 (output node).
    # i1 = (u - x1 - x2)/R1; C x1' = i1 - iL; C2 x2' = i1 - x2/R2; L iL' = x1.
    Ac = np.array([
        [0,            R1 / L,                0],
        [-1 / (R1 * C), -1 / (R1 * C),        -1 / (R1 * C)],
        [0,            -1 / (R1 * C2),        -1 / (R1 * C2) - 1 / (R2 * C2)],
    ])
    Bc = np.array([0, 1 / (R1 * C), 1 / (R1 * C2)])
    return Ac, Bc


TRAP_A, TRAP_B = zoh(*trap_continuous())
TRAP_C = (R1 + R2) / R2          # y = TRAP_C * x2: DC gain normalised to 1
CHR_A, CHR_B = [v.item() for v in zoh(np.array([[-1 / RC_CHROMA]]), np.array([1 / RC_CHROMA]))]
W_OUT = 2 * np.pi * F_OUT
OUT_A, OUT_B = [v.item() for v in zoh(np.array([[-W_OUT]]), np.array([W_OUT]))]


def q(x): return int(np.round(x * Q))


QT_A = [[q(v) for v in row] for row in TRAP_A]
QT_B = [q(v) for v in TRAP_B]
QT_C = q(TRAP_C)
QC_A, QC_B = q(CHR_A), q(CHR_B)
QO_A, QO_B = q(OUT_A), q(OUT_B)

if __name__ == '__main__':
    np.set_printoptions(precision=6, suppress=True)
    print('trap A\n', TRAP_A, '\ntrap B', TRAP_B, '\ntrap C', TRAP_C)
    print('Q16 trap A', QT_A, 'B', QT_B, 'C', QT_C)
    print('chroma a %.6f b %.6f -> Q16 %d %d' % (CHR_A, CHR_B, QC_A, QC_B))
    print('out    a %.6f b %.6f -> Q16 %d %d' % (OUT_A, OUT_B, QO_A, QO_B))
    print('|eig(A)|', np.abs(np.linalg.eigvals(TRAP_A)))
