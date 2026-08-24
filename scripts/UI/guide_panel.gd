## Panel modal de guía: muestra un mensaje de "qué hacer ahora" y espera a
## que el jugador lo cierre.
##
## Reutiliza el mismo lenguaje visual que tutorial_overlay (panel oscuro con
## borde dorado, fuentes PixelifySans, entrada con fade + slide) para que las
## guías del juego se lean siempre igual, aparezcan donde aparezcan.
##
## Bloquea el movimiento del jugador mediante SceneManager.is_ui_open mientras
## se muestra. Emite "closed" al cerrarse y se libera solo.
##
## Uso:
##     var panel := load("res://scenes/UI/guide_panel.tscn").instantiate()
##     add_child(panel)
##     panel.show_message("Título", "Cuerpo con [b]BBCode[/b]", "¡Entendido!")
##     await panel.closed
extends CanvasLayer

signal closed

const FONT_BOLD_PATH := "res://fonts/PixelifySans-SemiBold.ttf"
const FONT_REGULAR_PATH := "res://fonts/PixelifySans-VariableFont_wght.ttf"

const PANEL_WIDTH: int = 760
const PANEL_MIN_HEIGHT: int = 240
const MARGIN_BOTTOM: int = 40
const ANIM_DURATION: float = 0.35

var _font_bold: Font = null
var _font_regular: Font = null
var _was_ui_open: bool = false

## True desde que arranca el cierre: evita que un segundo Enter/E dispare
## _close() dos veces mientras corre la animación de salida.
var _closing: bool = false

@onready var _dim: ColorRect = $Dim
@onready var _panel: PanelContainer = $Panel
@onready var _title_label: Label = $Panel/Margin/VBox/Title
@onready var _body_label: RichTextLabel = $Panel/Margin/VBox/Body
@onready var _action_button: Button = $Panel/Margin/VBox/Footer/ActionButton


func _ready() -> void:
	layer = 60
	follow_viewport_enabled = false

	# El panel arranca oculto: sin esto se vería un recuadro vacío entre el
	# add_child() del llamante y su show_message().
	visible = false

	_font_bold = load(FONT_BOLD_PATH) if ResourceLoader.exists(FONT_BOLD_PATH) else null
	_font_regular = load(FONT_REGULAR_PATH) if ResourceLoader.exists(FONT_REGULAR_PATH) else null

	if SceneManager:
		SceneManager.ensure_fallbacks(_font_bold)
		SceneManager.ensure_fallbacks(_font_regular)

	if _font_bold:
		_title_label.add_theme_font_override("font", _font_bold)
		_action_button.add_theme_font_override("font", _font_bold)
	if _font_regular:
		_body_label.add_theme_font_override("normal_font", _font_regular)
		_body_label.add_theme_font_override("bold_font", _font_bold if _font_bold else _font_regular)

	_action_button.pressed.connect(_on_action_pressed)
	get_window().size_changed.connect(_layout)


# ─── API ─────────────────────────────────────────────────────────────────────

## Muestra el panel con el mensaje dado y lo anima de entrada.
## El cuerpo admite BBCode.
func show_message(title: String, body: String, button_text: String = "¡Entendido! ✓") -> void:
	# Permite llamar a show_message() antes de que el nodo entre en el árbol.
	if not is_node_ready():
		await ready

	_title_label.text = title
	_body_label.text = body
	_action_button.text = button_text

	# Visible pero transparente: el panel necesita un frame en pantalla para
	# que el RichTextLabel calcule su alto envuelto, y sin esto ese frame se
	# vería como un parpadeo.
	visible = true
	_dim.modulate.a = 0.0
	_panel.modulate.a = 0.0

	# Bloquear movimiento del jugador y otras interacciones mientras dure.
	_was_ui_open = SceneManager.is_ui_open
	SceneManager.is_ui_open = true

	_layout()
	await get_tree().process_frame
	_layout()
	_animate_in()


# ─── Entrada ─────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	# Un único mensaje que solo se puede aceptar: Enter / Space / E y Escape
	# hacen lo mismo, cerrarlo.
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _on_action_pressed() -> void:
	_close()


# ─── Layout ──────────────────────────────────────────────────────────────────

func _layout() -> void:
	if not visible:
		return

	var win := _get_window_size()
	_dim.size = win
	_dim.position = Vector2.ZERO

	# Alto según el contenido: los mensajes de guía varían mucho de longitud y
	# un alto fijo recortaría los más largos. El ancho se fija primero porque
	# el alto del cuerpo depende de cómo envuelva el texto a ese ancho.
	_panel.size.x = PANEL_WIDTH
	var height: float = maxf(float(PANEL_MIN_HEIGHT), _panel.get_combined_minimum_size().y)
	_panel.size = Vector2(PANEL_WIDTH, height)
	_panel.position = Vector2(
		(win.x - PANEL_WIDTH) / 2.0,
		win.y - height - MARGIN_BOTTOM
	)


func _get_window_size() -> Vector2:
	var window := get_window()
	if window:
		return Vector2(window.size)
	return Vector2(
		ProjectSettings.get_setting("display/window/size/window_width_override", 1280),
		ProjectSettings.get_setting("display/window/size/window_height_override", 720)
	)


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


func _close() -> void:
	if _closing:
		return
	_closing = true

	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_property(_panel, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_property(_panel, "position:y", _panel.position.y + 40.0, ANIM_DURATION)
	await tween.finished

	# Se restaura DESPUÉS de la animación a propósito: los NPC consultan
	# is_ui_open desde _process(), así que soltarlo antes haría que la misma
	# pulsación de E que cierra este panel reabriera el diálogo del NPC.
	SceneManager.is_ui_open = _was_ui_open

	closed.emit()
	queue_free()
