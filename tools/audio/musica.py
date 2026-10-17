"""Genera las 5 músicas de ambiente del juego, en bucle sin corte.

Uso: python musica.py <id|todas> <carpeta_salida> [--wav]

ids: biblioteca (la predeterminada), bosque, lluvia, noche, aventura.
Escribe <id>.ogg (o <id>.wav con --wav, para analizarlo con analizar.py).

Todas usan la paleta y la mezcla del boceto aprobado por Kevin (variante
«ambiental»): arpegio de pulso al 25 %, bajo triangular con una capa una
octava arriba, melodía cuadrada con vibrato, campanas de caja de música,
colchón de triángulo desafinado, hi-hat de ruido, eco entre canales y
reverberación larga. La sección A de «biblioteca» es la del boceto, nota a nota.

Las capas continuas (viento, lluvia) se generan cíclicas y se suman después
de plegar la cola, para que el bucle no tenga ni corte ni salto de volumen.
"""
import sys
from pathlib import Path

import numpy as np

from sintesis import (SR, Bus, campana, eco_pingpong, guardar_ogg, guardar_wav, midi,
                      mezclar, nivel, normalizar_nivel, nota, paso_alto, paso_bajo, paso_banda,
                      plegar_bucle, pulso, reverb, triangulo)

COLA = 8.0  # segundos de cola (eco y reverberación) que se pliegan al principio

# ─── Acordes: (arpegio [4 notas], bajo, colchón [4 notas]) ──────────────────

ACORDES = {
    # Do mayor / La menor (biblioteca, lluvia); las del boceto tal cual
    "Fmaj7": (["F4", "A4", "C5", "E5"], "F2", ["F3", "A3", "C4", "E4"]),
    "Em7":   (["E4", "G4", "B4", "D5"], "E2", ["E3", "G3", "B3", "D4"]),
    "Dm7":   (["D4", "F4", "A4", "C5"], "D2", ["D3", "F3", "A3", "C4"]),
    "Cmaj7": (["E4", "G4", "B4", "C5"], "C2", ["C3", "E3", "G3", "B3"]),
    "Am7":   (["E4", "G4", "A4", "C5"], "A2", ["A2", "C3", "E3", "G3"]),
    "G6":    (["D4", "G4", "B4", "E5"], "G2", ["G2", "B2", "D3", "E3"]),
    "Am9":   (["C4", "E4", "G4", "B4"], "A2", ["A2", "E3", "G3", "B3"]),
    "Dm9":   (["F4", "A4", "C5", "E5"], "D2", ["D3", "F3", "C4", "E4"]),
    "Esus4": (["E4", "A4", "B4", "E5"], "E2", ["E3", "A3", "B3", "E4"]),
    # Sol mayor (bosque)
    "Gmaj7": (["G4", "B4", "D5", "F#5"], "G2", ["G3", "B3", "D4", "F#4"]),
    "D6":    (["D4", "F#4", "A4", "B4"], "D2", ["D3", "F#3", "A3", "B3"]),
    # Re mayor (noche, aventura)
    "Dmaj7": (["D4", "F#4", "A4", "C#5"], "D2", ["D3", "F#3", "A3", "C#4"]),
    "Bm7":   (["D4", "F#4", "A4", "B4"], "B1", ["B2", "D3", "F#3", "A3"]),
    "Asus4": (["E4", "A4", "D5", "E5"], "A2", ["A2", "D3", "E3", "A3"]),
    "F#m7":  (["F#4", "A4", "C#5", "E5"], "F#2", ["F#3", "A3", "C#4", "E4"]),
    "A6":    (["E4", "F#4", "A4", "C#5"], "A2", ["A2", "C#3", "E3", "F#3"]),
    "D":     (["D4", "F#4", "A4", "D5"], "D2", ["D3", "F#3", "A3", "D4"]),
    "Bm":    (["D4", "F#4", "B4", "D5"], "B1", ["B2", "D3", "F#3", "B3"]),
    "G":     (["D4", "G4", "B4", "D5"], "G2", ["G2", "B2", "D3", "G3"]),
    "A":     (["E4", "A4", "C#5", "E5"], "A2", ["A2", "C#3", "E3", "A3"]),
    "F#m":   (["F#4", "A4", "C#5", "F#5"], "F#2", ["F#3", "A3", "C#4", "F#4"]),
}


