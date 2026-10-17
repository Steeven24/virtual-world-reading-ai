## Fuente del texto de todo el juego, elegible desde el menú del lobby.
##
## Todo el juego apunta a dos FontVariation compartidos (fonts/fuente_juego.tres
## y fonts/fuente_juego_negrita.tres). Cambiar de familia es cambiarles la
## base_font: lo que ya está en pantalla se redibuja solo.
##
## Las familias no miden lo mismo al mismo tamaño (OpenDyslexic sale un 54 %
## más ancha que la fuente con la que se maquetó el juego), así que cada una
## lleva una escala que se aplica a los tamaños de letra de todos los
## controles. Un Control con la meta "sin_escala" se deja como está.
##
## Registrar como Autoload: Project Settings → Autoload → "Tipografia"
extends Node

## Emitida tras aplicar una familia.
signal familia_aplicada(id: String)

const FUENTE_REGULAR := "res://fonts/fuente_juego.tres"
const FUENTE_NEGRITA := "res://fonts/fuente_juego_negrita.tres"

## Orden en el que se ofrecen en el menú.
const ORDEN: Array[String] = ["adventor", "lexend", "atkinson", "opendyslexic", "andika", "literata", "pixeloid"]

## Las escalas salen de medir cada familia frente a Pixelify (la fuente con la
## que se maquetó el juego) con texto del juego: ancho ≤ 1,05 y alto de línea
## ≤ 1,12. Las variables (peso_*) usan un mismo archivo para las dos.
const FAMILIAS: Dictionary = {
	"adventor": {
		"nombre": "Adventor", "nota": "predeterminada", "escala": 1.0,
		"regular": "res://fonts/adventor/texgyreadventor-regular.otf",
		"negrita": "res://fonts/adventor/texgyreadventor-bold.otf",
	},
	"lexend": {
		"nombre": "Lexend", "nota": "lectura fluida", "escala": 1.0,
		"regular": "res://fonts/lexend/Lexend-Variable.ttf",
		"negrita": "res://fonts/lexend/Lexend-Variable.ttf",
		"peso_regular": 400, "peso_negrita": 700,
	},
	"atkinson": {
		"nombre": "Atkinson", "nota": "alta legibilidad", "escala": 1.0,
		"regular": "res://fonts/atkinson/AtkinsonHyperlegible-Regular.ttf",
		"negrita": "res://fonts/atkinson/AtkinsonHyperlegible-Bold.ttf",
	},
	"opendyslexic": {
		"nombre": "OpenDyslexic", "nota": "dislexia", "escala": 0.68,
		"regular": "res://fonts/opendyslexic/OpenDyslexic-Regular.otf",
		"negrita": "res://fonts/opendyslexic/OpenDyslexic-Bold.otf",
	},
	"andika": {
		"nombre": "Andika", "nota": "letra escolar", "escala": 0.84,
		"regular": "res://fonts/andika/Andika-Regular.ttf",
		"negrita": "res://fonts/andika/Andika-Bold.ttf",
	},
	"literata": {
		"nombre": "Literata", "nota": "estilo libro", "escala": 0.9,
		"regular": "res://fonts/literata/Literata-Variable.ttf",
		"negrita": "res://fonts/literata/Literata-Variable.ttf",
		"peso_regular": 400, "peso_negrita": 700,
	},
	"pixeloid": {
		"nombre": "Pixeloid", "nota": "estilo pixel", "escala": 0.95, "pixel": true,
		"regular": "res://fonts/pixeloid/PixeloidSans.ttf",
		"negrita": "res://fonts/pixeloid/PixeloidSans-Bold.ttf",
	},
}

## Tamaños de letra de un RichTextLabel; el resto de controles con texto usa
## solo "font_size".
const TAMANOS_RICH_TEXT: Array[String] = [
	"normal_font_size", "bold_font_size", "italics_font_size",
	"bold_italics_font_size", "mono_font_size",
]

var familia_actual: String = "adventor"

var _escala: float = 1.0
var _regular: FontVariation = preload(FUENTE_REGULAR)
var _negrita: FontVariation = preload(FUENTE_NEGRITA)

## Controles recién entrados al árbol, pendientes de escalar en diferido.
var _pendientes: Array[Control] = []


func _ready() -> void:
	get_tree().node_added.connect(_on_nodo_agregado)
	aplicar("adventor")


