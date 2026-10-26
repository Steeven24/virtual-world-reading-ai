## comic_catalogo.gd
## Catálogo de episodios de la zona de cómics. Una sola escena con dos vistas que
## se alternan: «expositor» (portada central grande y las vecinas más pequeñas) y
## «rejilla» (todas las portadas más el panel de continuar). Arranca en el
## expositor; la vista elegida se recuerda con Ajustes.
##
## Este script no abre el lector: emite episodio_elegido y quien lo instancia
## decide qué hacer. Tampoco se libera solo al cerrar: emite cerrado.
extends CanvasLayer

## El alumno eligió un episodio; pagina_inicial es donde debe abrirse el lector.
signal episodio_elegido(episode_id: String, pagina_inicial: int)
## El alumno pulsó Cerrar (o Escape). Quien instancia el catálogo lo libera.
signal cerrado

const VISTA_EXPOSITOR := "expositor"
const VISTA_REJILLA := "rejilla"

## Tamaño de la portada central del expositor. Las portadas son apaisadas
## (1100x765) y se encajan con KEEP_ASPECT_CENTERED, así que otra proporción no
## deforma nada: solo deja bandas.
const TAM_PORTADA := Vector2(400, 278)
const ESCALA_VECINA := 0.8
const OPACIDAD_VECINA := 0.45
const SEPARACION_VECINAS := 30.0
const TAM_CELDA := Vector2(250, 205)
const COLOR_LEIDO := Color(0.35, 0.8, 0.45)

@onready var _contador: Label = %Contador
@onready var _boton_vista: Button = %BotonVista
@onready var _boton_cerrar: Button = %BotonCerrar
@onready var _expositor: Control = %Expositor
@onready var _pista: Control = %Pista
@onready var _boton_anterior: Button = %BotonAnterior
@onready var _boton_siguiente: Button = %BotonSiguiente
@onready var _titulo_expositor: Label = %TituloExpositor
@onready var _estado_expositor: Label = %EstadoExpositor
@onready var _rejilla: Control = %Rejilla
@onready var _cuadricula: GridContainer = %Cuadricula
@onready var _portada_continuar: TextureRect = %PortadaContinuar
@onready var _titulo_continuar: Label = %TituloContinuar
@onready var _barra_continuar: ProgressBar = %BarraContinuar
@onready var _texto_continuar: Label = %TextoContinuar
@onready var _boton_continuar: Button = %BotonContinuar

var _vista: String = VISTA_EXPOSITOR
var _episodios: Array[Dictionary] = []
var _indice := 0
var _items: Array[Control] = []
var _tween: Tween
var _continuar_id := ""
## Si el alumno ya movió el expositor, el progreso que llegue no lo recoloca.
var _movido := false


func _ready() -> void:
	_episodios = ComicLibrary.episodios()
	_construir_expositor()
	_construir_rejilla()

	_boton_vista.pressed.connect(cambiar_vista)
	_boton_cerrar.pressed.connect(func(): cerrado.emit())
	_boton_anterior.pressed.connect(mover_expositor.bind(-1))
	_boton_siguiente.pressed.connect(mover_expositor.bind(1))
	_boton_continuar.pressed.connect(_continuar)
	# Los botones que acompañan al expositor no toman foco: con un botón enfocado
	# el GUI se queda las flechas y Intro y nunca llegan a _unhandled_input.
	for b in [_boton_vista, _boton_cerrar, _boton_anterior, _boton_siguiente]:
		b.focus_mode = Control.FOCUS_NONE
	_pista.resized.connect(_colocar.bind(false))

	var guardada: String = str(Ajustes.obtener("comics_vista"))
	_vista = guardada if guardada == VISTA_REJILLA else VISTA_EXPOSITOR
	_aplicar_vista()

	# El progreso llega siempre (también sin red o sin sesión): se pinta al llegar.
	ComicLibrary.progreso_cargado.connect(_al_cargar_progreso)
	refrescar()
	# Con sesión el progreso llega después (GET asíncrono); sin ella, enseguida.
	ComicLibrary.cargar_progreso()
	_colocar(false)


# ─── API pública ────────────────────────────────────────────────────────────

func vista_actual() -> String:
	return _vista


## Alterna entre expositor y rejilla y recuerda la elección.
func cambiar_vista() -> void:
	_vista = VISTA_REJILLA if _vista == VISTA_EXPOSITOR else VISTA_EXPOSITOR
	Ajustes.fijar("comics_vista", _vista)
	_aplicar_vista()


