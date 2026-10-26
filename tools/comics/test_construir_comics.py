"""Pruebas del pipeline de episodios de Pepper&Carrot."""
import json
import sys
from pathlib import Path

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from construir_comics import construir_episodio, extraer_bocadillos, main  # noqa: E402

SVG_DE_MUESTRA = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1400">
  <text x="100" y="200" style="font-size:40px"><tspan x="100" y="200">¡Pimienta!</tspan></text>
  <text x="500" y="700" style="font-size:40px"><tspan x="500" y="700">Ya voy…</tspan></text>
</svg>"""

SVG_DOS_TSPAN = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1400">
  <text x="100" y="200" style="font-size:40px">
    <tspan x="100" y="200">¡Pimienta,</tspan>
    <tspan x="100" y="250">la poción!</tspan>
  </text>
</svg>"""


def _escribir_pagina(ruta: Path) -> None:
    Image.new("RGB", (2000, 2800), (200, 120, 40)).save(ruta)


@pytest.fixture
def origen_de_muestra(tmp_path):
    origen = tmp_path / "origen" / "ep01"
    origen.mkdir(parents=True)
    for n in ("01", "02"):
        _escribir_pagina(origen / f"{n}.png")
    (origen / "01.svg").write_text(SVG_DE_MUESTRA, encoding="utf-8")
    (origen / "02.svg").write_text(SVG_DOS_TSPAN, encoding="utf-8")
    (origen / "titulo.txt").write_text("La poción de talento\n", encoding="utf-8")
    return origen


def test_extraer_bocadillos_lee_texto_y_caja(tmp_path):
    svg = tmp_path / "bocadillos.svg"
    svg.write_text(SVG_DE_MUESTRA, encoding="utf-8")
    globos = extraer_bocadillos(svg)
    assert [g["texto"] for g in globos] == ["¡Pimienta!", "Ya voy…"]
    assert 0 <= globos[0]["x"] <= 1 and 0 <= globos[0]["y"] <= 1
    assert globos[0]["x"] == pytest.approx(0.1)
    assert 0 < globos[0]["ancho"] <= 1 and 0 < globos[0]["alto"] <= 1


def test_extraer_bocadillos_junta_varias_lineas_de_un_globo(tmp_path):
    svg = tmp_path / "b.svg"
    svg.write_text(SVG_DOS_TSPAN, encoding="utf-8")
    globos = extraer_bocadillos(svg)
    assert len(globos) == 1
    assert globos[0]["texto"] == "¡Pimienta,\nla poción!"


def test_construir_episodio_reescala_y_devuelve_manifiesto(tmp_path, origen_de_muestra):
    destino = tmp_path / "salida"
    manifiesto = construir_episodio(origen_de_muestra, destino, ancho_px=1100)
    assert manifiesto["paginas"] == ["01.webp", "02.webp"]
    imagen = Image.open(destino / "01.webp")
    assert imagen.width == 1100 and imagen.height == 1540
    assert len(manifiesto["bocadillos"]) == 2
    assert len(manifiesto["bocadillos"][0]) == 2
    assert manifiesto["titulo"] == "La poción de talento"


def test_pagina_sin_svg_tiene_lista_vacia(tmp_path, origen_de_muestra):
    (origen_de_muestra / "02.svg").unlink()
    manifiesto = construir_episodio(origen_de_muestra, tmp_path / "s", ancho_px=500)
    assert manifiesto["bocadillos"][1] == []


def test_main_escribe_catalogo_con_rutas_prefijadas(tmp_path, origen_de_muestra):
    trabajo = origen_de_muestra.parent
    destino = tmp_path / "assets"
    main(["--trabajo", str(trabajo), "--destino", str(destino), "--ancho", "600"])
    catalogo = json.loads((destino / "catalogo.json").read_text(encoding="utf-8"))
    assert catalogo["atribucion"]["autor"] == "David Revoy"
    assert catalogo["atribucion"]["titulo"] == "Pimienta y Zanahoria"
    assert catalogo["atribucion"]["licencia"] == "CC BY 4.0"
    assert catalogo["atribucion"]["enlace"] == "https://www.peppercarrot.com/es/"
    ep = catalogo["episodios"][0]
    assert ep["id"] == "ep01"
    assert ep["paginas"] == ["ep01/01.webp", "ep01/02.webp"]
    assert (destino / "ep01" / "01.webp").exists()
