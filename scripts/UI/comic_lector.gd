## comic_lector.gd
## Lector de las páginas de un episodio. La página es una imagen sin texto; cada
## bocadillo es un Label real colocado con las coordenadas relativas del catálogo,
## así que el texto usa la fuente y el tamaño que eligió el alumno (Tipografia).
##
## Si el texto de un bocadillo no cabe en su globo con la fuente actual, ese
## bocadillo concreto no se pinta recortado: pasa al panel de lectura de debajo,
## y en la página queda un marco que señala dónde estaba. «No cabe» se MIDE con
## la misma fuente y el mismo tamaño que tendría el Label (ver cabe).
##
## No se libera solo: emite salir y quien lo instancia lo libera.
extends CanvasLayer

## El alumno pulsó «Volver al catálogo» (o Escape) o terminó el episodio.
signal salir
## Se pasó de la última página: el episodio queda guardado como leído.
signal episodio_terminado(episode_id: String)

## Tamaños de letra de diseño de los bocadillos (antes de la escala de Tipografia):
## normal, grande y máximo.
const TAMANOS_TEXTO: Array[int] = [16, 21, 28]
const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.0
const PASO_ZOOM := 1.25
## Píxeles que se desplaza la página con la rueda o las flechas de arriba y abajo.
const PASO_DESPLAZAR := 90.0
## Margen interior del globo que se respeta al medir y al pintar el texto.
const MARGEN_GLOBO := 3.0
const COLOR_MARCO := Color(1.0, 0.75, 0.2, 0.9)

const FUENTE := preload("res://fonts/fuente_juego.tres")

@onready var _titulo: Label = %Titulo
@onready var _indicador: Label = %Indicador
@onready var _boton_texto_menos: Button = %BotonTextoMenos
@onready var _boton_texto_mas: Button = %BotonTextoMas
@onready var _boton_zoom_menos: Button = %BotonZoomMenos
@onready var _boton_zoom_mas: Button = %BotonZoomMas
@onready var _boton_salir: Button = %BotonSalir
@onready var _visor: Control = %Visor
@onready var _pagina_nodo: Control = %Pagina
@onready var _panel: PanelContainer = %PanelLectura
@onready var _boton_panel: Button = %BotonPanel
@onready var _desplazable: ScrollContainer = %Desplazable
@onready var _lista: VBoxContainer = %Lista
@onready var _boton_anterior: Button = %BotonAnterior
@onready var _boton_siguiente: Button = %BotonSiguiente
@onready var _atribucion: Label = %Atribucion

var _episodio := ""
var _titulo_episodio := ""
var _num_paginas := 0
var _pagina := 0
var _textura: Texture2D
var _bocadillos: Array[Dictionary] = []
var _zoom := ZOOM_MIN
## Esquina superior izquierda de la página dentro del visor (<= 0 si hay desplazamiento).
var _desplazamiento := Vector2.ZERO
var _nivel_texto := 0
var _panel_oculto := false
var _arrastrando := false

## Un Label por bocadillo que cabe; null en los que van al panel.
var _etiquetas: Array[Label] = []
var _en_panel: Array[int] = []


func _ready() -> void:
	_boton_salir.pressed.connect(func(): salir.emit())
	_boton_anterior.pressed.connect(anterior)
	_boton_siguiente.pressed.connect(siguiente)
	_boton_zoom_mas.pressed.connect(cambiar_zoom.bind(PASO_ZOOM))
	_boton_zoom_menos.pressed.connect(cambiar_zoom.bind(1.0 / PASO_ZOOM))
	_boton_texto_mas.pressed.connect(fijar_nivel_texto.bind(1, true))
	_boton_texto_menos.pressed.connect(fijar_nivel_texto.bind(-1, true))
	_boton_panel.pressed.connect(_alternar_panel)
	# Ningún botón toma foco: con uno enfocado el GUI se queda las flechas e Intro
	# y la navegación de páginas dejaría de funcionar tras el primer clic.
	for b in [_boton_salir, _boton_anterior, _boton_siguiente, _boton_zoom_mas,
			_boton_zoom_menos, _boton_texto_mas, _boton_texto_menos, _boton_panel]:
		b.focus_mode = Control.FOCUS_NONE
	_visor.resized.connect(_maquetar)
	_visor.gui_input.connect(_al_entrar_visor)
	# Si cambia la familia tipográfica, cambia lo que cabe: se vuelve a medir.
	Tipografia.familia_aplicada.connect(_al_cambiar_familia)

	var atrib := ComicLibrary.atribucion()
	_atribucion.text = "«%s», de %s · %s · %s" % [
		atrib.get("titulo", ""), atrib.get("autor", ""), atrib.get("licencia", ""), atrib.get("enlace", "")]


