"""Inventario de los caracteres no ASCII que el juego puede llegar a mostrar.

Uso: python inventario.py --salida inventario.json <carpetas o archivos...>

Recorre .gd, .tscn, .tres, .json, .py, .txt y .sql (los JSON se leen como datos,
para ver el texto real aunque venga con escapes \\uXXXX) y apunta:
  - caracteres: cada carácter no ASCII suelto;
  - secuencias: emojis de varios códigos (selector FE0F, tecla 20E3, tonos de
    piel, uniones ZWJ, banderas), que hay que comprobar dibujadas juntas.
Lo usan cobertura.py y la prueba visual de emojis en la web.
"""
import argparse
import json
import os
import sys
from pathlib import Path

EXTENSIONES = {".gd", ".tscn", ".tres", ".json", ".py", ".txt", ".sql"}
CARPETAS_IGNORADAS = {".git", ".godot", "node_modules", "__pycache__", "dist", "build", "addons", ".superpowers"}

ZWJ = 0x200D
SELECTORES = {0xFE0E, 0xFE0F}
TECLA = 0x20E3


def es_tono(cp: int) -> bool:
    return 0x1F3FB <= cp <= 0x1F3FF


def es_bandera(cp: int) -> bool:
    return 0x1F1E6 <= cp <= 0x1F1FF


def es_etiqueta(cp: int) -> bool:
    return 0xE0020 <= cp <= 0xE007F


def secuencias_de(texto: str) -> set:
    """Secuencias de emoji de más de un código dentro de un texto."""
    halladas = set()
    i, n = 0, len(texto)
    while i < n:
        cp = ord(texto[i])
        j = i + 1
        if es_bandera(cp) and j < n and es_bandera(ord(texto[j])):
            halladas.add(texto[i:j + 1])
            i = j + 1
            continue
        while j < n:
            sig = ord(texto[j])
            if sig in SELECTORES or sig == TECLA or es_tono(sig) or es_etiqueta(sig):
                j += 1
            elif sig == ZWJ and j + 1 < n and ord(texto[j + 1]) > 0x2000:
                j += 2
            else:
                break
        es_tecla = texto[i] in "0123456789#*" and TECLA in map(ord, texto[i:j])
        if j - i > 1 and (cp > 0x2000 or es_tecla):
            halladas.add(texto[i:j])
        i = j if j > i + 1 else i + 1
    return halladas


def textos_de_json(dato):
    if isinstance(dato, str):
        yield dato
    elif isinstance(dato, dict):
        for clave, valor in dato.items():
            yield from textos_de_json(clave)
            yield from textos_de_json(valor)
    elif isinstance(dato, list):
        for valor in dato:
            yield from textos_de_json(valor)


def textos_de(ruta: Path):
    try:
        crudo = ruta.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return
    if ruta.suffix == ".json":
        try:
            yield from textos_de_json(json.loads(crudo))
            return
        except json.JSONDecodeError:
            pass
    yield crudo


def archivos(rutas):
    for r in rutas:
        r = Path(r)
        if r.is_file():
            yield r
            continue
        for carpeta, subcarpetas, nombres in os.walk(r):
            subcarpetas[:] = [d for d in subcarpetas if d not in CARPETAS_IGNORADAS and not d.startswith(".venv")]
            for nombre in nombres:
                if Path(nombre).suffix.lower() in EXTENSIONES:
                    yield Path(carpeta) / nombre


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--salida", required=True)
    ap.add_argument("rutas", nargs="+")
    args = ap.parse_args()
    caracteres, secuencias = set(), set()
    leidos = 0
    for ruta in archivos(args.rutas):
        leidos += 1
        for texto in textos_de(ruta):
            caracteres.update(c for c in texto if ord(c) > 127)
            secuencias.update(secuencias_de(texto))
    datos = {"caracteres": sorted(caracteres), "secuencias": sorted(secuencias)}
    Path(args.salida).write_text(json.dumps(datos, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{leidos} archivos: {len(caracteres)} caracteres no ASCII y {len(secuencias)} secuencias -> {args.salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
