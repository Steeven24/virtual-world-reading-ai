"""Genera «Simbolos VW», la fuente de respaldo para los símbolos que no son emoji.

Uso: python construir_simbolos.py <DejaVuSans.ttf> <DejaVuSans-Bold.ttf> <twemoji.ttf> <carpeta_salida>

Es un recorte de DejaVu Sans 2.37 (regular y negrita) SIN los códigos que ya
dibuja Twemoji, salvo ▶ ◀ ✖, que el juego usa como flechas y botón de cerrar.
Motivo: si la fuente de símbolos tiene un carácter que también es emoji
(⚠ ⚙ ✉ ✔), Godot elige su versión en blanco y negro aunque Twemoji vaya antes
en los respaldos y aunque el texto pida emoji con FE0F. Sin esos códigos, los
emojis salen en color y ✓ ✗ ➜ ➤ ✦ ▾ ○ ● ─ salen como texto con cualquier
familia (prueba en el export web del 18-oct-2026).

La licencia de Bitstream Vera, de la que deriva DejaVu, exige otro nombre para
las fuentes modificadas: por eso se llama «Simbolos VW».
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

# Flechas y cierre de la interfaz: se quedan como texto aunque Twemoji los tenga.
SIEMPRE_TEXTO = {0x25B6, 0x25C0, 0x2716}


def construir(origen: Path, emoji: set, salida: Path, estilo: str) -> int:
    fuente = TTFont(origen)
    propios = set(fuente.getBestCmap())
    quedan = sorted((propios - emoji) | (propios & SIEMPRE_TEXTO))
    opciones = subset.Options()
    opciones.layout_features = ["*"]
    opciones.name_IDs = ["*"]
    opciones.notdef_outline = True
    opciones.glyph_names = False
    recortador = subset.Subsetter(opciones)
    recortador.populate(unicodes=quedan)
    recortador.subset(fuente)
    for registro in fuente["name"].names:
        if registro.nameID in (1, 16):
            registro.string = "Simbolos VW"
        elif registro.nameID == 4:
            registro.string = f"Simbolos VW {estilo}"
        elif registro.nameID == 6:
            registro.string = f"SimbolosVW-{estilo}"
    fuente.save(salida)
    return len(quedan)


def main() -> None:
    regular, negrita, twemoji, carpeta = sys.argv[1:5]
    emoji = set(TTFont(twemoji, lazy=True).getBestCmap())
    carpeta = Path(carpeta)
    for origen, estilo in ((regular, "Regular"), (negrita, "Bold")):
        salida = carpeta / f"SimbolosVW-{estilo}.ttf"
        n = construir(Path(origen), emoji, salida, estilo)
        print(f"{salida.name}: {n} caracteres, {salida.stat().st_size} bytes")


if __name__ == "__main__":
    main()