# ─── API pública ────────────────────────────────────────────────────────────

## Abre un episodio en la página indicada (acotada al rango).
func abrir(episode_id: String, pagina: int) -> void:
	_episodio = ""
	for ep in ComicLibrary.episodios():
		if ep["id"] == episode_id:
			_episodio = episode_id
			_titulo_episodio = ep["titulo"]
			_num_paginas = ep["num_paginas"]
	if _episodio.is_empty():
		push_warning("[ComicLector] Episodio desconocido: %s" % episode_id)
		return
	_titulo.text = _titulo_episodio
	_zoom = ZOOM_MIN
	_mostrar_pagina(clampi(pagina, 0, _num_paginas - 1))


func episodio_actual() -> String:
	return _episodio


func pagina_actual() -> int:
	return _pagina


## Avanza una página; pasar de la última termina el episodio.
func siguiente() -> void:
	if _episodio.is_empty():
		return
	if _pagina + 1 < _num_paginas:
		ir_a(_pagina + 1)
	else:
		ComicLibrary.guardar_progreso(_episodio, _num_paginas - 1, true)
		episodio_terminado.emit(_episodio)
		salir.emit()


func anterior() -> void:
	if not _episodio.is_empty() and _pagina > 0:
		ir_a(_pagina - 1)


func ir_a(pagina: int) -> void:
	if _episodio.is_empty():
		return
	pagina = clampi(pagina, 0, _num_paginas - 1)
	# Un episodio ya leído sigue leído aunque se vuelva a páginas anteriores.
	ComicLibrary.guardar_progreso(_episodio, pagina, ComicLibrary.progreso(_episodio)["finished"])
	_mostrar_pagina(pagina)


func zoom() -> float:
	return _zoom


## Multiplica el zoom por un factor, entre ZOOM_MIN y ZOOM_MAX, manteniendo fijo
## el punto de la página que está en el centro del visor.
func cambiar_zoom(factor: float) -> void:
	var nuevo := clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(nuevo, _zoom):
		return
	var centro := _visor.size / 2.0
	_desplazamiento = centro - (centro - _desplazamiento) * (nuevo / _zoom)
	_zoom = nuevo
	_maquetar()


## Mueve la página (delta en píxeles del visor); nunca deja ver fuera de ella.
func desplazar(delta: Vector2) -> void:
	_desplazamiento += delta
	_acotar_desplazamiento()
	_pagina_nodo.position = _desplazamiento


func desplazamiento() -> Vector2:
	return _desplazamiento


## Tamaño de la página ya con el zoom, en píxeles del visor.
func tam_pagina() -> Vector2:
	return _pagina_nodo.size


func tam_visor() -> Vector2:
	return _visor.size


## 0 normal, 1 grande, 2 máximo. Con relativo = true el valor se suma al actual.
func fijar_nivel_texto(nivel: int, relativo: bool = false) -> void:
	var nuevo := clampi((_nivel_texto + nivel) if relativo else nivel, 0, TAMANOS_TEXTO.size() - 1)
	if nuevo == _nivel_texto:
		return
	_nivel_texto = nuevo
	_maquetar()


func nivel_texto() -> int:
	return _nivel_texto


