# Pipeline de cómics (Pepper&Carrot)

`construir_comics.py` convierte episodios del webcómic **Pepper&Carrot**
(David Revoy, licencia CC BY 4.0) en los assets que empaqueta el juego:
páginas `.webp` reescaladas y `assets/Comics/catalogo.json` con la posición y
el texto de cada bocadillo. El texto va aparte de la imagen porque el juego lo
pinta con `Label` reales y así respeta las siete tipografías (incluida
OpenDyslexic). Se ejecuta a mano, no en el arranque del juego.

## De dónde se descarga el material

- Sitio: <https://www.peppercarrot.com/es/> (sección de descargas).
- Para cada episodio hacen falta las páginas en español (PNG o JPG) y el SVG
  de Inkscape con el texto traducido de cada página.

## Carpeta de trabajo que espera el script

Debe estar **fuera del repositorio** y tener una subcarpeta por episodio; el
nombre de la subcarpeta será el id (`ep01`, `ep02`, ...):

```
trabajo/
  ep01/
    titulo.txt     # opcional: título del episodio (si falta, se usa el id)
    01.png  01.svg # página y su SVG de bocadillos (el SVG es opcional)
    02.png  02.svg
```

Las páginas se ordenan por nombre. Una página sin SVG queda sin bocadillos.

## Uso

```
pip install pillow
python tools/comics/construir_comics.py --trabajo "D:/trabajo_comics" [--ancho 1100] [--destino assets/Comics]
python -m pytest tools/comics/test_construir_comics.py -v
```

## Qué se genera

- `assets/Comics/epNN/NN.webp`: páginas reescaladas al ancho indicado.
- `assets/Comics/catalogo.json`: bloque `atribucion` (autor, título, licencia
  y enlace) y la lista de episodios con `paginas` (rutas relativas a
  `assets/Comics`) y `bocadillos` (una lista por página).
- Las coordenadas de cada bocadillo (`x`, `y`, `ancho`, `alto`) son
  **relativas (0-1)** a la página, no píxeles. El tamaño de la caja es una
  estimación a partir del tamaño de letra, porque el SVG solo da el anclaje
  del texto.

## Por qué los originales no entran en el repositorio

Los originales de imprenta pesan decenas de megabytes por página y no hacen
falta en pantalla. En el repositorio solo entran las páginas ya reescaladas;
los originales se quedan en la carpeta de trabajo. Al usar el material hay que
mantener la atribución del catálogo (CC BY 4.0).
