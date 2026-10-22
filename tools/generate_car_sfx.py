"""Gera os efeitos sonoros do carro por síntese (sem dependências externas).

Saída em assets/audio/car/:
  engine_loop.wav  - motor 4 cilindros, loop; o pitch é variado no jogo pelo RPM
  skid_loop.wav    - chiado de pneu no asfalto, loop
  gravel_loop.wav  - rolagem em terra/grama com pedrinhas, loop
  impact.wav       - batida (one-shot)

Os loops levam um chunk "smpl" com os pontos de loop, que o importador de WAV
da Godot detecta automaticamente (Loop Mode = Detect From WAV).

Uso: python tools/generate_car_sfx.py
"""

import math
import os
import random
import struct

SR = 44100
TAU = 2.0 * math.pi
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "car")


class Biquad:
    """Filtro biquad (fórmulas RBJ): 'lp', 'hp' ou 'bp'."""

    def __init__(self, kind, freq, q=0.707):
        w = TAU * freq / SR
        c = math.cos(w)
        alpha = math.sin(w) / (2.0 * q)
        if kind == "lp":
            b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
        elif kind == "hp":
            b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
        else:
            b0, b1, b2 = alpha, 0.0, -alpha
        a0 = 1 + alpha
        self.b0, self.b1, self.b2 = b0 / a0, b1 / a0, b2 / a0
        self.a1, self.a2 = -2 * c / a0, (1 - alpha) / a0
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def __call__(self, x):
        y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        return y


def make_loop(x, n, fade):
    """Recebe n + fade amostras e devolve n amostras que repetem sem clique."""
    y = x[:n]
    for i in range(fade):
        t = i / fade
        y[i] = x[i] * math.sqrt(t) + x[n + i] * math.sqrt(1 - t)
    return y


def normalize(x, peak=0.89):
    m = max(abs(s) for s in x) or 1.0
    return [s * peak / m for s in x]


def write_wav(name, samples, loop=False):
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    body = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    body += b"data" + struct.pack("<I", len(data)) + data
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(samples) - 1, 0, 0)
        body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    path = os.path.join(OUT, name)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WAVE" + body)
    print(f"{name}: {len(samples) / SR:.2f}s")


def engine():
    # 55 Hz de explosões ~ 1650 RPM num 4 cilindros. Em 2 s cabem 110 ciclos
    # exatos, então a parte tonal já repete perfeitamente.
    f0 = 55.0
    n, fade, warm = SR * 2, SR // 10, 2000
    rng = random.Random(1)
    phases = [rng.random() * TAU for _ in range(14)]
    rasp = Biquad("bp", 900, 0.8)
    tone = Biquad("lp", 4000)
    out = []
    for i in range(warm + n + fade):
        cycles = f0 * (i - warm) / SR
        s = sum(math.sin(TAU * k * cycles + phases[k]) / k ** 0.7 for k in range(1, 13))
        s += 0.6 * math.sin(TAU * 0.5 * cycles + phases[0])  # irregularidade de 4 tempos
        pulse = math.exp(-(cycles % 1.0) * 5.0)  # cada explosão
        s = s * 0.35 + rasp(rng.uniform(-1, 1)) * 2.5 * pulse
        out.append(tone(math.tanh(s * 1.4)))
    return normalize(make_loop(out[warm:], n, fade))


def skid():
    n, fade, warm = SR * 2, SR // 5, 2000
    rng = random.Random(2)
    band1 = Biquad("bp", 1200, 6)
    band2 = Biquad("bp", 2400, 4)
    hp = Biquad("hp", 500)
    vib = 0.0
    ph = 0.0
    out = []
    for i in range(warm + n + fade):
        t = i / SR
        vib = vib * 0.9995 + rng.uniform(-1, 1) * 0.002
        ph += TAU * 1150 * (1 + 0.6 * vib) / SR
        chatter = 1 + 0.3 * math.sin(TAU * 13 * t)
        squeal = 0.5 * math.sin(ph) + 0.25 * math.sin(2.03 * ph)
        noise = band1(rng.uniform(-1, 1)) * 3 + band2(rng.uniform(-1, 1)) * 2
        out.append(hp((squeal + noise) * chatter))
    return normalize(make_loop(out[warm:], n, fade), 0.8)


def gravel():
    n, fade, warm = SR * 2, SR // 5, 2000
    rng = random.Random(3)
    rumble_lp = Biquad("lp", 900)
    crackle_bp = Biquad("bp", 2500, 1)
    brown = 0.0
    crackle = 0.0
    out = []
    for _ in range(warm + n + fade):
        brown = brown * 0.98 + rng.uniform(-1, 1) * 0.1
        if rng.random() < 160 / SR:  # pedrinha batendo no assoalho
            crackle = rng.uniform(0.3, 1.0) * rng.choice((-1, 1))
        crackle *= 0.975
        out.append(rumble_lp(brown) * 2.0 + crackle_bp(crackle + rng.uniform(-1, 1) * 0.05) * 1.5)
    return normalize(make_loop(out[warm:], n, fade), 0.8)


def impact():
    rng = random.Random(4)
    body_lp = Biquad("lp", 1500)
    rattle = [(310, 1.0), (467, 0.8), (733, 0.6), (1190, 0.4)]
    ph = 0.0
    out = []
    for i in range(int(SR * 0.7)):
        t = i / SR
        ph += TAU * (45 + 60 * math.exp(-t * 25)) / SR
        thump = math.sin(ph) * math.exp(-t * 9)
        crunch = body_lp(rng.uniform(-1, 1)) * math.exp(-t * 18)
        metal = sum(a * math.sin(TAU * f * t) for f, a in rattle) * math.exp(-t * 14)
        attack = min(1.0, t / 0.002)
        out.append((thump + crunch * 0.8 + metal * 0.15) * attack)
    return normalize(out)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write_wav("engine_loop.wav", engine(), loop=True)
    write_wav("skid_loop.wav", skid(), loop=True)
    write_wav("gravel_loop.wav", gravel(), loop=True)
    write_wav("impact.wav", impact())