## Tamaño de diseño del texto de los bocadillos (antes de la escala de Tipografia).
func tam_texto_diseno() -> int:
	return TAMANOS_TEXTO[_nivel_texto]


## Índices (en ComicLibrary.bocadillos) de los bocadillos que van al panel.
func bocadillos_en_panel() -> Array[int]:
	return _en_panel


## Label del bocadillo i dentro del globo, o null si ese va al panel.
func etiqueta(i: int) -> Label:
	return _etiquetas[i] if i >= 0 and i < _etiquetas.size() else null


func total_bocadillos() -> int:
	return _bocadillos.size()


func panel_visible() -> bool:
	return _panel.visible


## Labels de texto del panel de lectura, en el orden de la página.
func etiquetas_panel() -> Array[Label]:
	var res: Array[Label] = []
	for h in _lista.get_children():
		if h is Label and not h.is_queued_for_deletion():
			res.append(h)
	return res


## ¿Cabe este texto en una caja de ancho x alto píxeles con la fuente del juego a
## tam_diseno? Mide con la fuente compartida y el mismo tamaño que acabará teniendo
## el Label (diseño por la escala de la familia activa) y el mismo ajuste de línea
## que usa (AUTOWRAP_WORD_SMART). Una palabra más ancha que la caja no cabe: el
## Label la partiría por la mitad, y eso es justo lo que hay que evitar.
func cabe(texto: String, ancho: float, alto: float, tam_diseno: int) -> bool:
	var util_ancho := ancho - 2.0 * MARGEN_GLOBO
	var util_alto := alto - 2.0 * MARGEN_GLOBO
	if util_ancho <= 0.0 or util_alto <= 0.0:
		return false
	var tam := Tipografia.tam(tam_diseno)
	for palabra in texto.split(" ", false):
		if FUENTE.get_string_size(palabra, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > util_ancho:
			return false
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var medida := FUENTE.get_multiline_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, util_ancho, tam, -1, flags)
	return medida.y <= util_alto


# ─── Maquetación ────────────────────────────────────────────────────────────

func _mostrar_pagina(pagina: int) -> void:
	_pagina = pagina
	_textura = ComicLibrary.pagina(_episodio, pagina)
	_bocadillos = ComicLibrary.bocadillos(_episodio, pagina)
	_desplazamiento = Vector2.ZERO
	_panel_oculto = false
	_indicador.text = "Página %d de %d" % [pagina + 1, _num_paginas]
	_boton_anterior.disabled = pagina == 0
	_boton_siguiente.text = "Siguiente >" if pagina + 1 < _num_paginas else "Terminar"
	_maquetar()


## Coloca la página con el zoom actual y reparte los bocadillos entre los que
## caben en su globo (Label) y los que van al panel.
func _maquetar() -> void:
	if _episodio.is_empty() or _textura == null or _visor.size.x <= 0.0:
		return
	for h in _pagina_nodo.get_children():
		_pagina_nodo.remove_child(h)
		h.queue_free()
	# Zoom 1 = página a todo el ancho del visor; las altas se recorren desplazando.
	var tam_tex := _textura.get_size()
	var ancho := _visor.size.x * _zoom
	_pagina_nodo.size = Vector2(ancho, ancho * tam_tex.y / tam_tex.x)

	var imagen := TextureRect.new()
	imagen.name = "Imagen"
	imagen.texture = _textura
	imagen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	imagen.stretch_mode = TextureRect.STRETCH_SCALE
	imagen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	imagen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pagina_nodo.add_child(imagen)

	_etiquetas.clear()
	_en_panel.clear()
	var tam := tam_texto_diseno()
	for i in _bocadillos.size():
		var b: Dictionary = _bocadillos[i]
		var pos := Vector2(b["x"] * _pagina_nodo.size.x, b["y"] * _pagina_nodo.size.y)
		var caja := Vector2(b["ancho"] * _pagina_nodo.size.x, b["alto"] * _pagina_nodo.size.y)
		if cabe(b["texto"], caja.x, caja.y, tam):
			_etiquetas.append(_crear_etiqueta(b["texto"], pos, caja, tam, i))
		else:
			_etiquetas.append(null)
			_en_panel.append(i)
			_crear_marco(pos, caja, i)
	_llenar_panel(tam)
	_acotar_desplazamiento()
	_pagina_nodo.position = _desplazamiento
	_boton_zoom_menos.disabled = _zoom <= ZOOM_MIN + 0.001
	_boton_zoom_mas.disabled = _zoom >= ZOOM_MAX - 0.001
	_boton_texto_menos.disabled = _nivel_texto == 0
	_boton_texto_mas.disabled = _nivel_texto == TAMANOS_TEXTO.size() - 1