## Vuelve a leer el progreso de ComicLibrary y repinta contador, marcas y panel.
func refrescar() -> void:
	var terminados := 0
	_continuar_id = ""
	for i in _episodios.size():
		var ep: Dictionary = _episodios[i]
		var p: Dictionary = ComicLibrary.progreso(ep["id"])
		if p["finished"]:
			terminados += 1
		elif p["last_page"] > 0 and _continuar_id == "":
			_continuar_id = ep["id"]
		_cuadricula.get_child(i).get_node("MarcaLeido").visible = p["finished"]
		_items[i].get_node("MarcaLeido").visible = p["finished"]
	_contador.text = "%d / %d leídos" % [terminados, _episodios.size()]
	_pintar_continuar()
	_pintar_pie_expositor()


## Episodio que señala el panel de continuar, o "" si no hay ninguno a medias.
func episodio_a_continuar() -> String:
	return _continuar_id


## Al llegar el progreso se repinta y, si el alumno aún no ha tocado el
## expositor, se coloca en el episodio a medias.
func _al_cargar_progreso() -> void:
	refrescar()
	if not _movido and _continuar_id != "":
		_indice = _posicion_de(_continuar_id)
		_pintar_pie_expositor()
		_colocar(false)


## Mueve el expositor n episodios (negativo = izquierda), sin salirse de los extremos.
func mover_expositor(n: int) -> void:
	if _episodios.is_empty():
		return
	_movido = true
	var nuevo := clampi(_indice + n, 0, _episodios.size() - 1)
	if nuevo == _indice:
		return
	_indice = nuevo
	_colocar(true)
	_pintar_pie_expositor()


func indice_expositor() -> int:
	return _indice


## Portada i del expositor (para pruebas y para quien quiera animarla).
func item_expositor(i: int) -> Control:
	return _items[i]


## Elige un episodio y emite episodio_elegido. Si estaba a medias se abre en la
## página donde se quedó; terminado o sin empezar, desde la portada.
func elegir(episode_id: String) -> void:
	if _episodios.is_empty():
		return
	var p: Dictionary = ComicLibrary.progreso(episode_id)
	var pagina: int = 0 if p["finished"] else p["last_page"]
	episodio_elegido.emit(episode_id, pagina)


# ─── Construcción ───────────────────────────────────────────────────────────

func _construir_expositor() -> void:
	for ep in _episodios:
		var item := Control.new()
		item.name = "Item_%s" % ep["id"]
		item.size = TAM_PORTADA
		item.pivot_offset = TAM_PORTADA / 2.0
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		var textura := _crear_textura(ep["id"])
		textura.set_anchors_preset(Control.PRESET_FULL_RECT)
		item.add_child(textura)
		item.add_child(_crear_marca())
		item.gui_input.connect(_al_pulsar_item.bind(item))
		_pista.add_child(item)
		_items.append(item)


func _construir_rejilla() -> void:
	for ep in _episodios:
		var celda := Button.new()
		celda.name = "Celda_%s" % ep["id"]
		celda.custom_minimum_size = TAM_CELDA
		celda.pressed.connect(elegir.bind(ep["id"]))
		var portada := _crear_textura(ep["id"])
		portada.set_anchors_preset(Control.PRESET_TOP_WIDE)
		portada.offset_left = 6
		portada.offset_right = -6
		portada.offset_top = 6
		portada.offset_bottom = 156
		celda.add_child(portada)
		var titulo := Label.new()
		titulo.name = "Titulo"
		titulo.text = ep["titulo"]
		titulo.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		titulo.offset_top = -44
		titulo.offset_bottom = -4
		titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		titulo.add_theme_font_override("font", load("res://fonts/fuente_juego.tres"))
		titulo.add_theme_font_size_override("font_size", 15)
		celda.add_child(titulo)
		celda.add_child(_crear_marca())
		_cuadricula.add_child(celda)


## Portada del episodio, encajada sin deformar sea cual sea su proporción.
func _crear_textura(episode_id: String) -> TextureRect:
	var t := TextureRect.new()
	t.name = "Portada"
	t.texture = ComicLibrary.pagina(episode_id, 0)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _crear_marca() -> Label:
	var marca := Label.new()
	marca.name = "MarcaLeido"
	marca.text = "Leído"
	marca.visible = false
	marca.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marca.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	marca.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	marca.offset_top = 10
	marca.offset_right = -10
	marca.add_theme_font_override("font", load("res://fonts/fuente_juego_negrita.tres"))
	marca.add_theme_font_size_override("font_size", 16)
	marca.add_theme_color_override("font_color", Color.BLACK)
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = COLOR_LEIDO
	fondo.set_corner_radius_all(4)
	fondo.content_margin_left = 8
	fondo.content_margin_right = 8
	fondo.content_margin_top = 2
	fondo.content_margin_bottom = 2
	marca.add_theme_stylebox_override("normal", fondo)
	return marca


