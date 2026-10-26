"""Convierte episodios de Pepper&Carrot en los assets que empaqueta el juego.

Se ejecuta a mano (no en el arranque). Lee una carpeta de trabajo FUERA del
repositorio y escribe en assets/Comics/ las páginas reescaladas (.webp) y el
catálogo con la posición y el texto de cada bocadillo. Ver README.md.
"""
import argparse
import json
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


def extraer_bocadillos(svg: Path) -> list[dict]:
    """Devuelve un bocadillo por cada <text> del SVG, con coordenadas 0-1.

    Cada <tspan> es una línea del mismo bocadillo (se une con salto de línea).
    La caja se estima a partir del tamaño de letra: el SVG solo da el punto
    de anclaje de cada línea, no el tamaño del globo.
    """
    raiz = ET.parse(svg).getroot()
    ancho_lienzo, alto_lienzo = _lienzo(raiz)
    globos = []
    for texto in raiz.iter():
        if _sin_espacio_de_nombres(texto.tag) != "text":
            continue
        lineas = []  # (cadena, x, y)
        hijos = [h for h in texto if _sin_espacio_de_nombres(h.tag) == "tspan"]
        for hijo in hijos:
            cadena = "".join(hijo.itertext()).strip()
            if cadena:
                lineas.append((
                    cadena,
                    _numero(hijo.get("x"), _numero(texto.get("x"), 0)),
                    _numero(hijo.get("y"), _numero(texto.get("y"), 0)),
                ))
        if not hijos:
            cadena = "".join(texto.itertext()).strip()
            if cadena:
                lineas.append((cadena, _numero(texto.get("x"), 0), _numero(texto.get("y"), 0)))
        if not lineas:
            continue
        tamano = _tamano_letra(texto)
        xs = [x for _, x, _ in lineas]
        ys = [y for _, _, y in lineas]
        x0, y0 = min(xs), min(ys) - tamano  # la y del SVG es la línea base
        ancho = max(len(c) for c, _, _ in lineas) * tamano * ANCHO_CARACTER
        alto = (max(ys) - min(ys)) + tamano * INTERLINEADO
        x, y = _limitar(x0 / ancho_lienzo), _limitar(y0 / alto_lienzo)
        globos.append({
            "x": x,
            "y": y,
            "ancho": _limitar(min(ancho / ancho_lienzo, 1.0 - x)),
            "alto": _limitar(min(alto / alto_lienzo, 1.0 - y)),
            "texto": "\n".join(c for c, _, _ in lineas),
        })
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
