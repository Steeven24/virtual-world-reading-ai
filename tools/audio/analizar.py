"""Comprobaciones objetivas del audio generado (quien lo genera no lo escucha).

Uso:
    python analizar.py --efecto <archivos...>
    python analizar.py --musica <archivos...>

Imprime un informe por archivo y sale con código 1 si alguno falla.

Efecto: dura menos de 1,5 s, el pico está en -6 dBFS (±0,5) y no hay clics.
Música: dura entre 90 y 120 s, el nivel percibido (ponderación K) es -18 ± 1 dB,
el pico no pasa de -1 dBFS, la vuelta al principio no da un salto y no hay
clics.

Un clic es un salto entre muestras consecutivas mayor que 8 veces el
percentil 99,9 de los saltos del propio archivo.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

from sintesis import nivel

TECHO_MUSICA = 10 ** (-1 / 20)


def _leer(ruta):
    datos, sr = sf.read(str(ruta), always_2d=True)
    l = datos[:, 0]
    r = datos[:, 1] if datos.shape[1] > 1 else datos[:, 0]
    return l, r, sr


def _clics(mono):
    saltos = np.abs(np.diff(mono))
    umbral = 8 * np.percentile(saltos, 99.9)
    return int((saltos > umbral).sum()), saltos


def analizar_efecto(ruta):
    l, r, sr = _leer(ruta)
    duracion = len(l) / sr
    pico_db = 20 * np.log10(max(np.abs(l).max(), np.abs(r).max()) + 1e-12)
    clics, _ = _clics((l + r) / 2)
    problemas = []
    if duracion >= 1.5:
        problemas.append(f"dura {duracion:.2f} s")
    if not -6.5 <= pico_db <= -5.5:
        problemas.append(f"pico {pico_db:.1f} dBFS")
    if clics:
        problemas.append(f"{clics} clics")
    return f"{duracion:5.2f} s  pico {pico_db:5.1f} dBFS  clics {clics}", problemas


def analizar_musica(ruta):
    l, r, sr = _leer(ruta)
    duracion = len(l) / sr
    nivel_db = 20 * np.log10(nivel(l, r, solo_activo=False))
    pico = max(np.abs(l).max(), np.abs(r).max())
    clics, saltos = _clics((l + r) / 2)
    p99 = np.percentile(saltos, 99)
    costura = max(abs(l[0] - l[-1]), abs(r[0] - r[-1]))
    problemas = []
    if not 90 <= duracion <= 120:
        problemas.append(f"dura {duracion:.1f} s")
    if not -19 <= nivel_db <= -17:
        problemas.append(f"nivel {nivel_db:.1f} dB")
    if pico > TECHO_MUSICA + 1e-4:
        problemas.append(f"pico {20 * np.log10(pico):.2f} dBFS")
    if costura >= p99:
        problemas.append(f"costura {costura:.4f} (p99 {p99:.4f})")
    if clics:
        problemas.append(f"{clics} clics")
    informe = (f"{duracion:6.1f} s  nivel {nivel_db:6.1f} dB  pico {20 * np.log10(pico):5.1f} dBFS  "
               f"costura {costura:.4f}/{p99:.4f}  clics {clics}")
    return informe, problemas


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    tipo = ap.add_mutually_exclusive_group(required=True)
    tipo.add_argument("--efecto", action="store_true")
    tipo.add_argument("--musica", action="store_true")
    ap.add_argument("archivos", nargs="+")
    args = ap.parse_args(argv)

    fallos = 0
    for archivo in args.archivos:
        ruta = Path(archivo)
        if not ruta.exists():
            print(f"FALLO {ruta.name}: no existe")
            fallos += 1
            continue
        informe, problemas = (analizar_efecto if args.efecto else analizar_musica)(ruta)
        if problemas:
            fallos += 1
            print(f"FALLO {ruta.name}: {informe}  -> {', '.join(problemas)}")
        else:
            print(f"OK    {ruta.name}: {informe}")
    print(f"{len(args.archivos) - fallos}/{len(args.archivos)} correctos")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
