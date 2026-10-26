"""Convierte episodios de Pepper&Carrot en los assets que empaqueta el juego.

Se ejecuta a mano (no en el arranque). Lee una carpeta de trabajo FUERA del
repositorio y escribe en assets/Comics/ las páginas reescaladas (.webp) y el
catálogo con la posición y el texto de cada bocadillo. Ver README.md.
"""
import argparse
import json
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

RAIZ_JUEGO = Path(__file__).resolve().parents[2]
DESTINO_POR_DEFECTO = RAIZ_JUEGO / "assets" / "Comics"
ANCHO_POR_DEFECTO = 1100
CALIDAD_WEBP = 90
EXTENSIONES_PAGINA = {".png", ".jpg", ".jpeg"}

ATRIBUCION = {
    "autor": "David Revoy",
    "titulo": "Pimienta y Zanahoria",
    "licencia": "CC BY 4.0",
    "enlace": "https://www.peppercarrot.com/es/",
}

# Si el SVG no indica tamaño de letra, se supone este (unidades del lienzo).
TAMANO_LETRA_POR_DEFECTO = 20.0
ANCHO_CARACTER = 0.55  # ancho medio de un carácter, en múltiplos del tamaño de letra
INTERLINEADO = 1.25


def _sin_espacio_de_nombres(etiqueta: str) -> str:
    return etiqueta.rsplit("}", 1)[-1]


def _numero(valor, por_defecto: float) -> float:
    if valor is None:
        return por_defecto
    # Puede venir con unidades ("12.5px") o como lista ("10 20 30").
    coincidencia = re.match(r"\s*(-?\d+(?:\.\d+)?)", valor)
    return float(coincidencia.group(1)) if coincidencia else por_defecto


def _tamano_letra(elemento) -> float:
    coincidencia = re.search(r"font-size\s*:\s*(\d+(?:\.\d+)?)", elemento.get("style", ""))
    if coincidencia:
        return float(coincidencia.group(1))
    return _numero(elemento.get("font-size"), TAMANO_LETRA_POR_DEFECTO)


def _lienzo(raiz) -> tuple[float, float]:
    vista = raiz.get("viewBox")
    if vista:
        partes = [float(p) for p in re.split(r"[\s,]+", vista.strip())]
        if len(partes) == 4 and partes[2] > 0 and partes[3] > 0:
            return partes[2], partes[3]
    ancho, alto = _numero(raiz.get("width"), 0), _numero(raiz.get("height"), 0)
    if ancho <= 0 or alto <= 0:
        raise ValueError("El SVG no tiene viewBox ni width/height válidos")
    return ancho, alto


def _limitar(valor: float) -> float:
    return round(min(1.0, max(0.0, valor)), 5)


IDENTIDAD = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)  # matriz afín (a, b, c, d, e, f) de SVG


def _componer(padre, hijo):
    """Matriz que aplica primero `hijo` y luego `padre` (como la cascada de SVG)."""
    a1, b1, c1, d1, e1, f1 = padre
    a2, b2, c2, d2, e2, f2 = hijo
    return (
        a1 * a2 + c1 * b2, b1 * a2 + d1 * b2,
        a1 * c2 + c1 * d2, b1 * c2 + d1 * d2,
        a1 * e2 + c1 * f2 + e1, b1 * e2 + d1 * f2 + f1,
    )


def _matriz(transform):
    """Convierte el atributo `transform` de SVG en una matriz afín."""
    resultado = IDENTIDAD
    for nombre, argumentos in re.findall(r"(\w+)\s*\(([^)]*)\)", transform or ""):
        v = [float(n) for n in re.findall(r"-?\d*\.?\d+(?:[eE][-+]?\d+)?", argumentos)]
        if nombre == "matrix" and len(v) == 6:
            m = tuple(v)
        elif nombre == "translate" and v:
            m = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0.0)
        elif nombre == "scale" and v:
            m = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif nombre == "rotate" and v:
            c, s = math.cos(math.radians(v[0])), math.sin(math.radians(v[0]))
            m = (c, s, -s, c, 0, 0)
            if len(v) == 3:
                m = _componer(_componer((1, 0, 0, 1, v[1], v[2]), m), (1, 0, 0, 1, -v[1], -v[2]))
        elif nombre == "skewX" and v:
            m = (1, 0, math.tan(math.radians(v[0])), 1, 0, 0)
        elif nombre == "skewY" and v:
            m = (1, math.tan(math.radians(v[0])), 0, 1, 0, 0)
        else:
            continue
        resultado = _componer(resultado, m)
    return resultado


