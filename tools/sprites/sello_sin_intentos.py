"""Genera el sello «sin intentos» de las estaciones del lobby.

Uso: python sello_sin_intentos.py <salida.png>

Pareja de sello_aprobado.py: misma rejilla de 21x21 celdas escalada x7 sin
suavizado (ocupa lo mismo que el candado), en rojo y con una X blanca.
"""
import math
import sys

from PIL import Image

CELDAS = 21
ESCALA = 7
CENTRO = 10
RADIO = 10.4

RELLENO = (0xB8, 0x3B, 0x30, 255)
CONTORNO = (0x4A, 0x16, 0x12, 255)
BRILLO = (0xD9, 0x6A, 0x5E, 255)
MARCA = (255, 255, 255, 255)

# Las dos diagonales de la X, celda a celda.
DESDE, HASTA = 6, 14


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
    # Grosor de 2 celdas: cada punto de la diagonal y el de su derecha.
    for i in range(DESDE, HASTA + 1):
        for x, y in ((i, i), (DESDE + HASTA - i, i)):
            img.putpixel((x, y), MARCA)
            img.putpixel((min(x + 1, CELDAS - 1), y), MARCA)
    return img.resize((CELDAS * ESCALA, CELDAS * ESCALA), Image.NEAREST)


if __name__ == "__main__":
    dibujar().save(sys.argv[1])
