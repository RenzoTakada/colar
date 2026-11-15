"""Sons do Colar, sintetizados (sem arquivo de terceiros). Cada opção tem um par: copiar e colar.
Uso: python3 -I design/sons/gerar.py <pasta-saida>
Gera <opcao>-copiar.wav e <opcao>-colar.wav (44,1 kHz, 16 bits, mono), curtos (< 160 ms) e suaves (pico -12 dBFS),
com ataque de 2 ms (sem clique) e decaimento exponencial, para não soar como alerta do sistema.
"""
import math
import random
import struct
import sys
import wave
from pathlib import Path

TAXA = 44100
PICO = 10 ** (-12 / 20)  # -12 dBFS


def envelope(n, ataque_ms=2.0, decai=30.0):
    a = int(TAXA * ataque_ms / 1000)
    out = []
    for i in range(n):
        t = i / TAXA
        e = math.exp(-decai * t)
        if i < a:
            e *= i / max(1, a)
        out.append(e)
    return out


def seno(freq, dur, decai, fase=0.0, harm=()):
    n = int(TAXA * dur)
    env = envelope(n, decai=decai)
    s = []
    for i in range(n):
        t = i / TAXA
        v = math.sin(2 * math.pi * freq * t + fase)
        for (mult, ganho) in harm:
            v += ganho * math.sin(2 * math.pi * freq * mult * t)
        s.append(v * env[i])
    return s


def ruido_filtrado(dur, decai, corte=0.15, semente=7):
    """Ruído passado num passa-baixa de um polo: soa como papel/ar, não como chiado."""
    rnd = random.Random(semente)
    n = int(TAXA * dur)
    env = envelope(n, ataque_ms=4, decai=decai)
    s, y = [], 0.0
    for i in range(n):
        y += corte * (rnd.uniform(-1, 1) - y)
        s.append(y * env[i] * 3)
    return s


def misturar(*partes):
    """(atraso_s, sinal, ganho) somados."""
    n = max(int(a * TAXA) + len(s) for a, s, _ in partes)
    out = [0.0] * n
    for a, s, g in partes:
        o = int(a * TAXA)
        for i, v in enumerate(s):
            out[o + i] += v * g
    return out


def normalizar(s):
    m = max(abs(v) for v in s) or 1
    return [v / m * PICO for v in s]


def gravar(caminho, s):
    s = normalizar(s)
    with wave.open(str(caminho), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TAXA)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in s))


def opcoes():
    return {
        # A: duas contas de vidro se tocando (copiar sobe, colar desce)
        "A-conta": (
            misturar((0, seno(2350, 0.12, 38, harm=((2.76, 0.18),)), 1.0),
                     (0.045, seno(2900, 0.10, 45, harm=((2.76, 0.15),)), 0.7)),
            misturar((0, seno(2900, 0.10, 45, harm=((2.76, 0.15),)), 0.7),
                     (0.045, seno(2050, 0.14, 32, harm=((2.76, 0.18),)), 1.0)),
        ),
        # B: papel deslizando (copiar curto e mais claro; colar um pouco mais longo e grave)
        "B-papel": (
            ruido_filtrado(0.07, 55, corte=0.35, semente=3),
            ruido_filtrado(0.11, 38, corte=0.18, semente=11),
        ),
        # C: toque de madeira (senos graves com harmônico inarmônico e queda rápida)
        "C-madeira": (
            misturar((0, seno(880, 0.08, 70, harm=((2.3, 0.35), (4.1, 0.12))), 1.0),
                     (0, ruido_filtrado(0.02, 160, corte=0.5), 0.25)),
            misturar((0, seno(620, 0.10, 55, harm=((2.3, 0.35), (4.1, 0.12))), 1.0),
                     (0, ruido_filtrado(0.02, 160, corte=0.5), 0.25)),
        ),
        # D: gota (seno com afinação que sobe rápido, como um plic; colar mais grave)
        "D-gota": (gota(700, 1150, 0.09), gota(520, 820, 0.11)),
    }


def gota(f0, f1, dur):
    n = int(TAXA * dur)
    env = envelope(n, decai=36)
    s, fase = [], 0.0
    for i in range(n):
        t = i / dur / TAXA
        f = f0 + (f1 - f0) * (1 - math.exp(-8 * t))
        fase += 2 * math.pi * f / TAXA
        s.append(math.sin(fase) * env[i])
    return s


if __name__ == "__main__":
    saida = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    saida.mkdir(parents=True, exist_ok=True)
    for nome, (copiar, colar) in opcoes().items():
        gravar(saida / f"{nome}-copiar.wav", copiar)
        gravar(saida / f"{nome}-colar.wav", colar)
        print(nome, f"{len(copiar)/TAXA*1000:.0f} ms / {len(colar)/TAXA*1000:.0f} ms")
