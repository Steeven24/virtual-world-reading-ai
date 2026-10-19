## Selector de la zona de práctica: el alumno elige qué tipología practicar.
##
## Las cuatro tipologías están siempre disponibles, aunque estén bloqueadas en
## la progresión: la práctica no cuenta para nada, así que sirve justamente para
## prepararse. Mismo lenguaje visual que guide_panel (panel oscuro con borde
## dorado, fuentes del juego, entrada con fade + slide).
##
## Bloquea el movimiento con SceneManager.is_ui_open mientras está abierto y se
## libera solo al cerrarse.
##
## Uso:
##     var selector := load("res://scenes/UI/practice_selector.tscn").instantiate()
##     add_child(selector)
##     selector.typology_chosen.connect(_on_tipologia_elegida)
##     selector.open()
extends CanvasLayer

## El alumno eligió una tipología.
signal typology_chosen(typology: String)

## El alumno cerró el selector sin elegir.
signal canceled

const FONT_BOLD_PATH := "res://fonts/fuente_juego_negrita.tres"
const FONT_REGULAR_PATH := "res://fonts/fuente_juego.tres"

const PANEL_WIDTH: int = 620
const MARGIN_BOTTOM: int = 40
const ANIM_DURATION: float = 0.3

const COLOR_ORO := Color(0.95, 0.85, 0.4, 1.0)

@onready var _dim: ColorRect = $Dim
@onready var _panel: PanelContainer = $Panel
@onready var _title_label: Label = $Panel/Margin/VBox/Title
@onready var _body_label: Label = $Panel/Margin/VBox/Body
@onready var _options: VBoxContainer = $Panel/Margin/VBox/Options
@onready var _cancel_button: Button = $Panel/Margin/VBox/Footer/CancelButton

var _typology_buttons: Array[Button] = []
var _was_ui_open: bool = false

## True desde que arranca el cierre: evita elegir dos veces mientras corre la
## animación de salida.
var _closing: bool = false


func _ready() -> void:
	layer = 60
	follow_viewport_enabled = false
	# Oculto hasta open(): sin esto se vería un recuadro vacío un frame.
	visible = false

	var font_bold: Font = load(FONT_BOLD_PATH) if ResourceLoader.exists(FONT_BOLD_PATH) else null
	var font_regular: Font = load(FONT_REGULAR_PATH) if ResourceLoader.exists(FONT_REGULAR_PATH) else null
	if SceneManager:
		SceneManager.ensure_fallbacks(font_bold)
		SceneManager.ensure_fallbacks(font_regular)
	if font_bold:
		_title_label.add_theme_font_override("font", font_bold)
		_cancel_button.add_theme_font_override("font", font_bold)
	if font_regular:
		_body_label.add_theme_font_override("font", font_regular)

	var estilo: StyleBox = _cancel_button.get_theme_stylebox("normal")
	for typology in ProgressionManager.DIFFICULTY_ORDER:
		var boton := Button.new()
		# "Narrativo" → "Textos narrativos": las cuatro terminan en -o.
		boton.text = "Textos %ss" % typology.to_lower()
		boton.custom_minimum_size = Vector2(0, 42)
		boton.add_theme_stylebox_override("normal", estilo)
		boton.add_theme_stylebox_override("hover", estilo)
		boton.add_theme_stylebox_override("pressed", estilo)
		boton.add_theme_color_override("font_color", COLOR_ORO)
		boton.add_theme_font_size_override("font_size", 16)
		if font_bold:
			boton.add_theme_font_override("font", font_bold)
		boton.pressed.connect(_on_typology_pressed.bind(typology))
		_options.add_child(boton)
		_typology_buttons.append(boton)

	_cancel_button.pressed.connect(_on_cancel_pressed)
	get_window().size_changed.connect(_layout)


## Muestra el selector con su animación de entrada.
func open() -> void:
	if not is_node_ready():
		await ready

	Sonido.efecto("abrir")
	visible = true
	_dim.modulate.a = 0.0
	_panel.modulate.a = 0.0

	_was_ui_open = SceneManager.is_ui_open
	SceneManager.is_ui_open = true

	# Dos pasadas de layout: el cuerpo necesita un frame con el ancho definitivo
	# para saber cuánto alto ocupa (igual que en guide_panel).
	_layout()
	await get_tree().process_frame
	_layout()
	_animate_in()

	var botones: Array[Button] = _typology_buttons.duplicate()
	botones.append(_cancel_button)
	DialogFocus.encadenar(botones, true)
	DialogFocus.enfocar(_typology_buttons[0])


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


func _on_typology_pressed(typology: String) -> void:
	if _closing:
		return
	await _close()
	typology_chosen.emit(typology)


func _on_cancel_pressed() -> void:
	if _closing:
		return
	await _close()
	canceled.emit()


func _layout() -> void:
	if not visible:
		return
	var win := _get_window_size()
	_dim.size = win
	_dim.position = Vector2.ZERO
	_panel.size.x = PANEL_WIDTH
	var height: float = _panel.get_combined_minimum_size().y
	_panel.size = Vector2(PANEL_WIDTH, height)
	_panel.position = Vector2((win.x - PANEL_WIDTH) / 2.0, win.y - height - MARGIN_BOTTOM)


func _get_window_size() -> Vector2:
	# Con el estirado canvas_items la interfaz mide siempre 1280x720, sea cual
	# sea la ventana: el tamaño real (get_window().size) ya no sirve aquí.
	return get_viewport().get_visible_rect().size


func _animate_in() -> void:
	var final_y := _panel.position.y
	_panel.position.y = final_y + 40.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 1.0, ANIM_DURATION)
	tween.tween_property(_panel, "modulate:a", 1.0, ANIM_DURATION).set_delay(0.05)
	tween.tween_property(_panel, "position:y", final_y, ANIM_DURATION).set_delay(0.05)


func _close() -> void:
	_closing = true
	Sonido.efecto("cerrar")
	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_property(_panel, "modulate:a", 0.0, ANIM_DURATION)
	await tween.finished
	# Como en guide_panel: se suelta DESPUÉS de la animación, para que la misma
	# pulsación que cierra el selector no reabra la estación.
	SceneManager.is_ui_open = _was_ui_open
	queue_free()
