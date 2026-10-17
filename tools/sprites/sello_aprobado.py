"""Genera el sello «✓ Aprobado» de las estaciones del lobby.

Uso: python sello_aprobado.py <salida.png>

Mismo estilo que el candado (assets/Scenery/Padlock/padlock.png, 147x181 con
píxel grueso de 7 px): se dibuja en una rejilla de 21x21 celdas y se escala x7
sin suavizado, para que en el juego ocupe lo mismo que el candado.
"""
import math
import sys

from PIL import Image

CELDAS = 21
ESCALA = 7
CENTRO = 10
RADIO = 10.4

RELLENO = (0x3F, 0x9E, 0x4D, 255)
CONTORNO = (0x1F, 0x3D, 0x24, 255)
BRILLO = (0x6C, 0xC0, 0x70, 255)
MARCA = (255, 255, 255, 255)

# Trazo de la marca de verificación, celda a celda: bajada corta y subida larga.
MARCA_TRAZO = [(5, 10), (6, 11), (7, 12), (8, 13), (9, 12), (10, 11), (11, 10),
               (12, 9), (13, 8), (14, 7), (15, 6)]


def dibujar() -> Image.Image:
    img = Image.new("RGBA", (CELDAS, CELDAS), (0, 0, 0, 0))
    for y in range(CELDAS):
        for x in range(CELDAS):
            d = math.hypot(x - CENTRO, y - CENTRO)
            if d > RADIO:
                continue
            if d > RADIO - 1.0:
                img.putpixel((x, y), CONTORNO)
            elif 6.5 <= d <= 8.5 and x < CENTRO - 1 and y < CENTRO - 1:
                img.putpixel((x, y), BRILLO)
            else:
                img.putpixel((x, y), RELLENO)
    # Grosor de 2 celdas: cada punto del trazo y el de debajo.
    for x, y in MARCA_TRAZO:
        img.putpixel((x, y), MARCA)
        img.putpixel((x, y + 1), MARCA)
    return img.resize((CELDAS * ESCALA, CELDAS * ESCALA), Image.NEAREST)


if __name__ == "__main__":
    dibujar().save(sys.argv[1])