# ─── Partituras ─────────────────────────────────────────────────────────────
# Melodías y campanas: (compás, pulso de inicio, duración en pulsos, nota),
# con los compases contados desde 0. "X|Y" es un compás partido: X la primera
# mitad, Y la segunda.

BIBLIOTECA_A = ["Fmaj7", "Em7", "Dm7", "Cmaj7", "Fmaj7", "Em7", "Am7", "G6",
                "Fmaj7", "Em7", "Dm7", "Cmaj7", "Fmaj7", "G6", "Am7", "Dm7|G6"]
BIBLIOTECA_B = ["Am7", "Dm7", "G6", "Cmaj7", "Fmaj7", "Em7", "Dm7", "G6"] * 2

BIBLIOTECA_MELODIA = [
    # Sección A: la del boceto (compases 9–16)
    (8, 0, 1, "A4"), (8, 1, 1, "C5"), (8, 2, 2, "E5"),
    (9, 0, 1.5, "D5"), (9, 1.5, 0.5, "B4"), (9, 2, 2, "G4"),
    (10, 0, 1, "F4"), (10, 1, 1, "A4"), (10, 2, 1, "C5"), (10, 3, 1, "D5"),
    (11, 0, 3, "E5"),
    (12, 0, 1, "A5"), (12, 1, 1, "G5"), (12, 2, 2, "E5"),
    (13, 0, 1, "D5"), (13, 1, 1, "E5"), (13, 2, 2, "G5"),
    (14, 0, 1.5, "E5"), (14, 1.5, 0.5, "D5"), (14, 2, 2, "C5"),
    (15, 0, 2, "D5"), (15, 2, 1.5, "B4"),
    # Sección B: melodía nueva en pentatónica de Do (compases 21–32)
    (20, 0, 1, "C5"), (20, 1, 1, "E5"), (20, 2, 2, "A5"),
    (21, 0, 1.5, "G5"), (21, 1.5, 0.5, "E5"), (21, 2, 2, "D5"),
    (22, 0, 1, "C5"), (22, 1, 1, "D5"), (22, 2, 1, "A4"), (22, 3, 1, "C5"),
    (23, 0, 3, "D5"),
    (24, 0, 1, "E5"), (24, 1, 1, "G5"), (24, 2, 2, "A5"),
    (25, 0, 1, "A5"), (25, 1, 1, "G5"), (25, 2, 2, "D5"),
    (26, 0, 1, "E5"), (26, 1, 1, "D5"), (26, 2, 2, "G4"),
    (27, 0, 3, "E5"),
    (28, 0, 1, "A4"), (28, 1, 1, "C5"), (28, 2, 2, "E5"),
    (29, 0, 1, "G5"), (29, 1, 1, "E5"), (29, 2, 2, "D5"),
    (30, 0, 1.5, "C5"), (30, 1.5, 0.5, "D5"), (30, 2, 2, "A4"),
    (31, 0, 2, "D5"), (31, 2, 1.5, "G4"),
]
BIBLIOTECA_CAMPANAS = [
    # Las del boceto (compases 5–8)
    (4, 0, 2, "C6"), (4, 2, 2, "B5"), (5, 0, 4, "G5"), (6, 0, 2, "A5"), (6, 2, 2, "E5"), (7, 0, 4, "D5"),
    # Entrada de la sección B (compases 17–20)
    (16, 0, 2, "E6"), (16, 2, 2, "C6"), (17, 0, 4, "A5"), (18, 0, 2, "B5"), (18, 2, 2, "D6"), (19, 0, 4, "G5"),
]

