"""Genera los 13 efectos de sonido del juego.

Uso: python efectos.py <carpeta_salida>

Mismo estilo retro que la música (pulso, triángulo, campana y ruido), cortos y
suaves: mono a 44,1 kHz, pico a -6 dBFS, una reverberación corta (0,6 s al
15 %) y menos de 1,5 s cada uno, con un fundido final para no cortar en seco.
"""
import sys
from pathlib import Path

import numpy as np

from sintesis import (SR, campana, envolvente, guardar_wav, hz, midi, normalizar_pico,
                      paso_banda, pulso, reverb, triangulo)

DURACION_MAX = 1.45
rng = np.random.default_rng(2026)


def _tono(m, dur, timbre, env, freq=None):
    """Una nota con su envolvente. freq permite pasar un barrido ya hecho."""
    puerta = int(dur * SR)
    e = envolvente(puerta, *env)
    f = np.full(len(e), hz(m)) if freq is None else np.resize(freq, len(e))
    return timbre(f) * e


def _poner(destino, inicio, señal, vel=1.0):
    i = int(inicio * SR)
    señal = señal[: max(0, len(destino) - i)]
    destino[i:i + len(señal)] += señal * vel


def _ruido(dur, bajo, alto, env):
    puerta = int(dur * SR)
    e = envolvente(puerta, *env)
    return paso_banda(rng.standard_normal(len(e)), bajo, alto) * e


def _terminar(x, mezcla=0.15):
    """Reverberación corta, recorte del silencio final, fundido y pico -6 dBFS."""
    l, r = reverb(x, x, rt60=0.6, mezcla=mezcla)
    y = (l + r) / 2
    umbral = np.abs(y).max() * 10 ** (-60 / 20)
    sonando = np.nonzero(np.abs(y) > umbral)[0]
    fin = min(len(y), sonando[-1] + int(0.02 * SR) if len(sonando) else len(y), int(DURACION_MAX * SR))
    y = y[:fin].copy()
    fundido = min(len(y), int(0.06 * SR))
    y[-fundido:] *= np.linspace(1, 0, fundido) ** 2
    return normalizar_pico(y, -6.0)


def _vacio(segundos=1.6):
    return np.zeros(int(segundos * SR))


def clic():
    x = _vacio(0.4)
    _poner(x, 0, _tono(midi("G6"), 0.03, lambda f: pulso(f, 0.25, 8), (0.001, 0.012, 0.0, 0.01)))
    return _terminar(x, 0.08)


def abrir():
    x = _vacio(0.6)
    timbre = lambda f: 0.8 * triangulo(f, 7) + 0.2 * pulso(f, 0.5, 5)
    _poner(x, 0.00, _tono(midi("C6"), 0.06, timbre, (0.003, 0.05, 0.3, 0.04)))
    _poner(x, 0.06, _tono(midi("G6"), 0.06, timbre, (0.003, 0.05, 0.3, 0.05)))
    return _terminar(x)


def cerrar():
    x = _vacio(0.6)
    timbre = lambda f: 0.8 * triangulo(f, 7) + 0.2 * pulso(f, 0.5, 5)
    _poner(x, 0.00, _tono(midi("G6"), 0.06, timbre, (0.003, 0.05, 0.3, 0.04)))
    _poner(x, 0.06, _tono(midi("C6"), 0.06, timbre, (0.003, 0.05, 0.3, 0.05)))
    return _terminar(x)


def puerta():
    x = _vacio(1.2)
    dur = 0.5
    t = np.arange(int(dur * SR) + int(0.3 * SR)) / SR
    barrido = 300 * (1200 / 300) ** np.clip(t / dur, 0, 1)
    tono = _tono(0, dur, lambda f: 0.7 * triangulo(f, 9) + 0.3 * pulso(f, 0.125, 6),
                 (0.05, 0.4, 0.6, 0.12), freq=barrido)
    _poner(x, 0, tono)
    _poner(x, 0, _ruido(dur, 800, 3000, (0.15, 0.3, 0.4, 0.1)), 0.25)
    # Eco: dos repeticiones más suaves.
    seco = x.copy()
    for k, g in ((1, 0.35), (2, 0.15)):
        d = int(0.12 * k * SR)
        x[d:] += seco[: len(x) - d] * g
    return _terminar(x)


