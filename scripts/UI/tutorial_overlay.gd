## Overlay del tutorial guiado.
## Muestra un panel paso a paso al entrar al Lobby por primera vez,
## o cuando el jugador interactúa con el punto Tutorial del Lobby.
##
## Bloquea el movimiento del jugador mediante SceneManager.is_ui_open
## mientras se muestra. Emite "finished" al cerrarse.
extends CanvasLayer

signal finished

const FONT_BOLD_PATH := "res://fonts/fuente_juego_negrita.tres"
const FONT_REGULAR_PATH := "res://fonts/fuente_juego.tres"

const PANEL_WIDTH: int = 760
## Alto mínimo: los pasos que presentan a los personajes crecen por encima.
const PANEL_HEIGHT: int = 260
const MARGIN_BOTTOM: int = 40
const ANIM_DURATION: float = 0.35

## Pasos del tutorial. Cada uno define título y cuerpo (con BBCode).
##
## El detalle de las herramientas del libro no está aquí a propósito: se
## explica dentro del libro la primera vez que se abre, que es donde se usa.
const STEPS: Array = [
	{
		"title": "👋 ¡Bienvenido al mundo virtual de la comprensión lectora!",
		"body": "Soy tu guía. En unos pocos pasos te enseño cómo moverte, quién es quién y qué tienes que hacer para completar una lectura.",
	},
	{
		"title": "🎮 Movimiento",
		"body": "Muévete con las teclas [color=#f0c050][b]W A S D[/b][/color] o las [color=#f0c050][b]flechas[/b][/color], y mantén [color=#f0c050][b]Shift[/b][/color] para correr.\n\nCuando te acerques a algo con lo que puedas interactuar, aparecerá el ícono [color=#f0c050][b]E[/b][/color] sobre tu personaje. Púlsalo para hablar, leer o empezar.",
	},
	{
		"title": "⭐ Tu progreso",
		"body": "Arriba a la derecha tienes tu [color=#f0c050][b]puntuación[/b][/color]: cada respuesta correcta suma según el nivel de dificultad.\n\nEn el ícono [color=#f0c050][b]🏆[/b][/color] están tus logros, el cómo leer tu primera lectura o cómo completar las 4 tipologías textuales.",
	},
	{
		"title": "📚 Las 4 tipologías textuales",
		"body": "En el lobby hay [color=#f0c050][b]4 estaciones[/b][/color], una por tipología: [b]Narrativo[/b], [b]Descriptivo[/b], [b]Argumentativo[/b] y [b]Expositivo[/b].\n\nTienes [color=#f0c050][b]5 intentos[/b][/color] por tipología: cada lectura que terminas cuenta como uno y las lecturas no se repiten. Si gastas los 5 sin aprobar, ya no podrás avanzar.\n\n[color=#f0c050][b]➜ Camina hasta el cartel de una de ellas y pulsa E[/b][/color] para entrar. Visítalas todas para convertirte en explorador.\n\nY si quieres ensayar sin que cuente, usa la [color=#f0c050][b]Herramienta de práctica[/b][/color]: ahí puedes practicar cualquier tipología.",
	},
	{
		"title": "📖 La sala de lectura",
		"body": "Dentro encontrarás un [color=#f0c050][b]libro[/b][/color]. Acércate y pulsa [b]E[/b] para abrirlo.\n\nNo es solo texto: trae herramientas para [b]resaltar[/b], [b]subrayar[/b] y [b]tomar notas[/b] mientras lees. Te las explico cuando lo abras.",
	},
	{
		"title": "🧙 El sabio",
		"body": "Está sentado en la sala de lectura. Te da [color=#f0c050][b]consejos de comprensión lectora[/b][/color]: técnicas que te sirven para cualquier texto.\n\n[color=#f0c050][b]➜ Acércate y pulsa E[/b][/color] antes de abrir el libro. Cada vez que hables con él te dará un consejo distinto.",
	},
	{
		"title": "🤖 El robot asistente",
		"body": "También está en la sala de lectura. Responde a [color=#f0c050][b]tus preguntas concretas[/b][/color] sobre el texto y te orienta si te pierdes con el juego.\n\n[color=#f0c050][b]➜ Pulsa E y escribe tu duda.[/b][/color] Te dará pistas para que llegues tú a la respuesta, nunca a la respuesta directa.",
	},
	{
		"title": "🧑‍🏫 El profesor",
		"body": "Aparece [color=#f0c050][b]cuando terminas la lectura[/b][/color]. Es quien te pone a prueba, con desafíos adaptados a la tipología del texto.\n\n[color=#f0c050][b]➜ Acércate y pulsa E[/b][/color] para empezar. Hay 3 niveles: [b]literal[/b] (lo que el texto dice), [b]inferencial[/b] (lo que deja entender) y [b]crítico[/b] (lo que tú opinas y por qué).",
	},
	{
		"title": "🗺️ Tu recorrido",
		"body": "Cartel de una tipología ➜ sabio y robot ➜ libro ➜ profesor.\n\nY con el profesor, tres desafíos seguidos: [b]literal[/b] ➜ [b]inferencial[/b] ➜ [b]crítico[/b].\n\n¿Quieres repasar esto? Vuelve al [color=#f0c050][b]ícono central[/b][/color] del lobby y pulsa [b]E[/b]. ¡Buena suerte, lector!",
	},
]