func _crear_etiqueta(texto: String, pos: Vector2, caja: Vector2, tam: int, i: int) -> Label:
	var l := Label.new()
	l.name = "Bocadillo_%d" % i
	l.text = texto
	l.position = pos
	l.size = caja
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", FUENTE)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", Color.BLACK)
	_pagina_nodo.add_child(l)
	return l


## Marco que señala en la página el globo cuyo texto está en el panel.
func _crear_marco(pos: Vector2, caja: Vector2, i: int) -> void:
	var m := ReferenceRect.new()
	m.name = "Marco_%d" % i
	m.editor_only = false
	m.border_color = COLOR_MARCO
	m.border_width = 2.0
	m.position = pos
	m.size = Vector2(maxf(caja.x, 4.0), maxf(caja.y, 4.0))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pagina_nodo.add_child(m)


func _llenar_panel(tam: int) -> void:
	for h in _lista.get_children():
		_lista.remove_child(h)
		h.queue_free()
	_panel.visible = not _en_panel.is_empty()
	for i in _en_panel:
		var l := Label.new()
		l.text = _bocadillos[i]["texto"]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_override("font", FUENTE)
		l.add_theme_font_size_override("font_size", maxi(tam, TAMANOS_TEXTO[1]))
		_lista.add_child(l)
	_aplicar_panel_oculto()


func _alternar_panel() -> void:
	_panel_oculto = not _panel_oculto
	_aplicar_panel_oculto()


func _aplicar_panel_oculto() -> void:
	_desplazable.visible = not _panel_oculto
	_boton_panel.text = "Mostrar" if _panel_oculto else "Ocultar"


## Si la página (con zoom) es mayor que el visor, no se puede arrastrar más allá
## de sus bordes; si es menor en un eje, queda centrada en él.
func _acotar_desplazamiento() -> void:
	var libre := _visor.size - _pagina_nodo.size
	for eje in 2:
		if libre[eje] >= 0.0:
			_desplazamiento[eje] = libre[eje] / 2.0
		else:
			_desplazamiento[eje] = clampf(_desplazamiento[eje], libre[eje], 0.0)


func _al_cambiar_familia(_id: String) -> void:
	_maquetar()


# ─── Entradas ───────────────────────────────────────────────────────────────

func _al_entrar_visor(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_arrastrando = event.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if not event.pressed:
					return
				var arriba: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
				if event.ctrl_pressed:
					cambiar_zoom(PASO_ZOOM if arriba else 1.0 / PASO_ZOOM)
				else:
					desplazar(Vector2(0, PASO_DESPLAZAR if arriba else -PASO_DESPLAZAR))
	elif event is InputEventMouseMotion and _arrastrando:
		desplazar(event.relative)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		salir.emit()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		siguiente()
	elif event.is_action_pressed("ui_left"):
		anterior()
	elif event.is_action_pressed("ui_down"):
		desplazar(Vector2(0, -PASO_DESPLAZAR))
	elif event.is_action_pressed("ui_up"):
		desplazar(Vector2(0, PASO_DESPLAZAR))
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS or event.keycode == KEY_KP_ADD):
		cambiar_zoom(PASO_ZOOM)
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT):
		cambiar_zoom(1.0 / PASO_ZOOM)
	else:
		return
	get_viewport().set_input_as_handled()
