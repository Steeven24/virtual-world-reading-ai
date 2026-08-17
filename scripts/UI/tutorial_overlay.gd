## Overlay del tutorial guiado.
## Muestra un panel paso a paso al entrar al Lobby por primera vez,
## o cuando el jugador interactúa con el punto Tutorial del Lobby.
##
## Bloquea el movimiento del jugador mediante SceneManager.is_ui_open
## mientras se muestra. Emite "finished" al cerrarse.
extends CanvasLayer

signal finished

const FONT_BOLD_PATH := "res://fonts/PixelifySans-SemiBold.ttf"
const FONT_REGULAR_PATH := "res://fonts/PixelifySans-VariableFont_wght.ttf"

const PANEL_WIDTH: int = 760
const PANEL_HEIGHT: int = 260
const MARGIN_BOTTOM: int = 40
const ANIM_DURATION: float = 0.35

## Pasos del tutorial. Cada uno define título y cuerpo (con BBCode).
const STEPS: Array = [
	{
		"title": "👋 ¡Bienvenido al Mundo Virtual de Lectura!",
		"body": "Soy tu guía. Te mostraré en pocos pasos cómo explorar el lobby y empezar tus desafíos de lectura.",
	},
	{
		"title": "🎮 Movimiento",
		"body": "Usa las teclas [color=#f0c050][b]W A S D[/b][/color] o las [color=#f0c050][b]flechas[/b][/color] del teclado para mover a tu personaje por el escenario.",
	},
	{
		"title": "⭐ Puntuación",
		"body": "En la esquina superior derecha verás tu [color=#f0c050][b]puntuación total[/b][/color]. Cada respuesta correcta te dará puntos según el nivel de dificultad.",
	},
	{
		"title": "🏆 Logros",
		"body": "Pulsa el icono [color=#f0c050][b]🏆[/b][/color] de la esquina superior para ver tus logros desbloqueados, como leer tu primera lectura o completar las 5 tipologías.",
	},
	{
		"title": "📚 Las 5 tipologías textuales",
		"body": "En el lobby hay [color=#f0c050][b]5 estaciones[/b][/color], una por cada tipología: [b]Narrativo[/b], [b]Descriptivo[/b], [b]Expositivo[/b], [b]Instructivo[/b] y [b]Argumentativo[/b]. Visítalas todas para convertirte en Explorador.",
	},
	{
		"title": "🅴 Cómo iniciar un desafío",
		"body": "Acércate al cartel de una tipología. Cuando aparezca el icono [color=#f0c050][b]E[/b][/color] sobre tu personaje, presiona la tecla [b]E[/b] para comenzar la lectura.",
	},
	{
		"title": "🧠 Niveles de comprensión",
		"body": "Cada lectura tiene 3 niveles: [color=#f0c050][b]Literal[/b][/color] (lo que dice el texto), [color=#f0c050][b]Inferencial[/b][/color] (lo que se deduce) y [color=#f0c050][b]Crítico[/b][/color] (tu opinión razonada). Responde con atención para ganar más puntos.",
	},
	{
		"title": "🚀 ¡A explorar!",
		"body": "¡Eso es todo! Si quieres repasar este tutorial, acércate al [color=#f0c050][b]icono central[/b][/color] del lobby y presiona E. ¡Buena suerte, lector!",
	},
]

var _font_bold: Font = null
var _font_regular: Font = null
var _step_index: int = 0
var _was_ui_open: bool = false

@onready var _dim: ColorRect = $Dim
@onready var _panel: PanelContainer = $Panel
@onready var _title_label: Label = $Panel/Margin/VBox/Header/Title
@onready var _body_label: RichTextLabel = $Panel/Margin/VBox/Body
@onready var _counter_label: Label = $Panel/Margin/VBox/Footer/Counter
@onready var _skip_button: Button = $Panel/Margin/VBox/Footer/Buttons/SkipButton
@onready var _prev_button: Button = $Panel/Margin/VBox/Footer/Buttons/PrevButton
@onready var _next_button: Button = $Panel/Margin/VBox/Footer/Buttons/NextButton


