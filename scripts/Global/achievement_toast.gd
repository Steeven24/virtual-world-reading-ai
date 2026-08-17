## Notificación de logros estilo Steam mejorada.
## Muestra un recuadro animado en la esquina inferior derecha cuando se
## desbloquea un logro. Incluye shimmer, partículas y borde pulsante.
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
const PANEL_WIDTH: int = 340
const PANEL_HEIGHT: int = 95

const COLOR_GOLD := Color(0.93, 0.79, 0.28, 1.0)
const COLOR_BG := Color(0.04, 0.04, 0.09, 0.96)
const COLOR_BORDER := Color(0.85, 0.75, 0.3, 0.7)

# ─── Estado ──────────────────────────────────────────────────────────────────

var _queue: Array[Dictionary] = []
var _is_showing: bool = false
var _panel: PanelContainer = null
var _panel_style: StyleBoxFlat = null
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
	if SceneManager:
		SceneManager.ensure_fallbacks(_font_bold)
		SceneManager.ensure_fallbacks(_font_regular)
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
	_panel.clip_contents = true

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = COLOR_BG
	_panel_style.border_width_left = 2
	_panel_style.border_width_top = 2
	_panel_style.border_width_right = 2
	_panel_style.border_width_bottom = 2
	_panel_style.border_color = COLOR_BORDER
	_panel_style.corner_radius_top_left = 12
	_panel_style.corner_radius_top_right = 12
	_panel_style.corner_radius_bottom_left = 12
	_panel_style.corner_radius_bottom_right = 12
	_panel_style.shadow_color = Color(0.93, 0.79, 0.28, 0.2)
	_panel_style.shadow_size = 8
	_panel_style.shadow_offset = Vector2(0, 2)
	_panel_style.content_margin_left = 18
	_panel_style.content_margin_right = 18
	_panel_style.content_margin_top = 14
	_panel_style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", _panel_style)

	# Contenido horizontal: ícono + texto
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	_panel.add_child(hbox)

	# Ícono de trofeo grande
	var icon_lbl := Label.new()
	icon_lbl.text = "🏆"
	icon_lbl.add_theme_font_size_override("font_size", 30)
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon_lbl)

	# Contenedor de texto
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	# Título "¡Logro desbloqueado!"
	var title_label := Label.new()
	title_label.text = "¡Logro desbloqueado!"
	title_label.add_theme_color_override("font_color", COLOR_GOLD)
	title_label.add_theme_font_size_override("font_size", 14)
	if _font_bold:
		title_label.add_theme_font_override("font", _font_bold)
	vbox.add_child(title_label)

	# Nombre del logro
	var name_label := Label.new()
	name_label.text = achievement_name
	name_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.97))
	name_label.add_theme_font_size_override("font_size", 17)
	if _font_bold:
		name_label.add_theme_font_override("font", _font_bold)
	vbox.add_child(name_label)

	# Posicionar: esquina inferior derecha, fuera de pantalla (a la derecha)
	_panel.position = Vector2(
		win_size.x,  # fuera de la ventana a la derecha
		win_size.y - PANEL_HEIGHT - MARGIN
	)

	add_child(_panel)

	# ═══ Animación principal ═══
	var final_x: float = win_size.x - PANEL_WIDTH - MARGIN
	var offscreen_x: float = win_size.x + 20

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Slide in
	tween.tween_property(_panel, "position:x", final_x, ANIM_DURATION)
	# Efectos decorativos al llegar
	tween.tween_callback(_create_shimmer_effect)
	tween.tween_callback(_create_sparkles)
	tween.tween_callback(_start_border_pulse)
	# Esperar
	tween.tween_interval(DISPLAY_DURATION)
	# Slide-out + fade (ambos en paralelo, DESPUÉS de la espera)
	tween.tween_property(_panel, "position:x", offscreen_x, ANIM_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(_panel, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_callback(_on_toast_finished)


# ─── Efectos Decorativos ────────────────────────────────────────────────────

## Rayo de luz diagonal que cruza el panel (shimmer).
func _create_shimmer_effect() -> void:
	if not _panel or not is_instance_valid(_panel):
		return

	var shimmer := ColorRect.new()
	shimmer.color = Color(1.0, 1.0, 1.0, 0.08)
	shimmer.size = Vector2(40, PANEL_HEIGHT + 20)
	shimmer.position = Vector2(-50, -10)
	shimmer.rotation = deg_to_rad(-15)
	_panel.add_child(shimmer)

	var tween := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(shimmer, "position:x", float(PANEL_WIDTH + 50), 0.7)
	tween.tween_callback(func():
		if shimmer and is_instance_valid(shimmer):
			shimmer.queue_free()
	)


## Partículas ✨ decorativas que flotan alrededor del panel.
func _create_sparkles() -> void:
	if not _panel or not is_instance_valid(_panel):
		return

	var sparkle_positions := [
		Vector2(25, 15), Vector2(PANEL_WIDTH - 40, 20),
		Vector2(50, PANEL_HEIGHT - 25), Vector2(PANEL_WIDTH - 60, PANEL_HEIGHT - 20),
		Vector2(PANEL_WIDTH / 2.0, 10)
	]

	for i in range(sparkle_positions.size()):
		var sparkle := Label.new()
		sparkle.text = "✨"
		sparkle.add_theme_font_size_override("font_size", 10 + randi() % 6)
		sparkle.position = sparkle_positions[i]
		sparkle.modulate.a = 0.0
		_panel.add_child(sparkle)

		var delay := i * 0.12 + randf_range(0.0, 0.1)
		var sp_tween := create_tween()
		sp_tween.tween_property(sparkle, "modulate:a", 0.9, 0.25).set_delay(delay)
		sp_tween.tween_property(sparkle, "position:y", sparkle.position.y - 12, 0.6)
		sp_tween.parallel().tween_property(sparkle, "modulate:a", 0.0, 0.6)
		sp_tween.tween_callback(func():
			if sparkle and is_instance_valid(sparkle):
				sparkle.queue_free()
		)


## Pulsación sutil del borde dorado.
func _start_border_pulse() -> void:
	if not _panel_style or not _panel or not is_instance_valid(_panel):
		return

	var pulse := create_tween().set_loops(4)
	pulse.tween_method(func(val: float):
		if _panel_style:
			_panel_style.border_color = Color(0.85, 0.75, 0.3, val)
			_panel_style.shadow_color = Color(0.93, 0.79, 0.28, val * 0.3)
	, 0.5, 1.0, 0.35)
	pulse.tween_method(func(val: float):
		if _panel_style:
			_panel_style.border_color = Color(0.85, 0.75, 0.3, val)
			_panel_style.shadow_color = Color(0.93, 0.79, 0.28, val * 0.3)
	, 1.0, 0.5, 0.35)


# ─── Fin del toast ───────────────────────────────────────────────────────────

func _on_toast_finished() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
	_panel_style = null
	# Mostrar el siguiente en la cola, si hay
	_show_next()
