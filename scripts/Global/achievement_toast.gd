## Notificación de logros estilo Steam.
## Muestra un recuadro animado en la esquina inferior derecha cuando se
## desbloquea un logro. Soporta cola de notificaciones.
##
## Registrar como Autoload: Project Settings → Autoload → "AchievementToast"
extends CanvasLayer

# ─── Constantes ──────────────────────────────────────────────────────────────

const FONT_PATH := "res://fonts/PixelifySans-SemiBold.ttf"
const FONT_REGULAR_PATH := "res://fonts/PixelifySans-VariableFont_wght.ttf"

## Duración visible en segundos.
const DISPLAY_DURATION: float = 5.0

## Duración de las animaciones slide-in/slide-out.
const ANIM_DURATION: float = 0.4

## Margen desde los bordes de la pantalla (en px de ventana).
const MARGIN: int = 20

## Tamaño del panel (en px de ventana).
const PANEL_WIDTH: int = 320
const PANEL_HEIGHT: int = 90

# ─── Estado ──────────────────────────────────────────────────────────────────

var _queue: Array[Dictionary] = []
var _is_showing: bool = false
var _panel: PanelContainer = null
var _font_bold: Font = null
var _font_regular: Font = null

# ─── Ciclo de vida ───────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 100  # Por encima de todo
	# No seguir el viewport del juego (que es 192x108 en pixel art).
	# Esto hace que el CanvasLayer trabaje en coordenadas de ventana reales.
	follow_viewport_enabled = false
	_font_bold = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_font_regular = load(FONT_REGULAR_PATH) if ResourceLoader.exists(FONT_REGULAR_PATH) else null
	GameSession.achievement_unlocked.connect(_on_achievement_unlocked)


# ─── API ─────────────────────────────────────────────────────────────────────

func _on_achievement_unlocked(_id: String, display_name: String) -> void:
	_queue.append({"id": _id, "name": display_name})
	if not _is_showing:
		_show_next()


# ─── Lógica de presentación ─────────────────────────────────────────────────

func _show_next() -> void:
	if _queue.is_empty():
		_is_showing = false
		return

	_is_showing = true
	var data: Dictionary = _queue.pop_front()
	_create_toast(data["name"])


## Obtiene el tamaño real de la ventana (no el viewport del juego).
func _get_window_size() -> Vector2:
	var window := get_window()
	if window:
		return Vector2(window.size)
	# Fallback: usar el override de project.godot
	return Vector2(
		ProjectSettings.get_setting("display/window/size/window_width_override", 1280),
		ProjectSettings.get_setting("display/window/size/window_height_override", 720)
	)


func _create_toast(achievement_name: String) -> void:
	var win_size := _get_window_size()

	# Panel principal
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.85, 0.75, 0.3, 0.7)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)

	# Contenedor vertical
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	# Título "¡Logro desbloqueado!"
	var title_label := Label.new()
	title_label.text = "🏆 ¡Logro desbloqueado!"
	title_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.3, 1.0))
	title_label.add_theme_font_size_override("font_size", 15)
	if _font_bold:
		title_label.add_theme_font_override("font", _font_bold)
	vbox.add_child(title_label)

	# Nombre del logro
	var name_label := Label.new()
	name_label.text = achievement_name
	name_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95, 1.0))
	name_label.add_theme_font_size_override("font_size", 18)
	if _font_bold:
		name_label.add_theme_font_override("font", _font_bold)
	vbox.add_child(name_label)

	# Posicionar: esquina inferior derecha, fuera de pantalla (a la derecha)
	_panel.position = Vector2(
		win_size.x,  # fuera de la ventana a la derecha
		win_size.y - PANEL_HEIGHT - MARGIN
	)

	add_child(_panel)

	# Animación: slide-in desde la derecha
	var final_x: float = win_size.x - PANEL_WIDTH - MARGIN
	var offscreen_x: float = win_size.x + 20
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_panel, "position:x", final_x, ANIM_DURATION)
	tween.tween_interval(DISPLAY_DURATION)
	# Slide-out + fade (ambos en paralelo, DESPUÉS de la espera)
	tween.tween_property(_panel, "position:x", offscreen_x, ANIM_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(_panel, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_callback(_on_toast_finished)


func _on_toast_finished() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
	# Mostrar el siguiente en la cola, si hay
	_show_next()