BOSQUE_A = ["Gmaj7", "Em7", "Cmaj7", "D6", "Am7", "D6", "Gmaj7", "Cmaj7"]
BOSQUE_B = ["Em7", "Am7", "D6", "Gmaj7", "Em7", "Cmaj7", "Am7", "D6"]
_BOSQUE_FRASE = [
    (0, 0, 1, "B4"), (0, 1, 1, "D5"), (0, 2, 2, "E5"),
    (1, 0, 1.5, "D5"), (1, 1.5, 0.5, "B4"), (1, 2, 2, "G4"),
    (2, 0, 2, "G5"), (2, 2, 1, "E5"), (2, 3, 1, "D5"),
    (3, 0, 3, "A4"),
    (4, 0, 1, "A4"), (4, 1, 1, "B4"), (4, 2, 2, "E5"),
    (5, 0, 1.5, "D5"), (5, 1.5, 0.5, "E5"), (5, 2, 2, "A4"),
    (6, 0, 1, "B4"), (6, 1, 1, "D5"), (6, 2, 2, "G5"),
]
BOSQUE_MELODIA = (
    [(c + 8, p, d, n) for c, p, d, n in _BOSQUE_FRASE] + [(15, 0, 3, "E5")]
    + [(c + 24, p, d, n) for c, p, d, n in _BOSQUE_FRASE] + [(31, 0, 3, "G5")]
)
BOSQUE_CAMPANAS = [
    (16, 0, 2, "B5"), (16, 2, 2, "G5"), (17, 0, 2, "A5"), (17, 2, 2, "E5"),
    (18, 0, 4, "F#5"), (19, 0, 2, "D6"), (19, 2, 2, "B5"), (20, 0, 2, "G5"), (20, 2, 2, "E5"),
    (21, 0, 2, "G5"), (21, 2, 2, "C6"), (22, 0, 4, "A5"), (23, 0, 2, "F#5"), (23, 2, 2, "A5"),
]

_LLUVIA_P1 = ["Am9", "Fmaj7", "Cmaj7", "G6"]
_LLUVIA_P2 = ["Dm9", "Fmaj7", "Am9", "Esus4"]
LLUVIA = _LLUVIA_P1 + _LLUVIA_P2 + _LLUVIA_P1 + _LLUVIA_P2 + _LLUVIA_P1 + _LLUVIA_P1 + _LLUVIA_P2
LLUVIA_MELODIA = [
    (8, 0, 4, "E5"), (9, 0, 2, "C5"), (9, 2, 2, "A4"), (10, 0, 4, "G4"), (11, 0, 2, "D5"), (11, 2, 2, "E5"),
    (12, 0, 4, "A4"), (13, 0, 2, "C5"), (13, 2, 2, "E5"), (14, 0, 4, "G5"), (15, 0, 3, "E5"),
    (20, 0, 2, "A4"), (20, 2, 2, "C5"), (21, 0, 4, "E5"), (22, 0, 2, "D5"), (22, 2, 2, "E5"), (23, 0, 4, "D5"),
    (24, 0, 2, "C5"), (24, 2, 2, "A4"), (25, 0, 4, "C5"), (26, 0, 2, "E5"), (26, 2, 2, "D5"), (27, 0, 3, "B4"),
]
# Campanas cada 2 compases: la nota más aguda del arpegio, una octava arriba.
LLUVIA_CAMPANAS = [
    (c, 0, 4, ACORDES[LLUVIA[c]][0][-1][:-1] + str(int(ACORDES[LLUVIA[c]][0][-1][-1]) + 1))
    for c in range(0, len(LLUVIA), 2)
]

