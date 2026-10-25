## Controles de ajustes (fuente, música, efectos y pantalla completa), como un
## bloque reutilizable que se puede meter en cualquier panel.
##
## Nació dentro del menú del HUD del lobby, pero los ajustes hacen falta
## también durante la lectura: un alumno que no ve bien el texto no debería
## tener que volver al Lobby para cambiar la fuente. Vive aquí para que haya
## una sola implementación y los dos sitios se comporten igual.
##
## Cada cambio va a Ajustes, que lo guarda por cuenta y lo aplica (Tipografia,
## Sonido). Quien lo use solo necesita:
##
##     var controles := AjustesControles.new()
##     contenedor.add_child(controles)
##     controles.refrescar()      # al abrir el panel que lo contiene
##     controles.cerrar_listas()  # al cerrarlo
class_name AjustesControles
extends VBoxContainer

const COLOR_TITULO_AJUSTE := Color(0.79, 0.71, 0.35, 1.0)
const COLOR_NOTA_AJUSTE := Color(0.5, 0.54, 0.7, 1.0)

var _selector_fuente: Button
var _lista_fuentes: VBoxContainer
var _interruptor_musica: CheckButton
var _selector_pista: Button
var _lista_pistas: VBoxContainer
var _volumen_musica: HSlider
var _etiqueta_volumen_musica: Label
var _interruptor_efectos: CheckButton
var _volumen_efectos: HSlider
var _etiqueta_volumen_efectos: Label
var _interruptor_pantalla: CheckButton

## Lo que se ve de cada sección del menú, sin su lista. Con una lista abierta,
## el menú solo enseña la sección de esa lista (ver _mostrar_lista).
var _seccion_fuente: Array[Control] = []
var _seccion_musica: Array[Control] = []
var _seccion_efectos: Array[Control] = []
var _seccion_pantalla: Array[Control] = []

## Mientras se copian los valores de Ajustes a los controles, sus señales no
## deben volver a escribir en Ajustes.
var _refrescando := false



func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_construir_ajustes()


func _construir_ajustes() -> void:
	_seccion_fuente.append(HSeparator.new())
	_seccion_fuente.append(_etiqueta_ajuste("TituloFuente", "🔤 Fuente del texto"))
	_selector_fuente = _desplegable("SelectorFuente")
	_selector_fuente.pressed.connect(_alternar_lista.bind(true))
	_seccion_fuente.append(_selector_fuente)
	_lista_fuentes = _lista_ajuste("ListaFuentes")
	for id in Tipografia.ORDEN:
		var opcion := _opcion_ajuste("Fuente_" + id)
		# Cada nombre con su propia fuente, al tamaño que ocupa en el juego.
		opcion.add_theme_font_override("font", Tipografia.fuente_de(id))
		opcion.add_theme_font_size_override("font_size", roundi(16 * Tipografia.escala(id)))
		opcion.set_meta("sin_escala", true)
		opcion.pressed.connect(_elegir_fuente.bind(id))
		_lista_fuentes.add_child(opcion)

	_seccion_musica.append(HSeparator.new())
	_interruptor_musica = _interruptor_ajuste("InterruptorMusica", "🎵 Música")
	_interruptor_musica.toggled.connect(_on_interruptor.bind("musica_activa"))
	_seccion_musica.append(_interruptor_musica)
	_selector_pista = _desplegable("SelectorPista")
	_selector_pista.pressed.connect(_alternar_lista.bind(false))
	_seccion_musica.append(_selector_pista)
	_lista_pistas = _lista_ajuste("ListaPistas")
	for id in Sonido.ORDEN_PISTAS:
		var opcion := _opcion_ajuste("Pista_" + id)
		opcion.pressed.connect(_elegir_pista.bind(id))
		_lista_pistas.add_child(opcion)
	var fila_musica := _fila_volumen("VolumenMusica", "EtiquetaVolumenMusica")
	_volumen_musica = fila_musica.get_node("VolumenMusica")
	_etiqueta_volumen_musica = fila_musica.get_node("EtiquetaVolumenMusica")
	_volumen_musica.value_changed.connect(_on_volumen.bind("musica_volumen", _etiqueta_volumen_musica))
	_seccion_musica.append(fila_musica)

	_seccion_efectos.append(HSeparator.new())
	_interruptor_efectos = _interruptor_ajuste("InterruptorEfectos", "🔔 Efectos de sonido")
	_interruptor_efectos.toggled.connect(_on_interruptor.bind("efectos_activos"))
	_seccion_efectos.append(_interruptor_efectos)
	var fila_efectos := _fila_volumen("VolumenEfectos", "EtiquetaVolumenEfectos")
	_volumen_efectos = fila_efectos.get_node("VolumenEfectos")
	_etiqueta_volumen_efectos = fila_efectos.get_node("EtiquetaVolumenEfectos")
	_volumen_efectos.value_changed.connect(_on_volumen.bind("efectos_volumen", _etiqueta_volumen_efectos))
	_seccion_efectos.append(fila_efectos)

	# Pantalla completa: preferencia del equipo (Pantalla), no de la cuenta.
	_seccion_pantalla.append(HSeparator.new())
	_interruptor_pantalla = _interruptor_ajuste("InterruptorPantalla", "🖥️ Pantalla completa")
	_interruptor_pantalla.toggled.connect(_on_pantalla_completa)
	_seccion_pantalla.append(_interruptor_pantalla)

	# Cada lista, justo debajo de su selector.
	var nodos: Array[Control] = []
	nodos.append_array(_seccion_fuente)
	nodos.append(_lista_fuentes)
	nodos.append_array(_seccion_musica)
	nodos.insert(nodos.find(_selector_pista) + 1, _lista_pistas)
	nodos.append_array(_seccion_efectos)
	nodos.append_array(_seccion_pantalla)
	for nodo in nodos:
		add_child(nodo)
	refrescar()


