"""Comprueba que las 7 familias del juego, con sus respaldos, tienen todos los
caracteres del inventario.

Uso: python cobertura.py <inventario.json> <raíz_del_juego> [--sin-simbolos]

Por familia y estilo se mira cmap(base) ∪ cmap(Twemoji) ∪ cmap(Simbolos VW),
que es lo que consulta Godot con Font.has_char() sobre fonts/fuente_juego*.tres.
Las familias se leen de scripts/Global/tipografia.gd. Sale con 1 si falta algo.
--sin-simbolos quita Simbolos VW de la cuenta: sirve para ver que la prueba
detecta huecos.
"""
import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

from fontTools.ttLib import TTFont

TWEMOJI = "fonts/twemoji/twemoji.ttf"
SIMBOLOS = {"regular": "fonts/simbolos/SimbolosVW-Regular.ttf", "negrita": "fonts/simbolos/SimbolosVW-Bold.ttf"}

# Invisibles que no necesitan dibujo propio: los consume el modelado del emoji.
IGNORADOS = {0x200D, 0xFE0E, 0xFE0F, 0xFEFF}

PATRON_FAMILIA = re.compile(
    r'"(\w+)": \{[^}]*?"regular": "res://([^"]+)"[^}]*?"negrita": "res://([^"]+)"', re.S
)


def familias(raiz: Path) -> dict:
    """{id: {"regular": ruta, "negrita": ruta}} desde Tipografia.FAMILIAS."""
    codigo = (raiz / "scripts/Global/tipografia.gd").read_text(encoding="utf-8")
    halladas = {m.group(1): {"regular": m.group(2), "negrita": m.group(3)} for m in PATRON_FAMILIA.finditer(codigo)}
    if len(halladas) != 7:
        raise SystemExit(f"Se esperaban 7 familias en tipografia.gd y hay {len(halladas)}")
    return halladas


def cmap(raiz: Path, ruta: str) -> set:
    return set(TTFont(raiz / ruta, lazy=True).getBestCmap())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("inventario")
    ap.add_argument("raiz")
    ap.add_argument("--sin-simbolos", action="store_true")
    args = ap.parse_args()
    raiz = Path(args.raiz)
    inventario = json.loads(Path(args.inventario).read_text(encoding="utf-8"))
    codigos = sorted({
        ord(c) for c in inventario["caracteres"]
        if ord(c) not in IGNORADOS and unicodedata.category(c) not in ("Cc", "Cf")
    })
    emoji = cmap(raiz, TWEMOJI)
    simbolos = {estilo: (set() if args.sin_simbolos else cmap(raiz, ruta)) for estilo, ruta in SIMBOLOS.items()}
    ausencias = 0
    for id_familia, rutas in familias(raiz).items():
        for estilo, ruta in rutas.items():
            disponibles = cmap(raiz, ruta) | emoji | simbolos[estilo]
            faltan = [chr(cp) for cp in codigos if cp not in disponibles]
            ausencias += len(faltan)
            estado = "ok" if not faltan else "FALTAN " + " ".join(f"{c}(U+{ord(c):04X})" for c in faltan)
            print(f"{id_familia:13} {estilo:8} {estado}")
    print(f"{len(codigos)} caracteres comprobados, {ausencias} ausencias")
    return 1 if ausencias else 0


if __name__ == "__main__":
    sys.exit(main())
