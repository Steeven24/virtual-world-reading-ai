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


def _globos_de(tmp_path, contenido):
    svg = tmp_path / "b.svg"
    svg.write_text(contenido, encoding="utf-8")
    return extraer_bocadillos(svg)


def test_text_anchor_middle_centra_la_caja_sobre_el_anclaje(tmp_path):
    # 10 caracteres a 40 px => 220 de ancho estimado; centrado en x=500 => borde en 390.
    globos = _globos_de(tmp_path, """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1400">
      <text x="500" y="200" style="font-size:40px;text-anchor:middle"><tspan x="500" y="200">0123456789</tspan></text>
    </svg>""")
    assert globos[0]["x"] == pytest.approx(0.39)
    assert globos[0]["ancho"] == pytest.approx(0.22)


def test_text_anchor_end_termina_en_el_anclaje(tmp_path):
    globos = _globos_de(tmp_path, """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1400">
      <text x="500" y="200" style="font-size:40px"><tspan x="500" y="200" style="text-anchor:end">0123456789</tspan></text>
    </svg>""")
    assert globos[0]["x"] == pytest.approx(0.28)


def test_aplica_el_transform_de_los_grupos(tmp_path):
    globos = _globos_de(tmp_path, """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1400">
      <g transform="translate(100,50)"><g transform="scale(2)">
        <text x="100" y="100" style="font-size:20px"><tspan x="100" y="100">0123456789</tspan></text>
      </g></g>
    </svg>""")
    # x local 100 -> 100*2+100 = 300; y local 80 (100-20) -> 80*2+50 = 210.
    assert globos[0]["x"] == pytest.approx(0.3)
    assert globos[0]["y"] == pytest.approx(210 / 1400, abs=1e-4)
    assert globos[0]["ancho"] == pytest.approx(2 * 10 * 20 * 0.55 / 1000)


def test_flowroot_usa_la_region_y_su_transform(tmp_path):
    globos = _globos_de(tmp_path, """<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg" width="1000" height="1400">
      <g><flowRoot transform="translate(100,200)">
        <flowRegion><rect x="50" y="20" width="300" height="100"/></flowRegion>
        <flowPara>¡Pimienta,</flowPara><flowPara>la poción!</flowPara>
      </flowRoot></g>
    </svg>""")
    assert len(globos) == 1
    assert globos[0]["texto"] == "¡Pimienta,\nla poción!"
    assert globos[0]["x"] == pytest.approx(0.15)
    assert globos[0]["y"] == pytest.approx(220 / 1400, abs=1e-4)
    assert globos[0]["ancho"] == pytest.approx(0.3)
    assert globos[0]["alto"] == pytest.approx(100 / 1400, abs=1e-4)


def test_ignora_capas_ocultas_y_flowroot_vacio(tmp_path):
    globos = _globos_de(tmp_path, """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1400">
      <g style="display:none"><text x="10" y="50"><tspan x="10" y="50">oculto</tspan></text></g>
      <flowRoot><flowRegion><rect x="0" y="0" width="10" height="10"/></flowRegion><flowPara/></flowRoot>
      <text x="10" y="50"><tspan x="10" y="50">visible</tspan></text>
    </svg>""")
    assert [g["texto"] for g in globos] == ["visible"]


def _origen_con(tmp_path, imagenes, svgs=()):
    origen = tmp_path / "o" / "ep01"
    origen.mkdir(parents=True)
    for nombre, imagen in imagenes.items():
        imagen.save(origen / nombre)
    for nombre in svgs:
        (origen / nombre).write_text(SVG_DE_MUESTRA, encoding="utf-8")
    return origen


def test_descarta_tiras_en_blanco_aunque_tengan_texto(tmp_path):
    # Cabecera con el título: 992x265, blanca; el SVG trae el texto del título.
    origen = _origen_con(tmp_path, {
        "00.png": Image.new("RGB", (992, 265), "white"),
        "01.png": Image.new("RGB", (992, 1401), (200, 120, 40)),
        "02.png": Image.new("RGB", (992, 20), "white"),  # pie
    }, svgs=("00.svg",))
    manifiesto = construir_episodio(origen, tmp_path / "s", ancho_px=500)
    assert manifiesto["paginas"] == ["01.webp"]
    assert not (tmp_path / "s" / "00.webp").exists()
    assert len(manifiesto["bocadillos"]) == 1


def test_conserva_una_tira_con_ilustracion(tmp_path):
    # Viñeta apaisada (alto < 0,3 x ancho) pero con dibujo: no es cabecera.
    origen = _origen_con(tmp_path, {"01.png": Image.new("RGB", (992, 259), (30, 30, 60))})
    assert construir_episodio(origen, tmp_path / "s", ancho_px=500)["paginas"] == ["01.webp"]


def test_pagina_en_blanco_solo_se_conserva_si_trae_texto(tmp_path):
    # Créditos: la imagen es casi blanca y los nombres van como texto en el SVG.
    origen = _origen_con(tmp_path, {
        "01.png": Image.new("RGB", (992, 991), "white"),
        "02.png": Image.new("RGB", (992, 1401), "white"),  # vacía y sin texto
    }, svgs=("01.svg",))
    assert construir_episodio(origen, tmp_path / "s", ancho_px=500)["paginas"] == ["01.webp"]


def test_transparencia_se_compone_sobre_blanco(tmp_path):
    origen = _origen_con(tmp_path, {
        "01.png": Image.new("RGBA", (992, 1401), (0, 0, 0, 0)),  # transparente = blanca
        "02.png": Image.new("RGB", (992, 1401), (200, 120, 40)),
    })
    assert construir_episodio(origen, tmp_path / "s", ancho_px=500)["paginas"] == ["02.webp"]


def test_error_si_todo_se_descarta(tmp_path):
    origen = _origen_con(tmp_path, {"00.png": Image.new("RGB", (992, 265), "white")})
    with pytest.raises(FileNotFoundError):
        construir_episodio(origen, tmp_path / "s", ancho_px=500)
