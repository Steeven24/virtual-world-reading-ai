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

const LOBBY_SCENE := "res://scenes/Scenery/Lobby/lobby.tscn"

## Dónde estaba el jugador al salir del lobby, para que al volver aparezca
## ahí y no en el inicio: {"posicion": Vector2, "direccion": String}, o vacío.
## Vive en memoria: al recargar la página o al entrar otra cuenta se empieza
## en el inicio.
var lobby_spawn: Dictionary = {}

func _enter_tree() -> void:
	_setup_emoji_fallbacks()

func _ready() -> void:
	_setup_emoji_fallbacks()
	# En diferido: AuthManager es un autoload posterior a este.
	_conectar_sesion.call_deferred()


func _conectar_sesion() -> void:
	AuthManager.login_success.connect(func(_usuario: Dictionary): olvidar_posicion_lobby())
	AuthManager.logged_out.connect(olvidar_posicion_lobby)
	AuthManager.session_invalidated.connect(olvidar_posicion_lobby)

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
	if scene_path != LOBBY_SCENE:
		recordar_posicion_lobby(get_tree().current_scene)
	get_tree().change_scene_to_file(scene_path)


# ─── Posición en el lobby ────────────────────────────────────────────────────

## Guarda dónde está el jugador si la escena es el lobby. Sirve para todas las
## salidas: estaciones y tutorial.
func recordar_posicion_lobby(escena: Node) -> void:
	if escena == null or escena.scene_file_path != LOBBY_SCENE:
		return
	var jugador := escena.get_node_or_null("Player") as Node2D
	if jugador == null:
		return
	lobby_spawn = {"posicion": jugador.position, "direccion": str(jugador.get("last_direction"))}


## Coloca al jugador donde estaba. La llama el lobby en _enter_tree, antes del
## _ready del jugador, para que la cámara arranque ya en su sitio.
func aplicar_posicion_lobby(jugador: Node2D) -> void:
	if jugador == null or lobby_spawn.is_empty():
		return
	jugador.position = lobby_spawn["posicion"]
	if "last_direction" in jugador:
		jugador.last_direction = lobby_spawn["direccion"]


func olvidar_posicion_lobby() -> void:
	lobby_spawn = {}