# ─── API ─────────────────────────────────────────────────────────────────────

## Copia a los controles lo que dice Ajustes. Hay que llamarla al abrir el
## panel que los contiene: los ajustes son por cuenta y pueden haber cambiado
## desde el otro sitio que también los muestra.
func refrescar() -> void:
	_refrescando = true
	var fuente := str(Ajustes.obtener("fuente"))
	if not Tipografia.FAMILIAS.has(fuente):
		fuente = "adventor"
	_selector_fuente.text = Tipografia.FAMILIAS[fuente]["nombre"]
	for id in Tipografia.ORDEN:
		var familia: Dictionary = Tipografia.FAMILIAS[id]
		_marcar_opcion(_lista_fuentes.get_node("Fuente_" + id), id == fuente, familia["nombre"], familia["nota"])

	var musica_activa := bool(Ajustes.obtener("musica_activa"))
	var pista := str(Ajustes.obtener("musica_pista"))
	if not Sonido.PISTAS.has(pista):
		pista = "biblioteca"
	_interruptor_musica.button_pressed = musica_activa
	_selector_pista.text = Sonido.PISTAS[pista]["nombre"]
	_selector_pista.disabled = not musica_activa
	_volumen_musica.editable = musica_activa
	for id in Sonido.ORDEN_PISTAS:
		var datos: Dictionary = Sonido.PISTAS[id]
		_marcar_opcion(_lista_pistas.get_node("Pista_" + id), id == pista, datos["nombre"], datos["nota"])
	_volumen_musica.value = int(Ajustes.obtener("musica_volumen"))
	_etiqueta_volumen_musica.text = "%d %%" % int(Ajustes.obtener("musica_volumen"))

	var efectos_activos := bool(Ajustes.obtener("efectos_activos"))
	_interruptor_efectos.button_pressed = efectos_activos
	_volumen_efectos.editable = efectos_activos
	_volumen_efectos.value = int(Ajustes.obtener("efectos_volumen"))
	_etiqueta_volumen_efectos.text = "%d %%" % int(Ajustes.obtener("efectos_volumen"))

	# El modo real, no la preferencia: el alumno pudo salir con el navegador.
	_interruptor_pantalla.button_pressed = Pantalla.es_completa()
	_refrescando = false


## Cierra el desplegable que hubiera abierto. Hay que llamarla al cerrar el
## panel que los contiene, para que la próxima vez se abra entero.
func cerrar_listas() -> void:
	_mostrar_lista(null)


# ─── Desplegables ────────────────────────────────────────────────────────────

## Abre la lista de fuentes (o la de músicas), o la cierra si ya lo estaba.
func _alternar_lista(fuentes: bool) -> void:
	var lista := _lista_fuentes if fuentes else _lista_pistas
	if lista.visible:
		_mostrar_lista(null)
	else:
		_mostrar_lista(lista)


## Deja abierta como mucho una lista (null: ninguna). Con una lista abierta,
## el menú solo enseña la sección de esa lista: así cabe en 720 px con
## cualquier fuente.
func _mostrar_lista(lista: Control) -> void:
	_lista_fuentes.visible = lista == _lista_fuentes
	_lista_pistas.visible = lista == _lista_pistas
	for nodo in _seccion_fuente:
		nodo.visible = lista == null or lista == _lista_fuentes
	for nodo in _seccion_musica:
		nodo.visible = lista == null or lista == _lista_pistas
	for nodo in _seccion_efectos:
		nodo.visible = lista == null
	for nodo in _seccion_pantalla:
		nodo.visible = lista == null


func _elegir_fuente(id: String) -> void:
	Ajustes.fijar("fuente", id)
	_mostrar_lista(null)
	refrescar()


func _elegir_pista(id: String) -> void:
	Ajustes.fijar("musica_pista", id)
	_mostrar_lista(null)
	refrescar()