NOCHE = ["Dmaj7", "Bm7", "Gmaj7", "Asus4", "Gmaj7", "F#m7", "Em7", "A6"] * 3
_NOCHE_1 = [
    (0, 0, 1, "F#5"), (0, 1, 1, "A5"), (0, 2, 2, "E5"),
    (1, 0, 2, "D5"), (1, 2, 2, "F#5"),
    (2, 0, 1, "B5"), (2, 1, 1, "A5"), (2, 2, 2, "F#5"),
    (3, 0, 3, "E5"),
    (4, 0, 1, "D5"), (4, 1, 1, "E5"), (4, 2, 2, "B4"),
    (5, 0, 2, "C#5"), (5, 2, 2, "A4"),
    (6, 0, 1, "B4"), (6, 1, 1, "D5"), (6, 2, 2, "E5"),
    (7, 0, 3, "F#5"),
]
_NOCHE_2 = [
    (8, 0, 2, "A5"), (8, 2, 2, "F#5"),
    (9, 0, 1, "B5"), (9, 1, 1, "A5"), (9, 2, 2, "F#5"),
    (10, 0, 4, "D6"),
    (11, 0, 2, "E6"), (11, 2, 2, "D6"),
    (12, 0, 2, "B5"), (12, 2, 2, "A5"),
    (13, 0, 4, "A5"),
    (14, 0, 2, "G5"), (14, 2, 2, "E5"),
    (15, 0, 3, "E5"),
]
# Tercera vuelta, más escasa: solo la primera nota de cada compás de la primera.
_NOCHE_3 = [(c + 16, 0, 4, n) for c, p, d, n in _NOCHE_1 if p == 0]
NOCHE_MELODIA = _NOCHE_1 + _NOCHE_2 + _NOCHE_3

_AVENTURA_A = ["D", "Bm", "G", "A", "Em7", "A", "D", "D"]
_AVENTURA_PUENTE = ["G", "A", "F#m", "Bm", "Em7", "G", "A", "A"]
AVENTURA = _AVENTURA_A * 2 + _AVENTURA_PUENTE + _AVENTURA_A * 2
_AVENTURA_FRASE = [
    (0, 0, 0.5, "F#5"), (0, 0.5, 0.5, "A5"), (0, 1, 1, "B5"), (0, 2, 1, "A5"), (0, 3, 1, "F#5"),
    (1, 0, 1, "D5"), (1, 1, 0.5, "E5"), (1, 1.5, 0.5, "F#5"), (1, 2, 2, "D5"),
    (2, 0, 0.5, "B4"), (2, 0.5, 0.5, "D5"), (2, 1, 1, "E5"), (2, 2, 1, "D5"), (2, 3, 1, "B4"),
    (3, 0, 2, "A4"), (3, 2, 1, "C#5"), (3, 3, 1, "E5"),
    (4, 0, 1, "E5"), (4, 1, 1, "G5"), (4, 2, 1, "B5"), (4, 3, 1, "A5"),
    (5, 0, 1.5, "A5"), (5, 1.5, 0.5, "E5"), (5, 2, 2, "C#5"),
    (6, 0, 1, "D5"), (6, 1, 1, "F#5"), (6, 2, 1, "A5"), (6, 3, 1, "F#5"),
]
AVENTURA_MELODIA = []
for _inicio, _final in ((0, [(7, 0, 3, "D5")]), (8, [(7, 0, 1, "A5"), (7, 1, 2, "F#5")]),
                        (24, [(7, 0, 3, "D5")]), (32, [(7, 0, 1, "A5"), (7, 1, 2, "F#5")])):
    AVENTURA_MELODIA += [(c + _inicio, p, d, n) for c, p, d, n in _AVENTURA_FRASE + _final]
AVENTURA_CAMPANAS = [
    (16, 0, 2, "B5"), (16, 2, 2, "D6"), (17, 0, 2, "C#6"), (17, 2, 2, "E6"), (18, 0, 4, "C#6"),
    (19, 0, 2, "B5"), (19, 2, 2, "F#5"), (20, 0, 2, "G5"), (20, 2, 2, "B5"), (21, 0, 2, "D6"),
    (21, 2, 2, "B5"), (22, 0, 4, "E6"), (23, 0, 2, "C#6"), (23, 2, 2, "A5"),
]


# ─── Pistas ─────────────────────────────────────────────────────────────────

