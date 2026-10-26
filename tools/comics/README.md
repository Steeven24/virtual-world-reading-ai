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

### Cómo se adaptó el material de los episodios 1-10

Las fuentes por episodio viven en
`https://www.peppercarrot.com/0_sources/epNN_Nombre/`. Para cada episodio:

- Portada real: `low-res/Pepper-and-Carrot_by-David-Revoy_ENN.jpg` (1100x765,
  sin texto). Se copia como `00_portada.jpg` y queda de primera página, sin
  bocadillos (el título va en `titulo`).
- Ilustración sin texto: `lang/gfx_Pepper-and-Carrot_by-David-Revoy_ENNPxx.png`.
  OJO: no todo `Pxx` es una página. `P00` es la cabecera con el título (tira de
  265 px, casi en blanco) y `ep01` P04 un pie de 20 px; el script las descarta
  solo (ver abajo).
- Bocadillos en español: `lang/es/ENNPxx.svg`. Una página sin SVG (por
  ejemplo `ep04` P05) queda sin bocadillos.
- Se copian a `trabajo/epNN/xx.png` y `xx.svg` (el número de página es el de
  `Pxx`) y se escribe `titulo.txt` con el título español, que sale del texto
  de la portada `P00` sin el prefijo «Episodio N:».

Es un paso de un solo uso, por eso no tiene script propio. Los SVG de Inkscape
0.91 guardan casi todo el texto como `<flowRoot>` (la región da el globo) y
con `text-anchor:middle` y `transform` en los grupos; el extractor lo tiene en
cuenta (ver sus pruebas). Las cajas de los efectos de sonido inclinados son la
envolvente del rectángulo girado, así que pueden salir más grandes que la
palabra.

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

## Qué piezas se descartan

El script no copia todo lo que hay en la carpeta: descarta una pieza si es una
tira (alto < 0,3 x ancho) con al menos un 70 % de blanco (cabeceras y pies), o
si es casi blanca (97 %) y su SVG no trae texto. Una tira con ilustración (una
viñeta de `ep04`) y las páginas de créditos (casi blancas, pero con los
nombres como texto en el SVG) se conservan. Las piezas no tienen por qué ser
verticales: hay páginas de 1401 px, créditos de 816-991 px y viñetas sueltas.
Cada descarte se imprime al ejecutar.

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
