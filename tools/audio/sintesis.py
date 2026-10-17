"""Piezas de síntesis para la música y los efectos del juego.

Salen del boceto aprobado por Kevin (docs/superpowers/bocetos/2026-10-16-sonido/
boceto_biblioteca.py, variante «ambiental»), separadas de su composición:
osciladores limitados en banda (sin aliasing), envolventes, buses estéreo,
filtros en frecuencia, eco, reverberación, mezcla por nivel percibido y bucle
sin corte. Todo se genera aquí, así que el audio es original.

Los filtros y la reverberación trabajan con FFT sobre el búfer entero (fase
cero), con relleno de ceros para que nada dé la vuelta.
"""
import wave

import numpy as np

SR = 44100

NOMBRES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
           "G#": 8, "A": 9, "A#": 10, "B": 11}


def midi(nombre):
    """'C4' -> 60. Admite sostenidos ('F#3')."""
    if nombre[1] == "#":
        return 12 * (int(nombre[2:]) + 1) + NOMBRES[nombre[:2]]
    return 12 * (int(nombre[1:]) + 1) + NOMBRES[nombre[0]]


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# ─── Osciladores limitados en banda ─────────────────────────────────────────

def fase(freq):
    return 2 * np.pi * np.cumsum(freq) / SR


def pulso(freq, ciclo=0.5, armonicos=10):
    """Onda de pulso por suma de armónicos (25 %: sonido NES; 50 %: cuadrada)."""
    ph = fase(freq)
    f0 = float(freq.max())
    out = np.zeros(len(freq))
    for h in range(1, armonicos + 1):
        if h * f0 > 0.45 * SR:
            break
        a = (2 / (h * np.pi)) * np.sin(h * np.pi * ciclo)
        if abs(a) > 1e-6:
            out += a * np.cos(h * ph)
    return out


def triangulo(freq, armonicos=15):
    ph = fase(freq)
    f0 = float(freq.max())
    out = np.zeros(len(freq))
    for k, h in enumerate(range(1, armonicos + 1, 2)):
        if h * f0 > 0.45 * SR:
            break
        out += ((-1) ** k) * np.sin(h * ph) / h ** 2
    return out * 8 / np.pi ** 2


def campana(freq):
    """Caja de música: seno con un parcial agudo que se apaga antes."""
    ph = fase(freq)
    t = np.arange(len(freq)) / SR
    return np.sin(ph) + 0.25 * np.sin(4.0 * ph) * np.exp(-t / 0.25)


def envolvente(puerta, a, d, s, r):
    """ADSR con caídas exponenciales. puerta en muestras; a, d, r en segundos."""
    A = max(2, int(a * SR))
    G = max(puerta, A + 1)
    R = int(r * SR * 6) + 1
    e = np.empty(G + R)
    e[:A] = np.linspace(0, 1, A, endpoint=False)
    td = np.arange(G - A) / SR
    e[A:G] = s + (1 - s) * np.exp(-td / max(d, 1e-4))
    tr = np.arange(R) / SR
    e[G:] = e[G - 1] * np.exp(-tr / max(r, 1e-4))
    # Rampa final para que ninguna nota acabe en seco (sin clics).
    k = min(256, len(e))
    e[-k:] *= np.linspace(1, 0, k)
    return e


# ─── Buses estéreo ──────────────────────────────────────────────────────────

class Bus:
    def __init__(self, largo):
        self.l = np.zeros(largo)
        self.r = np.zeros(largo)

    def poner(self, inicio, señal, pan=0.0):
        """Suma una señal mono en el instante inicio (s), con panorama -1..1."""
        n = len(self.l)
        i = int(inicio * SR)
        if i >= n:
            return
        señal = señal[: n - i]
        gl = np.cos((pan + 1) * np.pi / 4)
        gr = np.sin((pan + 1) * np.pi / 4)
        self.l[i:i + len(señal)] += señal * gl
        self.r[i:i + len(señal)] += señal * gr


def nota(bus, inicio, dur, m, timbre, vel, pan=0.0, env=(0.01, 0.3, 0.6, 0.15),
         vibrato=0.0, desafinar=0.0):
    puerta = int(dur * SR)
    e = envolvente(puerta, *env)
    f = np.full(len(e), hz(m) * (1 + desafinar))
    if vibrato:
        t = np.arange(len(e)) / SR
        prof = vibrato * np.clip((t - 0.25) / 0.3, 0, 1)
        f = f * (1 + prof * np.sin(2 * np.pi * 5.0 * t))
    bus.poner(inicio, timbre(f) * e * vel, pan)


# ─── Filtros en frecuencia (fase cero) ──────────────────────────────────────

def _nfft(n):
    return 1 << int(np.ceil(np.log2(n + SR)))


def paso_bajo(x, corte, orden=1):
    nfft = _nfft(len(x))
    X = np.fft.rfft(x, nfft)
    f = np.fft.rfftfreq(nfft, 1 / SR)
    H = 1 / np.sqrt(1 + (f / corte) ** (2 * orden))
    return np.fft.irfft(X * H, nfft)[: len(x)]


def paso_alto(x, corte, orden=1):
    nfft = _nfft(len(x))
    X = np.fft.rfft(x, nfft)
    f = np.fft.rfftfreq(nfft, 1 / SR)
    f[0] = 1e-6
    H = 1 / np.sqrt(1 + (corte / f) ** (2 * orden))
    return np.fft.irfft(X * H, nfft)[: len(x)]


def paso_banda(x, bajo, alto, orden=2):
    return paso_alto(paso_bajo(x, alto, orden), bajo, orden)