PISTAS = {
    "biblioteca": {
        "bpm": 72, "compases": BIBLIOTECA_A + BIBLIOTECA_B,
        "arpegio": {"patron": [0, 1, 2, 3, 2, 1, 2, 3], "por_compas": 8, "env": (0.004, 0.32, 0.0, 0.18)},
        "melodia": BIBLIOTECA_MELODIA, "campanas": BIBLIOTECA_CAMPANAS,
        "lider": {"ciclo": 0.5, "armonicos": 7, "vibrato": 0.003},
        "hihat_desde": 8,
    },
    "bosque": {
        "bpm": 80, "compases": BOSQUE_A + BOSQUE_A + BOSQUE_B + BOSQUE_A,
        "arpegio": {"patron": [0, 1, 2, 3, 2, 1, 2, 3], "por_compas": 8, "env": (0.004, 0.32, 0.0, 0.18)},
        "melodia": BOSQUE_MELODIA, "campanas": BOSQUE_CAMPANAS,
        "lider": {"ciclo": 0.25, "armonicos": 5, "vibrato": 0.004},
        "hihat_desde": 8, "pajaros": -20.0, "viento": -22.0,
    },
    "lluvia": {
        "bpm": 66, "compases": LLUVIA,
        "arpegio": {"patron": [0, 1, 2, 3], "por_compas": 4, "env": (0.004, 0.6, 0.0, 0.3)},
        "melodia": LLUVIA_MELODIA, "campanas": LLUVIA_CAMPANAS,
        "lider": {"ciclo": 0.5, "armonicos": 5, "vibrato": 0.003},
        "lluvia": -18.0, "gotas": -24.0,
    },
    "noche": {
        "bpm": 60, "compases": NOCHE,
        "arpegio": {"patron": [0, 1, 2, 1, 2, 3, 2, 3, 2, 3, 2, 1], "por_compas": 12,
                    "env": (0.004, 0.3, 0.0, 0.18), "db": -8.0},
        # La melodía la llevan las campanas.
        "melodia_campanas": NOCHE_MELODIA, "campanas": [],
        "colchon_ataque": 1.2,
    },
    "aventura": {
        "bpm": 96, "compases": AVENTURA,
        "arpegio": {"patron": [0, 1, 2, 1, 3, 2, 1, 2] * 2, "por_compas": 16, "env": (0.003, 0.15, 0.0, 0.08)},
        "melodia": AVENTURA_MELODIA, "campanas": AVENTURA_CAMPANAS,
        "lider": {"ciclo": 0.5, "armonicos": 7, "vibrato": 0.002, "env": (0.01, 0.3, 0.6, 0.12)},
        "bajo_corcheas": True, "hihat_corcheas": True, "bombo": -14.0,
    },
}

ORDEN = ["biblioteca", "bosque", "lluvia", "noche", "aventura"]


# ─── Capas cíclicas (continuas, sin costura) ───────────────────────────────

def _ruido_ciclico(largo, rng, bajo, alto, rosa=False):
    """Ruido filtrado en banda, periódico con periodo 'largo' (se crea en el
    dominio de la frecuencia, así el final empalma con el principio)."""
    X = np.fft.rfft(rng.standard_normal(largo))
    f = np.fft.rfftfreq(largo, 1 / SR)
    f[0] = 1e-6
    H = np.sqrt(1 / (1 + (bajo / f) ** 4)) * np.sqrt(1 / (1 + (f / alto) ** 4))
    if rosa:
        H = H / np.sqrt(np.maximum(f, 20.0))
    return np.fft.irfft(X * H, largo)


def _lfo_ciclico(largo, hz_aprox, minimo):
    """Modulación lenta con un número entero de ciclos en el bucle."""
    segundos = largo / SR
    ciclos = max(1, round(hz_aprox * segundos))
    t = np.arange(largo) / SR
    return minimo + (1 - minimo) * (0.5 + 0.5 * np.sin(2 * np.pi * ciclos * t / segundos))


def _gotas_ciclicas(largo, rng):
    """Gotas: clics cortos de 2–6 kHz, de 4 a 10 por segundo, en un búfer
    periódico."""
    x = np.zeros(largo)
    clic = np.exp(-np.arange(int(0.004 * SR)) / (0.0012 * SR))
    for segundo in range(int(largo / SR) + 1):
        for _ in range(rng.integers(4, 11)):
            i = int((segundo + rng.random()) * SR) % largo
            fin = min(largo, i + len(clic))
            x[i:fin] += clic[: fin - i] * rng.uniform(0.3, 1.0) * rng.choice([-1, 1])
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(largo, 1 / SR)
    f[0] = 1e-6
    H = np.sqrt(1 / (1 + (2000 / f) ** 4)) * np.sqrt(1 / (1 + (f / 6000) ** 4))
    return np.fft.irfft(X * H, largo)


