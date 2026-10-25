## Panel modal de ajustes, para abrirlos sin volver al Lobby.
##
## Durante la lectura es cuando más falta hacen: un alumno al que le cuesta el
## texto no debería tener que salir del escenario para cambiar la fuente o
## bajar la música. Dentro lleva el mismo AjustesControles que el menú del
## lobby, así que no hay dos versiones de los ajustes que mantener.
##
## Sigue el patrón de guide_panel: CanvasLayer propio, fondo oscurecido,
## bloquea el movimiento con SceneManager.is_ui_open, emite "cerrado" y se
## libera solo. En los desafíos no aparece porque allí no hay desde dónde
## abrirlo: son un cambio de escena completo.
##
## Uso:
##     var panel := AjustesPanel.new()
##     add_child(panel)
##     await panel.cerrado
class_name AjustesPanel
extends CanvasLayer

signal cerrado

const ANCHO_PANEL: int = 480
const ALTO_MAXIMO_LISTA: int = 500
const ANIM_DURACION: float = 0.2

const COLOR_FONDO := Color(0.06, 0.06, 0.12, 0.95)
const COLOR_BORDE := Color(0.4, 0.45, 0.7, 0.5)
const COLOR_TITULO := Color(0.79, 0.71, 0.35, 1.0)

var _controles: AjustesControles
var _dim: ColorRect
var _panel: PanelContainer
var _scroll: ScrollContainer
var _boton_cerrar: Button

var _ui_abierta_antes: bool = false
var _cerrando: bool = false


func _ready() -> void:
	layer = 60
	follow_viewport_enabled = false
	_construir()

	_ui_abierta_antes = SceneManager.is_ui_open
	SceneManager.is_ui_open = true
	Sonido.efecto("abrir")

	# El alto depende de qué secciones se vean: los desplegables de fuente y
	# música esconden las demás mientras están abiertos. Hay que escuchar
	# minimum_size_changed y no resized: dentro del ScrollContainer el nodo
	# conserva su tamaño aunque su contenido crezca, así que resized no llega.
	_controles.minimum_size_changed.connect(_ajustar_alto)
	await get_tree().process_frame
	_ajustar_alto()
	_animar_entrada()

	DialogFocus.marcar(_boton_cerrar)
	DialogFocus.enfocar(_boton_cerrar)


func _construir() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Se traga los clics: detrás está el libro y no debe reaccionar.
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_fondo_pulsado)
	add_child(_dim)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centro)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(ANCHO_PANEL, 0)
	_panel.add_theme_stylebox_override("panel", _estilo_panel())
	centro.add_child(_panel)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	_panel.add_child(caja)

	var cabecera := HBoxContainer.new()
	caja.add_child(cabecera)

	var titulo := Label.new()
	titulo.text = "⚙ Ajustes"
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulo.add_theme_color_override("font_color", COLOR_TITULO)
	titulo.add_theme_font_size_override("font_size", 18)
	cabecera.add_child(titulo)

	_boton_cerrar = Button.new()
	_boton_cerrar.text = "✕"
	_boton_cerrar.custom_minimum_size = Vector2(30, 0)
	_boton_cerrar.pressed.connect(_cerrar)
	cabecera.add_child(_boton_cerrar)

	caja.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	caja.add_child(_scroll)

	_controles = AjustesControles.new()
	_controles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Sin esto el contenido no se ensancha hasta el panel y el scroll aparece
	# aunque sobre sitio.
	_scroll.add_child(_controles)
	_controles.custom_minimum_size = Vector2(ANCHO_PANEL - 44, 0)


func _estilo_panel() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_FONDO
	estilo.border_color = COLOR_BORDE
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(12)
	estilo.content_margin_left = 16
	estilo.content_margin_right = 16
	estilo.content_margin_top = 14
	estilo.content_margin_bottom = 14
	return estilo


## El panel crece con su contenido hasta el tope, y a partir de ahí se
## desplaza: con OpenDyslexic y la lista de fuentes abierta no cabe entero.
func _ajustar_alto() -> void:
	if _controles == null or _scroll == null:
		return
	var alto := minf(float(ALTO_MAXIMO_LISTA), _controles.get_combined_minimum_size().y)
	# Sin esta guarda, cambiar el mínimo volvería a disparar la señal que nos
	# ha traído aquí.
	if is_equal_approx(_scroll.custom_minimum_size.y, alto):
		return
	_scroll.custom_minimum_size.y = alto


# ─── Entrada ─────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _cerrando:
		return
	if event.is_action_pressed("ui_cancel"):
		_cerrar()
		get_viewport().set_input_as_handled()


func _on_fondo_pulsado(event: InputEvent) -> void:
	var raton := event as InputEventMouseButton
	if raton and raton.pressed and raton.button_index == MOUSE_BUTTON_LEFT:
		_cerrar()


# ─── Apertura y cierre ───────────────────────────────────────────────────────

func _animar_entrada() -> void:
	_dim.modulate.a = 0.0
	_panel.modulate.a = 0.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 1.0, ANIM_DURACION)
	tween.tween_property(_panel, "modulate:a", 1.0, ANIM_DURACION)


func _cerrar() -> void:
	if _cerrando:
		return
	_cerrando = true
	_controles.cerrar_listas()
	Sonido.efecto("cerrar")

	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 0.0, ANIM_DURACION)
	tween.tween_property(_panel, "modulate:a", 0.0, ANIM_DURACION)
	await tween.finished

	# Igual que en guide_panel: se suelta DESPUÉS de la animación, para que la
	# misma pulsación que cierra esto no reabra lo que haya detrás.
	SceneManager.is_ui_open = _ui_abierta_antes

	cerrado.emit()
	queue_free()