def _caja_transformada(caja, m):
    """Caja envolvente (x0, y0, x1, y1) de `caja` tras aplicar la matriz `m`."""
    x0, y0, x1, y1 = caja
    a, b, c, d, e, f = m
    puntos = [(a * x + c * y + e, b * x + d * y + f) for x in (x0, x1) for y in (y0, y1)]
    xs, ys = [p[0] for p in puntos], [p[1] for p in puntos]
    return min(xs), min(ys), max(xs), max(ys)


def _oculto(elemento) -> bool:
    en_estilo = re.search(r"display\s*:\s*none", elemento.get("style", ""))
    return bool(en_estilo) or elemento.get("display") == "none"


def _anclaje(*elementos) -> str:
    """text-anchor efectivo (start, middle o end); el primer elemento que lo fije gana."""
    for e in elementos:
        coincidencia = re.search(r"text-anchor\s*:\s*(\w+)", e.get("style", ""))
        valor = coincidencia.group(1) if coincidencia else e.get("text-anchor")
        if valor:
            return valor
    return "start"


def _caja_de_texto(texto):
    """Caja local (x0, y0, x1, y1) y líneas de un <text>; None si no tiene texto."""
    lineas = []  # (cadena, x, y, anclaje)
    hijos = [h for h in texto if _sin_espacio_de_nombres(h.tag) == "tspan"]
    for hijo in hijos:
        cadena = "".join(hijo.itertext()).strip()
        if cadena:
            lineas.append((
                cadena,
                _numero(hijo.get("x"), _numero(texto.get("x"), 0)),
                _numero(hijo.get("y"), _numero(texto.get("y"), 0)),
                _anclaje(hijo, texto),
            ))
    if not hijos:
        cadena = "".join(texto.itertext()).strip()
        if cadena:
            lineas.append((cadena, _numero(texto.get("x"), 0),
                           _numero(texto.get("y"), 0), _anclaje(texto)))
    if not lineas:
        return None
    tamano = _tamano_letra(texto)
    izquierdas, derechas = [], []
    for cadena, x, _, anclaje in lineas:
        ancho = len(cadena) * tamano * ANCHO_CARACTER
        # x es el anclaje: el borde izquierdo depende de text-anchor.
        izquierda = x - ancho / 2 if anclaje == "middle" else x - ancho if anclaje == "end" else x
        izquierdas.append(izquierda)
        derechas.append(izquierda + ancho)
    ys = [y for _, _, y, _ in lineas]
    y0 = min(ys) - tamano  # la y del SVG es la línea base
    caja = (min(izquierdas), y0, max(derechas), y0 + (max(ys) - min(ys)) + tamano * INTERLINEADO)
    return caja, [c for c, _, _, _ in lineas]


def _caja_de_flujo(flujo):
    """Caja local de un <flowRoot> (la unión de sus rectángulos de región) y sus párrafos.

    Inkscape 0.91 guarda los textos con flujo: la región da el tamaño real del
    globo y cada <flowPara> es una línea.
    """
    rectangulos = []
    for rect in flujo.iter():
        if _sin_espacio_de_nombres(rect.tag) == "rect":
            x, y = _numero(rect.get("x"), 0), _numero(rect.get("y"), 0)
            rectangulos.append((x, y, x + _numero(rect.get("width"), 0), y + _numero(rect.get("height"), 0)))
    parrafos = [
        "".join(p.itertext()).strip()
        for p in flujo.iter() if _sin_espacio_de_nombres(p.tag) == "flowPara"
    ]
    parrafos = [p for p in parrafos if p]
    if not rectangulos or not parrafos:
        return None
    caja = (min(r[0] for r in rectangulos), min(r[1] for r in rectangulos),
            max(r[2] for r in rectangulos), max(r[3] for r in rectangulos))
    return caja, parrafos


def _recorrer(elemento, matriz, ancho_lienzo, alto_lienzo, globos):
    for hijo in elemento:
        if _oculto(hijo):
            continue
        etiqueta = _sin_espacio_de_nombres(hijo.tag)
        propia = _componer(matriz, _matriz(hijo.get("transform")))
        if etiqueta == "text":
            encontrado = _caja_de_texto(hijo)
        elif etiqueta == "flowRoot":
            encontrado = _caja_de_flujo(hijo)
        else:
            _recorrer(hijo, propia, ancho_lienzo, alto_lienzo, globos)
            continue
        if encontrado is None:
            continue
        caja, lineas = encontrado
        x0, y0, x1, y1 = _caja_transformada(caja, propia)
        x, y = _limitar(x0 / ancho_lienzo), _limitar(y0 / alto_lienzo)
        globos.append({
            "x": x,
            "y": y,
            "ancho": _limitar(min((x1 - x0) / ancho_lienzo, 1.0 - x)),
            "alto": _limitar(min((y1 - y0) / alto_lienzo, 1.0 - y)),
            "texto": "\n".join(lineas),
        })