# ─── API pública ─────────────────────────────────────────────────────────────

## Cambia la fuente de todo el juego. Un id desconocido se trata como adventor.
func aplicar(id: String) -> void:
	if not FAMILIAS.has(id):
		id = "adventor"
	var datos: Dictionary = FAMILIAS[id]
	_regular.base_font = _cargar(datos["regular"], datos)
	_negrita.base_font = _cargar(datos["negrita"], datos)
	if datos.has("peso_regular"):
		_regular.variation_opentype = {"wght": datos["peso_regular"]}
		_negrita.variation_opentype = {"wght": datos["peso_negrita"]}
	else:
		_regular.variation_opentype = {}
		_negrita.variation_opentype = {}
	familia_actual = id
	_escala = float(datos["escala"])
	_reescalar_arbol(get_tree().root)
	familia_aplicada.emit(id)


## Escala de una familia, o la de la actual si id va vacío.
func escala(id: String = "") -> float:
	if id.is_empty():
		return _escala
	return float(FAMILIAS.get(id, FAMILIAS["adventor"])["escala"])


## Tamaño escalado para los que no pasan por overrides (BBCode [font_size]).
func tam(base: int) -> int:
	return maxi(1, roundi(base * _escala))


## Fuente propia de una familia, sin pasar por las compartidas. La usa el
## selector del menú para escribir cada nombre con su fuente.
func fuente_de(id: String, negrita: bool = false) -> Font:
	var datos: Dictionary = FAMILIAS.get(id, FAMILIAS["adventor"])
	return _cargar(datos["negrita" if negrita else "regular"], datos)


# ─── Reescalado de tamaños ───────────────────────────────────────────────────

func _cargar(ruta: String, datos: Dictionary) -> FontFile:
	var fuente: FontFile = load(ruta)
	# Pixeloid está dibujada píxel a píxel: sin suavizado para que no se emborrone.
	if datos.get("pixel", false):
		fuente.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		fuente.hinting = TextServer.HINTING_NONE
		fuente.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return fuente


## Los controles se escalan en diferido: así el script que los creó ya les
## puso sus tamaños, aunque lo haga justo después de añadirlos.
func _on_nodo_agregado(nodo: Node) -> void:
	if not nodo is Control:
		return
	if _pendientes.is_empty():
		_procesar_pendientes.call_deferred()
	_pendientes.append(nodo)


func _procesar_pendientes() -> void:
	var lote := _pendientes
	_pendientes = []
	for control in lote:
		if is_instance_valid(control) and control.is_inside_tree():
			_escalar(control)


## Recorre todo, hijos internos incluidos: así cambian también los diálogos
## que ya están abiertos.
func _reescalar_arbol(nodo: Node) -> void:
	if nodo is Control:
		_escalar(nodo)
	for hijo in nodo.get_children(true):
		_reescalar_arbol(hijo)


func _escalar(control: Control) -> void:
	if control.has_meta("sin_escala"):
		return
	var items := _tamanos_de(control)
	if items.is_empty():
		return
	# Tamaño de diseño (el que puso la escena o el script, o el heredado del
	# tema) y si venía como override, para poder restaurarlo tal cual.
	if not control.has_meta("_tam_base"):
		var base := {}
		for item in items:
			base[item] = [control.get_theme_font_size(item), control.has_theme_font_size_override(item)]
		control.set_meta("_tam_base", base)
	var guardado: Dictionary = control.get_meta("_tam_base")

	if is_equal_approx(_escala, 1.0):
		if not control.has_meta("_escalado"):
			return
		for item in guardado:
			if guardado[item][1]:
				control.add_theme_font_size_override(item, guardado[item][0])
			else:
				control.remove_theme_font_size_override(item)
		control.remove_meta("_escalado")
		return

	for item in guardado:
		control.add_theme_font_size_override(item, maxi(1, roundi(guardado[item][0] * _escala)))
	control.set_meta("_escalado", true)


func _tamanos_de(control: Control) -> Array[String]:
	if control is RichTextLabel:
		return TAMANOS_RICH_TEXT
	if control is Label or control is Button or control is LinkButton or control is LineEdit \
			or control is TextEdit or control is ItemList or control is TabBar or control is ProgressBar:
		return ["font_size"]
	return []