func _on_interruptor(activado: bool, clave: String) -> void:
	if _refrescando:
		return
	Ajustes.fijar(clave, activado)
	if clave == "musica_activa":
		_mostrar_lista(null)
	refrescar()


func _on_pantalla_completa(activada: bool) -> void:
	if _refrescando:
		return
	Pantalla.fijar_preferencia(activada)


func _on_volumen(valor: float, clave: String, etiqueta: Label) -> void:
	if _refrescando:
		return
	Ajustes.fijar(clave, int(valor))
	etiqueta.text = "%d %%" % int(valor)


# ─── Piezas del menú de ajustes ──────────────────────────────────────────────

func _estilo_ajuste(fondo: Color, borde: Color) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = fondo
	estilo.border_color = borde
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(8)
	estilo.content_margin_left = 10
	estilo.content_margin_right = 10
	estilo.content_margin_top = 5
	estilo.content_margin_bottom = 5
	return estilo


func _etiqueta_ajuste(nombre: String, texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.name = nombre
	etiqueta.text = texto
	etiqueta.add_theme_color_override("font_color", COLOR_TITULO_AJUSTE)
	etiqueta.add_theme_font_size_override("font_size", 14)
	return etiqueta


## Botón que abre una lista, con la flecha a la derecha.
func _desplegable(nombre: String) -> Button:
	var boton := Button.new()
	boton.name = nombre
	boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
	boton.add_theme_font_size_override("font_size", 16)
	boton.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	var normal := _estilo_ajuste(Color(1, 1, 1, 0.04), Color(0.85, 0.75, 0.3, 0.6))
	boton.add_theme_stylebox_override("normal", normal)
	boton.add_theme_stylebox_override("pressed", normal)
	boton.add_theme_stylebox_override("hover", _estilo_ajuste(Color(1, 1, 1, 0.09), Color(0.85, 0.75, 0.3, 0.9)))
	boton.add_theme_stylebox_override("disabled", _estilo_ajuste(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.15)))
	var flecha := Label.new()
	flecha.text = "▾"
	flecha.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	flecha.position.x -= 22
	flecha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flecha.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 0.8))
	boton.add_child(flecha)
	return boton


func _lista_ajuste(nombre: String) -> VBoxContainer:
	var lista := VBoxContainer.new()
	lista.name = nombre
	lista.visible = false
	lista.add_theme_constant_override("separation", 2)
	return lista


func _opcion_ajuste(nombre: String) -> Button:
	var opcion := Button.new()
	opcion.name = nombre
	opcion.alignment = HORIZONTAL_ALIGNMENT_LEFT
	opcion.add_theme_font_size_override("font_size", 15)
	opcion.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	opcion.add_theme_stylebox_override("normal", _estilo_ajuste(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.08)))
	opcion.add_theme_stylebox_override("hover", _estilo_ajuste(Color(0.85, 0.75, 0.3, 0.16), Color(0.85, 0.75, 0.3, 0.5)))
	opcion.add_theme_stylebox_override("pressed", _estilo_ajuste(Color(0.85, 0.75, 0.3, 0.16), Color(0.85, 0.75, 0.3, 0.5)))
	return opcion


## La opción elegida lleva ✓; todas, su nota de para qué sirve.
func _marcar_opcion(opcion: Button, elegida: bool, nombre: String, nota: String) -> void:
	opcion.text = ("✓ " if elegida else "") + nombre + "  · " + nota


func _interruptor_ajuste(nombre: String, texto: String) -> CheckButton:
	var interruptor := CheckButton.new()
	interruptor.name = nombre
	interruptor.text = texto
	interruptor.add_theme_font_size_override("font_size", 14)
	interruptor.add_theme_color_override("font_color", COLOR_TITULO_AJUSTE)
	interruptor.add_theme_color_override("font_pressed_color", COLOR_TITULO_AJUSTE)
	interruptor.add_theme_color_override("font_hover_color", COLOR_TITULO_AJUSTE)
	interruptor.add_theme_color_override("font_hover_pressed_color", COLOR_TITULO_AJUSTE)
	return interruptor


## Fila «🔈 [deslizador] 40 %» con el deslizador y la etiqueta con nombre.
func _fila_volumen(nombre_deslizador: String, nombre_etiqueta: String) -> HBoxContainer:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	var icono := Label.new()
	icono.text = "🔈"
	icono.add_theme_font_size_override("font_size", 13)
	fila.add_child(icono)
	var deslizador := HSlider.new()
	deslizador.name = nombre_deslizador
	deslizador.min_value = 0
	deslizador.max_value = 100
	deslizador.step = 5
	deslizador.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deslizador.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(deslizador)
	var etiqueta := Label.new()
	etiqueta.name = nombre_etiqueta
	etiqueta.custom_minimum_size = Vector2(44, 0)
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	etiqueta.add_theme_font_size_override("font_size", 13)
	etiqueta.add_theme_color_override("font_color", COLOR_NOTA_AJUSTE)
	fila.add_child(etiqueta)
	return fila