# ─── Vistas ─────────────────────────────────────────────────────────────────

func _aplicar_vista() -> void:
	var en_expositor := _vista == VISTA_EXPOSITOR
	_expositor.visible = en_expositor
	_rejilla.visible = not en_expositor
	_boton_vista.text = "Ver en rejilla" if en_expositor else "Ver en expositor"
	if en_expositor:
		_colocar(false)


## Reparte las portadas del expositor alrededor del índice actual: la central a
## escala 1,0, las vecinas a 0,8 y más claras, y el resto escondidas.
func _colocar(animar: bool) -> void:
	if _items.is_empty() or _pista.size.x <= 0.0:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animar:
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var centro := _pista.size / 2.0
	var paso := TAM_PORTADA.x * (0.5 + ESCALA_VECINA * 0.5) + SEPARACION_VECINAS
	for i in _items.size():
		var d := i - _indice
		var item := _items[i]
		var escala := 1.0 if d == 0 else ESCALA_VECINA
		var alfa := 1.0 if d == 0 else (OPACIDAD_VECINA if absi(d) == 1 else 0.0)
		var destino := centro - TAM_PORTADA / 2.0 + Vector2(clampi(d, -2, 2) * paso, 0)
		item.mouse_filter = Control.MOUSE_FILTER_STOP if absi(d) <= 1 else Control.MOUSE_FILTER_IGNORE
		item.z_index = 1 if d == 0 else 0
		if animar:
			_tween.tween_property(item, "position", destino, 0.25)
			_tween.tween_property(item, "scale", Vector2.ONE * escala, 0.25)
			_tween.tween_property(item, "modulate:a", alfa, 0.25)
		else:
			item.position = destino
			item.scale = Vector2.ONE * escala
			item.modulate.a = alfa
	_boton_anterior.disabled = _indice == 0
	_boton_siguiente.disabled = _indice >= _items.size() - 1


func _pintar_pie_expositor() -> void:
	if _episodios.is_empty():
		return
	var ep: Dictionary = _episodios[_indice]
	var p: Dictionary = ComicLibrary.progreso(ep["id"])
	_titulo_expositor.text = ep["titulo"]
	if p["finished"]:
		_estado_expositor.text = "Leído · %d páginas" % ep["num_paginas"]
	elif p["last_page"] > 0:
		_estado_expositor.text = "Vas por la página %d de %d" % [p["last_page"] + 1, ep["num_paginas"]]
	else:
		_estado_expositor.text = "%d páginas" % ep["num_paginas"]


func _pintar_continuar() -> void:
	var ep := _episodio(_continuar_id)
	_boton_continuar.disabled = ep.is_empty()
	if ep.is_empty():
		_portada_continuar.texture = null
		_titulo_continuar.text = ""
		_barra_continuar.value = 0
		_texto_continuar.text = "Todavía no tienes ningún episodio a medias. Elige uno de la rejilla."
		return
	var p: Dictionary = ComicLibrary.progreso(ep["id"])
	_portada_continuar.texture = ComicLibrary.pagina(ep["id"], 0)
	_titulo_continuar.text = ep["titulo"]
	_barra_continuar.max_value = ep["num_paginas"]
	_barra_continuar.value = p["last_page"] + 1
	_texto_continuar.text = "Página %d de %d" % [p["last_page"] + 1, ep["num_paginas"]]


# ─── Entradas ───────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cerrado.emit()
		get_viewport().set_input_as_handled()
	elif _vista == VISTA_EXPOSITOR:
		if event.is_action_pressed("ui_right"):
			mover_expositor(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_left"):
			mover_expositor(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept") and not _episodios.is_empty():
			elegir(_episodios[_indice]["id"])
			get_viewport().set_input_as_handled()


func _al_pulsar_item(event: InputEvent, item: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var d := _items.find(item) - _indice
		if d == 0:
			elegir(_episodios[_indice]["id"])
		else:
			mover_expositor(d)


func _continuar() -> void:
	if _continuar_id != "":
		elegir(_continuar_id)


func _posicion_de(episode_id: String) -> int:
	for i in _episodios.size():
		if _episodios[i]["id"] == episode_id:
			return i
	return 0


func _episodio(episode_id: String) -> Dictionary:
	for ep in _episodios:
		if ep["id"] == episode_id:
			return ep
	return {}
