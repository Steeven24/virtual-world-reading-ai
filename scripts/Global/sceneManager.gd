# SceneManager.gd (Configurado en Project Settings -> Autoload)
extends Node

var is_ui_open: bool = false
var emoji_font: Font = null
var simbolos_font: Font = null

const FUENTE_JUEGO := "res://fonts/fuente_juego.tres"

## Respaldos de todo el texto del juego (ver fonts/fuente_juego*.tres). En la
## web no hay fuentes del sistema: lo que no tenga la familia elegida sale de
## aquí. Twemoji pinta los emojis en color; Simbolos VW, los símbolos que no son
## emoji (✓ ✗ ➜ ▾…). Simbolos VW no lleva ningún código de Twemoji salvo ▶ ◀ ✖:
## si los tuviera, Godot usaría su versión en blanco y negro.
const FUENTE_EMOJI := "res://fonts/twemoji/twemoji.ttf"
const FUENTE_SIMBOLOS := "res://fonts/simbolos/SimbolosVW-Regular.ttf"

func _enter_tree() -> void:
	_setup_emoji_fallbacks()

func _ready() -> void:
	_setup_emoji_fallbacks()

func get_emoji_font() -> Font:
	if emoji_font == null and ResourceLoader.exists(FUENTE_EMOJI):
		emoji_font = load(FUENTE_EMOJI)
	return emoji_font

func get_simbolos_font() -> Font:
	if simbolos_font == null and ResourceLoader.exists(FUENTE_SIMBOLOS):
		simbolos_font = load(FUENTE_SIMBOLOS)
	return simbolos_font

## Añade a un FontFile suelto los mismos respaldos que llevan las fuentes del
## juego, en el mismo orden y sin repetirlos. Las FontVariation compartidas ya
## los traen en el recurso.
func ensure_fallbacks(font: Font) -> void:
	if not font or not (font is FontFile):
		return
	for respaldo in [get_emoji_font(), get_simbolos_font()]:
		if respaldo and not respaldo in font.fallbacks:
			font.fallbacks.append(respaldo)

func _setup_emoji_fallbacks() -> void:
	if not get_emoji_font():
		return

	# 1. Asegurar fallback en la fuente por defecto del tema global
	var sample_lbl := Label.new()
	var default_theme_font := sample_lbl.get_theme_font("font")
	if default_theme_font and default_theme_font is FontFile:
		ensure_fallbacks(default_theme_font)
	sample_lbl.free()

	# 2. Asegurar fallback en ThemeDB
	if ThemeDB.fallback_font and ThemeDB.fallback_font is FontFile:
		ensure_fallbacks(ThemeDB.fallback_font)

	# 3. Las fuentes del juego (fonts/fuente_juego*.tres, ver Tipografia) ya
	#    traen el emoji como respaldo en el propio recurso. La regular es
	#    también el último recurso de cualquier control sin tema.
	if ResourceLoader.exists(FUENTE_JUEGO):
		ThemeDB.fallback_font = load(FUENTE_JUEGO)

func transition_to(scene_path: String):
	# Aquí podrías añadir una animación de fade out más adelante
	get_tree().change_scene_to_file(scene_path)