def extraer_bocadillos(svg: Path) -> list[dict]:
    """Devuelve un bocadillo por cada <text> o <flowRoot> del SVG, con coordenadas 0-1.

    Cada <tspan> (o <flowPara>) es una línea del mismo bocadillo (se une con
    salto de línea). Se aplican los `transform` de los grupos, se respeta
    `text-anchor` (los SVG de Inkscape suelen centrar) y se ignora lo oculto.
    En <text> la caja se estima a partir del tamaño de letra (el SVG solo da el
    punto de anclaje); en <flowRoot> es el rectángulo de su región.
    """
    raiz = ET.parse(svg).getroot()
    ancho_lienzo, alto_lienzo = _lienzo(raiz)
    globos = []
    _recorrer(raiz, IDENTIDAD, ancho_lienzo, alto_lienzo, globos)
    return globos


def construir_episodio(origen: Path, destino: Path, ancho_px: int) -> dict:
    """Reescala las páginas de `origen` a `destino` y devuelve su manifiesto.

    Cada página `NN.png|jpg` puede traer un `NN.svg` con sus bocadillos y la
    carpeta un `titulo.txt`. Los nombres de página van relativos a `destino`.
    """
    origen, destino = Path(origen), Path(destino)
    paginas_origen = sorted(
        p for p in origen.iterdir() if p.suffix.lower() in EXTENSIONES_PAGINA
    )
    if not paginas_origen:
        raise FileNotFoundError(f"No hay páginas (png/jpg) en {origen}")
    destino.mkdir(parents=True, exist_ok=True)
    paginas, bocadillos = [], []
    for pagina in paginas_origen:
        with Image.open(pagina) as imagen:
            alto_px = round(imagen.height * ancho_px / imagen.width)
            reescalada = imagen.convert("RGB").resize((ancho_px, alto_px), Image.LANCZOS)
        nombre = pagina.stem + ".webp"
        reescalada.save(destino / nombre, "WEBP", quality=CALIDAD_WEBP)
        paginas.append(nombre)
        svg = pagina.with_suffix(".svg")
        bocadillos.append(extraer_bocadillos(svg) if svg.exists() else [])
    archivo_titulo = origen / "titulo.txt"
    titulo = (
        archivo_titulo.read_text(encoding="utf-8").strip()
        if archivo_titulo.exists()
        else origen.name
    )
    return {"titulo": titulo, "paginas": paginas, "bocadillos": bocadillos}


def main(argv=None) -> None:
    analizador = argparse.ArgumentParser(description=__doc__)
    analizador.add_argument("--trabajo", type=Path, required=True,
                            help="carpeta de trabajo (fuera del repositorio) con una subcarpeta por episodio")
    analizador.add_argument("--destino", type=Path, default=DESTINO_POR_DEFECTO,
                            help="carpeta de salida (por defecto assets/Comics del juego)")
    analizador.add_argument("--ancho", type=int, default=ANCHO_POR_DEFECTO,
                            help="ancho en píxeles de las páginas reescaladas")
    args = analizador.parse_args(argv)

    carpetas = sorted(c for c in args.trabajo.iterdir() if c.is_dir())
    if not carpetas:
        raise SystemExit(f"No hay carpetas de episodios en {args.trabajo}")
    episodios = []
    for carpeta in carpetas:
        id_episodio = carpeta.name
        manifiesto = construir_episodio(carpeta, args.destino / id_episodio, args.ancho)
        episodios.append({
            "id": id_episodio,
            "titulo": manifiesto["titulo"],
            "paginas": [f"{id_episodio}/{p}" for p in manifiesto["paginas"]],
            "bocadillos": manifiesto["bocadillos"],
        })
        print(f"{id_episodio}: {len(manifiesto['paginas'])} páginas")
    catalogo = {"atribucion": ATRIBUCION, "episodios": episodios}
    args.destino.mkdir(parents=True, exist_ok=True)
    (args.destino / "catalogo.json").write_text(
        json.dumps(catalogo, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Catálogo escrito en {args.destino / 'catalogo.json'}")


if __name__ == "__main__":
    main()