def pagina():
    x = _vacio(0.5)
    _poner(x, 0.00, _ruido(0.09, 2000, 6000, (0.005, 0.05, 0.2, 0.03)))
    _poner(x, 0.07, _ruido(0.08, 2500, 6000, (0.01, 0.04, 0.2, 0.03)), 0.6)
    return _terminar(x, 0.1)


def trazo():
    x = _vacio(0.4)
    ruido = _ruido(0.12, 1500, 4000, (0.09, 0.2, 1.0, 0.02))
    _poner(x, 0, ruido)
    return _terminar(x, 0.1)


def acierto():
    x = _vacio(0.9)
    timbre = lambda f: 0.7 * pulso(f, 0.5, 7) + 0.3 * campana(f)
    _poner(x, 0.00, _tono(midi("E6"), 0.07, timbre, (0.003, 0.06, 0.4, 0.05)))
    _poner(x, 0.07, _tono(midi("A6"), 0.16, timbre, (0.003, 0.15, 0.4, 0.12)))
    return _terminar(x)


def error():
    x = _vacio(0.9)
    timbre = lambda f: triangulo(f, 5)
    _poner(x, 0.00, _tono(midi("A4"), 0.09, timbre, (0.005, 0.08, 0.5, 0.05)))
    _poner(x, 0.10, _tono(midi("F4"), 0.20, timbre, (0.005, 0.18, 0.5, 0.12)))
    return _terminar(x)


def fin_lectura():
    x = _vacio(1.3)
    timbre = lambda f: 0.6 * pulso(f, 0.25, 8) + 0.4 * campana(f)
    for i, n in enumerate(["C5", "E5", "G5", "C6"]):
        dur = 0.35 if n == "C6" else 0.1
        _poner(x, i * 0.11, _tono(midi(n), dur, timbre, (0.003, 0.2, 0.3, 0.15)))
    return _terminar(x)


def aprobada():
    x = _vacio(1.6)
    lider = lambda f: pulso(f, 0.5, 7)
    for i, n in enumerate(["C5", "E5", "G5"]):
        _poner(x, i * 0.09, _tono(midi(n), 0.08, lider, (0.003, 0.06, 0.5, 0.04)), 0.9)
    _poner(x, 0.27, _tono(midi("C6"), 0.75, lider, (0.005, 0.5, 0.6, 0.2)))
    for n in ["C4", "E4", "G4"]:
        _poner(x, 0.27, _tono(midi(n), 0.75, lambda f: triangulo(f, 5), (0.02, 0.6, 0.6, 0.2)), 0.35)
    return _terminar(x)


def desbloqueo():
    x = _vacio(1.3)
    _poner(x, 0.00, _tono(midi("C7"), 0.5, campana, (0.002, 0.5, 0.0, 0.3)))
    _poner(x, 0.12, _tono(midi("E7"), 0.5, campana, (0.002, 0.5, 0.0, 0.3)), 0.8)
    return _terminar(x, 0.25)


def logro():
    x = _vacio(1.4)
    for i, n in enumerate(["G6", "B6", "D7", "G7"]):
        _poner(x, i * 0.07, _tono(midi(n), 0.4, campana, (0.002, 0.35, 0.0, 0.25)), 1.0 - i * 0.1)
    return _terminar(x, 0.3)


def no():
    x = _vacio(0.6)
    timbre = lambda f: triangulo(f, 5)
    _poner(x, 0.00, _tono(midi("C4"), 0.1, timbre, (0.004, 0.08, 0.5, 0.03)))
    _poner(x, 0.16, _tono(midi("C4"), 0.12, timbre, (0.004, 0.1, 0.5, 0.04)))
    return _terminar(x, 0.1)


EFECTOS = {
    "clic": clic, "abrir": abrir, "cerrar": cerrar, "puerta": puerta,
    "pagina": pagina, "trazo": trazo, "acierto": acierto, "error": error,
    "fin_lectura": fin_lectura, "aprobada": aprobada, "desbloqueo": desbloqueo,
    "logro": logro, "no": no,
}


if __name__ == "__main__":
    salida = Path(sys.argv[1])
    salida.mkdir(parents=True, exist_ok=True)
    for nombre, generar in EFECTOS.items():
        guardar_wav(salida / f"{nombre}.wav", generar())
        print(f"{nombre}.wav")