func _ready() -> void:
	layer = 60
	follow_viewport_enabled = false

	_font_bold = load(FONT_BOLD_PATH) if ResourceLoader.exists(FONT_BOLD_PATH) else null
	_font_regular = load(FONT_REGULAR_PATH) if ResourceLoader.exists(FONT_REGULAR_PATH) else null

	if SceneManager:
		SceneManager.ensure_fallbacks(_font_bold)
		SceneManager.ensure_fallbacks(_font_regular)

	if _font_bold:
		_title_label.add_theme_font_override("font", _font_bold)
		_skip_button.add_theme_font_override("font", _font_bold)
		_prev_button.add_theme_font_override("font", _font_bold)
		_next_button.add_theme_font_override("font", _font_bold)
	if _font_regular:
		_body_label.add_theme_font_override("normal_font", _font_regular)
		_body_label.add_theme_font_override("bold_font", _font_bold if _font_bold else _font_regular)
		_counter_label.add_theme_font_override("font", _font_regular)

	_skip_button.pressed.connect(_on_skip_pressed)
	_prev_button.pressed.connect(_on_prev_pressed)
	_next_button.pressed.connect(_on_next_pressed)

	# Bloquear movimiento del jugador y otras interacciones mientras dure el tutorial.
	_was_ui_open = SceneManager.is_ui_open
	SceneManager.is_ui_open = true

	get_window().size_changed.connect(_layout)
	_layout()
	_render_step()
	_animate_in()


func _unhandled_input(event: InputEvent) -> void:
	# Permitir saltar al siguiente paso con Enter / Space / E,
	# y cerrar con Escape.
	if event.is_action_pressed("ui_cancel"):
		_on_skip_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_on_next_pressed()
		get_viewport().set_input_as_handled()


func _layout() -> void:
	var win := _get_window_size()
	_dim.size = win
	_dim.position = Vector2.ZERO
	_panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.position = Vector2(
		(win.x - PANEL_WIDTH) / 2.0,
		win.y - PANEL_HEIGHT - MARGIN_BOTTOM
	)


func _get_window_size() -> Vector2:
	var window := get_window()
	if window:
		return Vector2(window.size)
	return Vector2(
		ProjectSettings.get_setting("display/window/size/window_width_override", 1280),
		ProjectSettings.get_setting("display/window/size/window_height_override", 720)
	)


func _render_step() -> void:
	var step: Dictionary = STEPS[_step_index]
	_title_label.text = str(step.get("title", ""))
	_body_label.text = "[center]" + str(step.get("body", "")) + "[/center]"
	_counter_label.text = "Paso %d / %d" % [_step_index + 1, STEPS.size()]

	_prev_button.disabled = _step_index == 0
	_prev_button.modulate.a = 0.4 if _prev_button.disabled else 1.0

	if _step_index == STEPS.size() - 1:
		_next_button.text = "¡Empezar! ✓"
	else:
		_next_button.text = "Siguiente ▶"


func _on_next_pressed() -> void:
	if _step_index < STEPS.size() - 1:
		_step_index += 1
		_render_step()
		_pulse_panel()
	else:
		_close()


func _on_prev_pressed() -> void:
	if _step_index > 0:
		_step_index -= 1
		_render_step()
		_pulse_panel()


func _on_skip_pressed() -> void:
	_close()


func _close() -> void:
	# Restaurar estado de UI previo (si ya estaba abierto, no lo cerramos).
	SceneManager.is_ui_open = _was_ui_open

	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_property(_panel, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_property(_panel, "position:y", _panel.position.y + 40.0, ANIM_DURATION)
	await tween.finished

	finished.emit()
	queue_free()


# ─── Animaciones ─────────────────────────────────────────────────────────────

func _animate_in() -> void:
	_dim.modulate.a = 0.0
	_panel.modulate.a = 0.0
	var final_y := _panel.position.y
	_panel.position.y = final_y + 40.0

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 1.0, ANIM_DURATION)
	tween.tween_property(_panel, "modulate:a", 1.0, ANIM_DURATION).set_delay(0.05)
	tween.tween_property(_panel, "position:y", final_y, ANIM_DURATION).set_delay(0.05)


func _pulse_panel() -> void:
	# Pequeño "pop" al cambiar de paso para reforzar la transición.
	_panel.scale = Vector2(0.98, 0.98)
	_panel.pivot_offset = _panel.size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.18)