def _a_nivel(l, r, db, referencia=0.1):
    g = referencia * 10 ** (db / 20) / nivel(l, r, solo_activo=False)
    return l * g, r * g


# ─── Composición ────────────────────────────────────────────────────────────

def componer(id_pista):
    p = PISTAS[id_pista]
    beat = 60.0 / p["bpm"]
    compas = 4 * beat
    compases = p["compases"]
    largo = int(round(len(compases) * compas * SR))
    total = largo + int(COLA * SR)
    rng = np.random.default_rng(sum(map(ord, id_pista)))

    arpegio, bajo, colchon, melodia, campanas, ritmo, pajaros, bombo = (Bus(total) for _ in range(8))
    arp = p["arpegio"]
    sub = compas / arp["por_compas"]

    for c, simbolo in enumerate(compases):
        t0 = c * compas
        primero, _, segundo = simbolo.partition("|")
        segundo = segundo or primero
        notas_arp, raiz, pad = ACORDES[primero]
        notas_arp2, raiz2, _ = ACORDES[segundo]

        # Arpegio de pulso al 25 %, alternando izquierda y derecha.
        for i, idx in enumerate(arp["patron"]):
            fuente = notas_arp if i < arp["por_compas"] / 2 else notas_arp2
            nota(arpegio, t0 + i * sub, sub, midi(fuente[idx]), lambda f: pulso(f, 0.25, 9),
                 0.10, pan=(-0.3 if i % 2 == 0 else 0.3), env=arp["env"])

        # Bajo triangular con su capa una octava arriba (para parlantes pequeños).
        r1 = midi(raiz)
        if p.get("bajo_corcheas"):
            golpes = [(i * beat / 2, beat / 2, r1 if i % 2 == 0 else r1 + 7) for i in range(8)]
            env_bajo = (0.005, 0.25, 0.5, 0.06)
        else:
            r2 = midi(raiz2) if segundo != primero else r1 + 7
            golpes = [(0, 2 * beat, r1), (2 * beat, 2 * beat, r2)]
            env_bajo = (0.01, 0.9, 0.7, 0.12)
        for k, (desde, dur, m) in enumerate(golpes):
            v = 0.42 if k == 0 else 0.36
            nota(bajo, t0 + desde, dur, m, triangulo, v, env=env_bajo)
            nota(bajo, t0 + desde, dur, m + 12, triangulo, v * 0.3, env=(0.01, 0.6, 0.5, 0.12))

        # Colchón: triángulo suave, desafinado entre izquierda y derecha.
        ataque = p.get("colchon_ataque", 0.7)
        for n in pad:
            for lado, des in ((-0.6, -0.0012), (0.6, 0.0012)):
                nota(colchon, t0, compas, midi(n), lambda f: triangulo(f, 3), 0.030,
                     pan=lado, env=(ataque, 1.5, 0.8, 0.9), desafinar=des)

        # Hi-hat de ruido, muy suave.
        if p.get("hihat_corcheas"):
            tiempos = [i * 0.5 for i in range(8)]
        elif "hihat_desde" in p and c >= p["hihat_desde"]:
            tiempos = [i + 0.5 for i in range(4)]
        else:
            tiempos = []
        for k, tb in enumerate(tiempos):
            golpe = rng.standard_normal(int(0.05 * SR))
            golpe = np.diff(golpe, prepend=0) * np.exp(-np.arange(len(golpe)) / (0.012 * SR))
            ritmo.poner(t0 + tb * beat, golpe * 0.018, pan=(-0.2 if k % 2 else 0.2))

        # Bombo suave en los tiempos 1 y 3 (aventura).
        if "bombo" in p:
            t = np.arange(int(0.12 * SR)) / SR
            fase = 2 * np.pi * np.cumsum(60 * (40 / 60) ** (t / 0.12)) / SR
            golpe = np.sin(fase) * np.exp(-t / 0.04)
            for tb in (0, 2):
                bombo.poner(t0 + tb * beat, golpe)

    # Melodía: cuadrada con vibrato (o campanas, en noche).
    if "melodia" in p:
        lider = p["lider"]
        timbre = lambda f: pulso(f, lider["ciclo"], lider["armonicos"])
        for c, pi, dur, n in p["melodia"]:
            nota(melodia, c * compas + pi * beat, dur * beat * 0.95, midi(n), timbre, 0.11, pan=0.1,
                 env=lider.get("env", (0.03, 0.5, 0.7, 0.2)), vibrato=lider["vibrato"])
    for c, pi, dur, n in p.get("melodia_campanas", []):
        nota(melodia, c * compas + pi * beat, dur * beat, midi(n), campana, 0.10, pan=-0.1,
             env=(0.002, 1.2, 0.0, 0.8))
    for c, pi, dur, n in p["campanas"]:
        nota(campanas, c * compas + pi * beat, dur * beat, midi(n), campana, 0.10, pan=-0.15,
             env=(0.002, 0.9, 0.0, 0.6))

    # Pájaros (bosque): grupos de 2 a 4 píos cada 3–7 s.
    if "pajaros" in p:
        t = 2.0
        while t < largo / SR - 1.0:
            pan = rng.uniform(-0.6, 0.6)
            for k in range(rng.integers(2, 5)):
                dur = rng.uniform(0.06, 0.12)
                n = int(dur * SR)
                ini, fin = (2500, 4000) if rng.random() < 0.6 else (4000, 2500)
                f = ini * (fin / ini) ** (np.arange(n) / n)
                pio = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * np.arange(n) / n) ** 2
                pajaros.poner(t + k * rng.uniform(0.09, 0.16), pio, pan)
            t += rng.uniform(3, 7)

    # Eco entre canales en el arpegio y las campanas.
    eco_pingpong(arpegio, 0.75 * beat, 0.32, 0.45)
    eco_pingpong(campanas, 0.75 * beat, 0.3, 0.4)
    if "melodia_campanas" in p:
        eco_pingpong(melodia, 0.75 * beat, 0.3, 0.4)

    l, r = mezclar([
        (melodia, 0.0),
        (arpegio, arp.get("db", -4.0)),
        (bajo, -5.0),
        (campanas, -4.0),
        (colchon, -11.0),
        (ritmo, -17.0),
        (pajaros, p.get("pajaros", -20.0)),
        (bombo, p.get("bombo", -14.0)),
    ])
    l, r = reverb(l, r, rt60=2.6, mezcla=0.30)
    l = paso_alto(paso_bajo(l, 9000), 35)
    r = paso_alto(paso_bajo(r, 9000), 35)
    l, r = plegar_bucle(l, r, largo)

    # Capas continuas, ya cíclicas: se suman después de plegar.
    if "viento" in p:
        lfo = _lfo_ciclico(largo, 0.07, 0.4)
        vl, vr = (_ruido_ciclico(largo, rng, 250, 900, rosa=True) * lfo for _ in range(2))
        vl, vr = _a_nivel(vl, vr, p["viento"])
        l, r = l + vl, r + vr
    if "lluvia" in p:
        ll, lr = (_ruido_ciclico(largo, rng, 1500, 8000) for _ in range(2))
        ll, lr = _a_nivel(ll, lr, p["lluvia"])
        gl, gr = (_gotas_ciclicas(largo, rng) for _ in range(2))
        gl, gr = _a_nivel(gl, gr, p["gotas"])
        l, r = l + ll + gl, r + lr + gr

    return normalizar_nivel(l, r, dbfs=-18.0, techo_dbfs=-1.0)


def main(argv):
    pedido, carpeta = argv[0], Path(argv[1])
    wav = "--wav" in argv
    carpeta.mkdir(parents=True, exist_ok=True)
    for id_pista in (ORDEN if pedido == "todas" else [pedido]):
        l, r = componer(id_pista)
        if wav:
            guardar_wav(carpeta / f"{id_pista}.wav", l, r)
        else:
            guardar_ogg(carpeta / f"{id_pista}.ogg", l, r)
        print(f"{id_pista}: {len(l) / SR:.1f} s")


if __name__ == "__main__":
    main(sys.argv[1:])