def eco_pingpong(bus, retardo, realim, mezcla, repeticiones=6):
    """Repeticiones alternas izquierda/derecha, cada vez más oscuras."""
    n = len(bus.l)
    D = int(retardo * SR)
    x = (bus.l + bus.r) * 0.5
    l = np.zeros(n)
    r = np.zeros(n)
    for k in range(1, repeticiones + 1):
        x = paso_bajo(x, 3500)
        desp = k * D
        if desp >= n:
            break
        copia = np.zeros(n)
        copia[desp:] = x[: n - desp] * realim ** k
        if k % 2:
            r += copia
        else:
            l += copia
    bus.l += l * mezcla
    bus.r += r * mezcla


def reverb(l, r, rt60, mezcla, corte=4500, semillas=(11, 23)):
    """Reverberación por convolución con un impulso de ruido que decae."""
    n = len(l)
    largo = int(rt60 * 1.2 * SR)
    t = np.arange(largo) / SR
    tau = rt60 / np.log(1000)
    pre = int(0.018 * SR)
    nfft = 1 << int(np.ceil(np.log2(n + largo)))
    salida = []
    for canal, semilla in ((l, semillas[0]), (r, semillas[1])):
        ir = np.random.default_rng(semilla).standard_normal(largo) * np.exp(-t / tau)
        ir[:pre] = 0
        ir = paso_bajo(ir, corte)
        ir /= np.sqrt(np.sum(ir ** 2))
        mojado = np.fft.irfft(np.fft.rfft(canal, nfft) * np.fft.rfft(ir, nfft), nfft)[:n]
        salida.append(canal + mezcla * mojado)
    return salida


# ─── Nivel percibido y mezcla ───────────────────────────────────────────────

def ponderacion_k(f):
    """Aproximación de la ponderación K (ITU-R BS.1770, la de los LUFS):
    estante de +4 dB en agudos y paso alto suave en 38 Hz."""
    estante = 1 + (10 ** (4 / 20) - 1) * f ** 2 / (f ** 2 + 1500 ** 2)
    x = f / 38.0
    paso_alto_rlb = x ** 2 / np.sqrt((1 - x ** 2) ** 2 + (x / 0.5) ** 2 + 1e-12)
    return estante * paso_alto_rlb


def nivel(l, r, solo_activo=True):
    """Nivel percibido aproximado (RMS con ponderación K). Con solo_activo se
    mide únicamente donde hay sonido, para que una parte dispersa (hi-hats,
    campanas) no reciba una ganancia enorme por tener mucho silencio."""
    nfft = _nfft(len(l))
    H = ponderacion_k(np.fft.rfftfreq(nfft, 1 / SR))
    ys = [np.fft.irfft(np.fft.rfft(c, nfft) * H, nfft)[: len(l)] for c in (l, r)]
    potencia = (ys[0] ** 2 + ys[1] ** 2) / 2
    if solo_activo:
        bloque = int(0.05 * SR)
        n = len(potencia) // bloque
        bloques = potencia[: n * bloque].reshape(n, bloque).mean(axis=1)
        activos = bloques[bloques > bloques.max() * 1e-3]
        return np.sqrt(activos.mean()) + 1e-12
    return np.sqrt(potencia.mean()) + 1e-12


def mezclar(objetivos, referencia=0.1):
    """objetivos: [(bus, dB respecto a la referencia)]. Cada bus se lleva a su
    nivel percibido medido solo mientras suena. Los buses vacíos se saltan."""
    largo = len(objetivos[0][0].l)
    l = np.zeros(largo)
    r = np.zeros(largo)
    for bus, db in objetivos:
        if not bus.l.any():
            continue
        g = referencia * 10 ** (db / 20) / nivel(bus.l, bus.r)
        l += bus.l * g
        r += bus.r * g
    return l, r


def plegar_bucle(l, r, largo):
    """Bucle sin corte: lo que suena después de 'largo' muestras (colas de
    notas, eco y reverberación) se suma al principio."""
    l = l.copy()
    r = r.copy()
    cola = len(l) - largo
    for canal in (l, r):
        canal[:cola] += canal[largo:largo + cola]
    return l[:largo], r[:largo]


def normalizar_nivel(l, r, dbfs=-18.0, techo_dbfs=-1.0):
    """Lleva la pieza a un nivel percibido fijo (igual en todas las músicas,
    para que no salte el volumen al cambiar de una a otra). Si algún pico pasa
    del techo, se redondea suavemente en vez de recortarse."""
    g = 10 ** (dbfs / 20) / nivel(l, r, solo_activo=False)
    l, r = l * g, r * g
    techo = 10 ** (techo_dbfs / 20)
    for canal in (l, r):
        exceso = np.abs(canal) > 0.7 * techo
        canal[exceso] = np.sign(canal[exceso]) * (
            0.7 * techo + 0.3 * techo * np.tanh((np.abs(canal[exceso]) - 0.7 * techo) / (0.3 * techo)))
    return l, r


def normalizar_pico(x, dbfs):
    return x * (10 ** (dbfs / 20) / (np.abs(x).max() + 1e-12))


# ─── Guardar ────────────────────────────────────────────────────────────────

def guardar_wav(ruta, l, r=None):
    """WAV de 16 bits; mono si no se da r."""
    canales = [l] if r is None else [l, r]
    datos = np.empty(len(l) * len(canales), dtype=np.int16)
    for i, c in enumerate(canales):
        datos[i::len(canales)] = np.clip(c * 32767, -32768, 32767).astype(np.int16)
    with wave.open(str(ruta), "wb") as w:
        w.setnchannels(len(canales))
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(datos.tobytes())


def guardar_ogg(ruta, l, r):
    import soundfile as sf
    sf.write(str(ruta), np.stack([l, r], axis=1), SR, format="OGG", subtype="VORBIS")