var _font_bold: Font = null
var _font_regular: Font = null
var _step_index: int = 0
var _was_ui_open: bool = false

## True desde que arranca el cierre, para no dispararlo dos veces.
var _closing: bool = false

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
	Sonido.efecto("abrir")

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

	# Transparente antes de medir: ajustar el alto al contenido necesita un
	# frame en pantalla, y sin esto ese frame se vería como un parpadeo.
	_dim.modulate.a = 0.0
	_panel.modulate.a = 0.0

	# Navegable con teclado: flechas entre Saltar / Anterior / Siguiente y
	# Enter o E para pulsar el que esté enfocado. Sin esto solo valía el ratón.
	DialogFocus.encadenar([_skip_button, _prev_button, _next_button])

	get_window().size_changed.connect(_layout)
	_layout()
	await _render_step()
	_animate_in()
	DialogFocus.enfocar(_next_button)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_skip_pressed()
		get_viewport().set_input_as_handled()
		return

	if not event.is_action_pressed("ui_accept"):
		return

	# Enter / Espacio / E ya los gestiona el botón enfocado, y además lo hace al
	# SOLTAR la tecla. Atenderlos también aquí contaba cada pulsación dos veces:
	# Siguiente saltaba dos pasos, y Anterior retrocedía uno para volver a
	# avanzar otro, quedándose en el mismo sitio.
	#
	# Solo se atiende si ningún botón tiene el foco, para que el tutorial nunca
	# se quede sin respuesta al teclado.
	if _boton_enfocado() != null:
		return

	_on_next_pressed()
	get_viewport().set_input_as_handled()


## Botón del pie que tiene el foco, o null si no lo tiene ninguno.
func _boton_enfocado() -> Button:
	for boton: Button in [_next_button, _prev_button, _skip_button]:
		if is_instance_valid(boton) and boton.has_focus():
			return boton
	return null


func _layout() -> void:
	var win := _get_window_size()
	_dim.size = win
	_dim.position = Vector2.ZERO

	# Alto según el contenido: los pasos que presentan a los personajes son
	# más largos y con un alto fijo se cortarían. El ancho se aplica primero
	# porque el alto del cuerpo depende de cómo envuelva el texto a ese ancho.
	_panel.size.x = PANEL_WIDTH
	var height: float = maxf(float(PANEL_HEIGHT), _panel.get_combined_minimum_size().y)
	_panel.size = Vector2(PANEL_WIDTH, height)
	_panel.position = Vector2(
		(win.x - PANEL_WIDTH) / 2.0,
		win.y - height - MARGIN_BOTTOM
	)


func _get_window_size() -> Vector2:
	# Con el estirado canvas_items la interfaz mide siempre 1280x720, sea cual
	# sea la ventana: el tamaño real (get_window().size) ya no sirve aquí.
	return get_viewport().get_visible_rect().size


func _render_step() -> void:
	var step: Dictionary = STEPS[_step_index]
	_title_label.text = str(step.get("title", ""))
	_body_label.text = "[center]" + str(step.get("body", "")) + "[/center]"
	_counter_label.text = "Paso %d / %d" % [_step_index + 1, STEPS.size()]

	_prev_button.disabled = _step_index == 0
	_prev_button.modulate.a = 0.4 if _prev_button.disabled else 1.0
	# Deshabilitado también significa no enfocable: así las flechas lo saltan
	# en lugar de dejar el foco en un botón que no hace nada.
	_prev_button.focus_mode = Control.FOCUS_NONE if _prev_button.disabled else Control.FOCUS_ALL
	if _prev_button.disabled and _prev_button.has_focus():
		DialogFocus.enfocar(_next_button)

	if _step_index == STEPS.size() - 1:
		_next_button.text = "¡Empezar! ✓"
	else:
		_next_button.text = "Siguiente ▶"

	# Dos pases: el primero aplica el ancho, y solo tras un frame el cuerpo
	# sabe cuánto alto necesita para ese ancho.
	_layout()
	await get_tree().process_frame
	_layout()


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
	# Un segundo Escape mientras corre la animación de salida no debe volver a
	# entrar aquí: emitiría "finished" dos veces.
	if _closing:
		return
	_closing = true
	Sonido.efecto("cerrar")

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
