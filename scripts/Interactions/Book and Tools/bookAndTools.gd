## Script que gestiona la interfaz del libro interactivo con herramientas
## de lectura (resaltar, subrayar, borrar) y sistema de notas por página.
##
## Soporta dos modos de carga de contenido:
## - Archivo local: si @export ruta_texto apunta a un .txt válido.
## - API remota: si ruta_texto está vacío y typology_filter tiene valor,
##   precarga una lectura aleatoria desde la API al entrar a la escena.
extends Control

signal warning_accepted

# ─── Enumeraciones ──────────────────────────────────────────────────────────────

enum Herramienta {NINGUNA, RESALTAR, SUBRAYAR, BORRAR}

enum ModoVista {LECTURA, NOTAS, COMPILATORIO}

# ─── Constantes ─────────────────────────────────────────────────────────────────

const CARACTERES_POR_PAGINA: int = 700
## Proporción mínima de llenado de una página al fragmentar texto.
const PROPORCION_MINIMA_PAGINA: float = 0.6

## Índice reservado para la portada: no es una página numerada, solo el título.
## El libro abre aquí y "Pag 1" sigue siendo la primera página con texto real.
const PAGINA_PORTADA: int = -1

## Ruta del archivo que almacena el UUID del dispositivo.
const DEVICE_ID_PATH: String = "user://device_id.txt"

## Archivo donde se persisten resaltados, subrayados y notas entre escenas.
const MARCAS_PATH: String = "user://reading_marks.cfg"

## Número máximo de lecturas cuyas marcas se conservan en disco.
const MAX_LECTURAS_GUARDADAS: int = 10

## Nombre del nodo que dibuja el contorno dorado sobre el botón activo.
const NOMBRE_CONTORNO: String = "ContornoSeleccion"

## Panel de guía que se muestra al abrir el libro por primera vez.
const GUIDE_PANEL_SCENE: String = "res://scenes/UI/guide_panel.tscn"

const TOOLS_GUIDE_TITLE: String = "🖍️ Las herramientas del libro"

const TOOLS_GUIDE_BODY: String = """Este libro no es solo para leer: puedes trabajar el texto mientras avanzas.

[color=#f0c050][b]Resaltar[/b][/color] — las frases que resumen la idea del autor.
[color=#f0c050][b]Subrayar[/b][/color] — los nombres, fechas y datos concretos.
[color=#f0c050][b]Notas[/b][/color] — tus dudas y lo que vas entendiendo. Cada página guarda las suyas, y el [b]Compilatorio[/b] las reúne todas.

[b]Para marcar:[/b] pulsa la herramienta —o las teclas [color=#f0c050][b]1[/b][/color], [color=#f0c050][b]2[/b][/color] y [color=#f0c050][b]3[/b][/color]—, arrastra el ratón sobre el texto y suelta. Con [b]Borrar[/b] quitas lo que hayas marcado.

Dejar el texto marcado te ahorrará releerlo entero cuando llegue el desafío."""

# ─── Exports ────────────────────────────────────────────────────────────────────

@export_file("*.tscn") var target_scene_path: String
@export_global_file("*.txt", "*.md") var ruta_texto: String

## Tipología para cargar desde la API (ej: "Descriptivo", "Narrativo", etc.).
## Si ruta_texto está vacío y esto tiene valor, se usa el modo API.
@export var typology_filter: String = ""

## Ruta de la escena del nivel intermedio para Inferencial.
@export_file("*.tscn") var level2_scene_path: String = ""

## Ruta de la escena del nivel intermedio para Crítico.
@export_file("*.tscn") var level3_scene_path: String = ""

## Ruta de la escena de retorno (Lobby).
@export_file("*.tscn") var lobby_scene_path: String = ""

## Ruta de la escena actual (Level 1) para reinicio.
@export_file("*.tscn") var level1_scene_path: String = ""

# ─── Nodos referenciados (@onready) ─────────────────────────────────────────────

@onready var rtl: RichTextLabel = %RichTextLabel
@onready var label_pagina: Label = %LabelPagina
@onready var text_notas: TextEdit = %TextEdit

@onready var resaltar_button: TextureButton = %ResaltarButton
@onready var subrayar_button: TextureButton = %SubrayarButton
@onready var borrar_button: TextureButton = %BorrarButton

@onready var panel_lectura: PanelContainer = %LecturaContainer
@onready var panel_notas: PanelContainer = %NotasContainer
@onready var panel_compilatorio: PanelContainer = %CompilatorioContainer
@onready var rtl_compilatorio: RichTextLabel = %RichTextLabelCompilatorio

@onready var boton_izq: TextureButton = %ButtonLeft
@onready var boton_der: TextureButton = %ButtonRight

@onready var boton_lectura: Button = %ButtonReading
@onready var boton_notas: Button = %ButtonNotes
@onready var boton_compilatorio: Button = %ButtonCompilatorio
@onready var label_notas_guardadas: Label = %LabelNotasGuardadas
@onready var confirm_desafios: ConfirmationDialog = %ConfirmDesafios
@onready var boton_cerrar: Button = %ButtonCerrar

# ─── Estado interno ─────────────────────────────────────────────────────────────

var modo_actual: ModoVista = ModoVista.LECTURA
var herramienta_actual: Herramienta = Herramienta.NINGUNA
var pagina_actual: int = PAGINA_PORTADA
var paginas: Array[String] = []
var estilos_por_pagina: Array[Array] = []
var notas_por_pagina: Dictionary = {}

## Título de la lectura. Se muestra en la portada del libro.
var _titulo_lectura: String = ""

## ID de la lectura actualmente cargada desde la API (-1 si es archivo local).
var _current_reading_id: int = -1

## True mientras se espera la respuesta de la API.
var _is_loading: bool = false

## UUID del dispositivo, usado para marcar lecturas como vistas.
var _user_id: String = ""

## True si el contenido se carga desde la API en lugar de un archivo local.
var _uses_api: bool = false

## Tracking de uso de herramientas para retroalimentación en resultados.
var _used_highlight: bool = false
var _used_underline: bool = false
var _used_notes: bool = false

## True cuando ya hay contenido paginado: antes de eso no hay marcas que guardar.
var _contenido_listo: bool = false

# ─── Ciclo de vida ──────────────────────────────────────────────────────────────

func _ready() -> void:
	panel_notas.visible = false
	panel_compilatorio.visible = false

	rtl.bbcode_enabled = true
	rtl.selection_enabled = true
	_configurar_botones_herramientas()
	_configurar_contornos_seleccion()
	_estilizar_boton_cerrar()

	# Determinar modo de carga
	# Si no tiene typology_filter propio, usar el de GameSession (configurado desde el Lobby)
	if typology_filter.is_empty() and not GameSession.current_typology.is_empty():
		typology_filter = GameSession.current_typology
	_uses_api = ruta_texto.is_empty() and not typology_filter.is_empty()

	if _uses_api:
		_user_id = _get_or_create_user_id()
		_connect_api_signals()
		_preload_from_api()
	else:
		_load_from_file()


func _exit_tree() -> void:
	# Al abandonar el escenario el libro se destruye: es el último momento para
	# conservar lo resaltado, subrayado y anotado.
	_guardar_nota()
	_guardar_marcas()

# ─── Guía de herramientas ───────────────────────────────────────────────────────

## Muestra la guía de herramientas la primera vez que el jugador abre el libro.
## La llama pressE_teleport_book.gd justo después de hacer visible el libro:
## el libro se precarga en _ready() mucho antes de verse, así que no se puede
## disparar desde aquí.
##
## Hasta ahora nadie explicaba estas herramientas y la pantalla de resultados
## reprochaba al final las que no se habían usado.
func show_tools_guide_if_needed() -> void:
	if GameSession.is_hint_seen(GameSession.HINT_BOOK_TOOLS):
		return
	GameSession.mark_hint_seen(GameSession.HINT_BOOK_TOOLS)

	var packed: PackedScene = load(GUIDE_PANEL_SCENE)
	if packed == null:
		push_warning("[BookAndTools] No se pudo cargar el panel de guía.")
		return

	var panel := packed.instantiate()
	# Colgado de la escena y no del libro: el CanvasLayer del libro se oculta
	# al cerrarlo y se llevaría el panel por delante.
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(panel)
	panel.show_message(TOOLS_GUIDE_TITLE, TOOLS_GUIDE_BODY, "¡A leer! ✓")

# ─── Carga desde archivo local (comportamiento original) ───────────────────────

func _load_from_file() -> void:
	var file := FileAccess.open(ruta_texto, FileAccess.READ)
	var texto_completo: String

	if file == null:
		texto_completo = "Loren ipsun"
	else:
		texto_completo = file.get_as_text()

	_titulo_lectura = ruta_texto.get_file().get_basename().capitalize()
	_preparar_contenido(texto_completo)

# ─── Carga desde la API (precarga al entrar a la escena) ───────────────────────

## Conecta las señales del Autoload ReadingAPI para recibir respuestas.
func _connect_api_signals() -> void:
	ReadingAPI.full_reading_loaded.connect(_on_api_reading_received)
	ReadingAPI.request_failed.connect(_on_api_request_failed)


## Solicita una lectura aleatoria COMPLETA de la tipología configurada.
## Muestra un estado de carga mientras espera la respuesta.
## Si GameSession ya tiene una sesión activa con datos cargados
## (lectura restaurada), reutiliza esos datos sin pedir una nueva.
func _preload_from_api() -> void:
	# Si ya hay una sesión activa con lectura cargada, reutilizarla
	# PERO solo si la tipología de la lectura coincide con la del escenario actual
	if GameSession.is_active and not GameSession.current_reading.is_empty():
		var reading_typology: String = str(GameSession.current_reading.get("typology", ""))
		if typology_filter.is_empty() or reading_typology == typology_filter:
			print("[BookAndTools] Reutilizando lectura existente de GameSession (tipología: %s)" % reading_typology)
			_on_api_reading_received(GameSession.current_reading)
			return
		else:
			# La lectura cargada es de otra tipología → no reutilizar, pedir nueva
			print("[BookAndTools] Lectura existente es de '%s' pero escenario requiere '%s', solicitando nueva" % [reading_typology, typology_filter])
			GameSession.is_active = false
			GameSession.current_reading = {}
	_is_loading = true
	_set_loading_state()
	ReadingAPI.get_random_reading_full(typology_filter)


## Muestra un estado visual de carga en el libro.
func _set_loading_state() -> void:
	rtl.text = "[color=black][center]Cargando lectura...[/center][/color]"
	label_pagina.text = "\n\tCargando..."
	boton_izq.visible = false
	boton_der.visible = false


## Callback cuando la API retorna una lectura exitosamente.
func _on_api_reading_received(data: Dictionary) -> void:
	_is_loading = false
	_current_reading_id = int(data.get("id", -1))

	var content: String = str(data.get("content", ""))
	_titulo_lectura = str(data.get("title", "Lectura sin título"))

	if content.is_empty():
		_show_error_state("La lectura no tiene contenido.")
		return

	# Alimentar GameSession con la lectura completa (preguntas incluidas)
	# Solo iniciar nueva sesión si NO hay una activa con esta misma lectura
	if not GameSession.is_active or GameSession.current_reading.get("id", -1) != _current_reading_id:
		GameSession.start_session_with_data(data)
	# Solo reconfigurar escenas si los exports tienen valor (flujo Baños legacy).
	# Para el flujo genérico, las rutas ya fueron configuradas desde el Lobby.
	if not level2_scene_path.is_empty():
		GameSession.configure_scenes(level2_scene_path, level3_scene_path, lobby_scene_path)
		GameSession.level_scenes["Literal"] = level1_scene_path

	_preparar_contenido(content)


## Callback cuando la API falla (red, timeout, etc.).
func _on_api_request_failed(endpoint: String, error: String) -> void:
	# Solo reaccionar si estamos esperando nuestra lectura
	if not _is_loading:
		return
	_is_loading = false
	_show_error_state("No se pudo cargar la lectura.\n%s" % error)
	push_error("[BookAndTools] Fallo en %s: %s" % [endpoint, error])


## Muestra un mensaje de error en el RichTextLabel del libro.
func _show_error_state(message: String) -> void:
	rtl.text = "[color=red][center]%s[/center][/color]" % _escapar_bbcode(message)
	label_pagina.text = "\n\tError"
	boton_izq.visible = false
	boton_der.visible = false


## Pasos comunes tras obtener el texto: paginar, recuperar las marcas guardadas
## y abrir el libro por la portada.
func _preparar_contenido(texto_completo: String) -> void:
	paginas = _fragmentar_texto(texto_completo, CARACTERES_POR_PAGINA)
	_inicializar_estilos()
	_contenido_listo = true
	_restaurar_marcas()
	pagina_actual = PAGINA_PORTADA
	_actualizar_estado_botones()
	_cambiar_modo(ModoVista.LECTURA)

# ─── Identificador de usuario (UUID de dispositivo) ─────────────────────────────

## Obtiene o genera un UUID único por dispositivo, almacenado en user://.
func _get_or_create_user_id() -> String:
	if FileAccess.file_exists(DEVICE_ID_PATH):
		var file := FileAccess.open(DEVICE_ID_PATH, FileAccess.READ)
		if file:
			var uid := file.get_as_text().strip_edges()
			file.close()
			if not uid.is_empty():
				return uid

	# Generar un UUID simple basado en timestamp + aleatorio
	var uid := "device_%d_%d" % [randi(), int(Time.get_unix_time_from_system())]
	var file := FileAccess.open(DEVICE_ID_PATH, FileAccess.WRITE)
	if file:
		file.store_string(uid)
		file.close()
	return uid

# ─── Señales de botones de herramientas ─────────────────────────────────────────

func _on_resaltar_button_pressed() -> void:
	_toggle_herramienta(Herramienta.RESALTAR)


func _on_subrayar_button_pressed() -> void:
	_toggle_herramienta(Herramienta.SUBRAYAR)


func _on_borrar_button_pressed() -> void:
	_toggle_herramienta(Herramienta.BORRAR)


func _on_hecho_button_pressed() -> void:
	_aplicar_formato()
	_show_confirm_dialog()


## Muestra el diálogo de confirmación con animación slide-up en la parte inferior.
func _show_confirm_dialog() -> void:
	var dialog := confirm_desafios

	# Forzar posicionamiento absoluto
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE

	# Configuración de texto
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.min_size = Vector2i(900, 150)

	# Posicionar fuera de pantalla antes de mostrar (evita destello visual)
	dialog.transparent = true
	dialog.position = Vector2i(-10000, -10000)

	# Mostrar (invisible para el usuario)
	dialog.show()

	# Esperar a que Godot calcule el tamaño real
	await get_tree().process_frame
	dialog.reset_size()

	# Posición final: centrado horizontalmente, abajo con margen
	var screen_size := get_viewport().get_visible_rect().size
	var final_x: int = int((screen_size.x - dialog.size.x) / 2)
	var final_y: int = int(screen_size.y - dialog.size.y - 60)

	# Animación slide-up + fade-in
	var offset_y: int = 30
	dialog.position = Vector2i(final_x, final_y + offset_y)

	# Ocultar hijos para hacer fade-in del contenido
	for child in dialog.get_children():
		if child is Control:
			child.modulate.a = 0.0

	# Tween: deslizar hacia arriba + fade-in
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_method(func(y): dialog.position = Vector2i(final_x, y), final_y + offset_y, final_y, 0.3)

	for child in dialog.get_children():
		if child is Control:
			tween.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(0.05)

	# Dejar el foco puesto en "Sí, empezar": show() no dispara el POST_POPUP que
	# normalmente lo coloca, y sin foco el diálogo solo responde al ratón.
	DialogFocus.preparar(dialog)


func _on_confirm_challenges() -> void:
	# Asegurar el guardado de la nota de la página actual por si acaso no se guardó al cambiar de vista
	_guardar_nota()
	_guardar_marcas()

	# Enviar notas a la API
	if AuthManager.is_authenticated and _current_reading_id > 0:
		for page_index in notas_por_pagina.keys():
			var content: String = notas_por_pagina[page_index]
			if not content.strip_edges().is_empty():
				var page_label = "Pág. %d" % (page_index + 1)
				AuthManager.save_note(_current_reading_id, content, -1, page_label)

	# Reportar uso de herramientas a GameSession
	GameSession.tools_used = {
		"highlight": _used_highlight,
		"underline": _used_underline,
		"notes": _used_notes,
	}

	# Registrar fin del tiempo de lectura
	GameSession.end_reading()

	# Marcar como vista si se cargó desde la API
	if _uses_api and _current_reading_id > 0:
		ReadingAPI.mark_seen(_user_id, _current_reading_id)

	# Emitir señal para que el SceneManager maneje la transición
	warning_accepted.emit()
	_on_button_cerrar_pressed()

# ─── Señales de entrada del RichTextLabel ────────────────────────────────────────

func _on_rich_text_label_gui_input(event: InputEvent) -> void:
	if herramienta_actual == Herramienta.NINGUNA:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_aplicar_formato()


## Atajos 1 / 2 / 3 para activar Resaltar, Subrayar y Borrar sin ir al ratón.
## Solo en modo lectura: en Notas el TextEdit se queda las teclas antes de que
## lleguen aquí, pero se comprueba el modo igual por si no tiene el foco.
func _unhandled_key_input(event: InputEvent) -> void:
	if modo_actual != ModoVista.LECTURA or not _libro_visible():
		return

	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_1, KEY_KP_1:
			_toggle_herramienta(Herramienta.RESALTAR)
		KEY_2, KEY_KP_2:
			_toggle_herramienta(Herramienta.SUBRAYAR)
		KEY_3, KEY_KP_3:
			_toggle_herramienta(Herramienta.BORRAR)
		_:
			return

	get_viewport().set_input_as_handled()


## ¿Está el libro realmente en pantalla? El CanvasLayer que lo contiene se
## oculta al cerrarlo, y eso no detiene la entrada de teclado del libro.
func _libro_visible() -> bool:
	if not visible:
		return false
	var canvas := get_parent() as CanvasLayer
	if canvas and not canvas.visible:
		return false
	return true

# ─── Señales de navegación ──────────────────────────────────────────────────────

func _on_button_right_pressed() -> void:
	if pagina_actual < paginas.size() - 1:
		pagina_actual += 1
		_mostrar_pagina()


func _on_button_left_pressed() -> void:
	if pagina_actual > PAGINA_PORTADA:
		pagina_actual -= 1
		_mostrar_pagina()

# ─── Señales de modo de vista ───────────────────────────────────────────────────

func _on_button_reading_pressed() -> void:
	_guardar_nota()
	_cambiar_modo(ModoVista.LECTURA)


func _on_button_notes_pressed() -> void:
	# La portada no es una página anotable: si se piden notas desde ella se pasa
	# a la primera página real, en lugar de abrir un cuaderno sin dueño.
	if pagina_actual == PAGINA_PORTADA and not paginas.is_empty():
		pagina_actual = 0
	_cambiar_modo(ModoVista.NOTAS)
	_cargar_nota()


func _on_button_compilatorio_pressed() -> void:
	_guardar_nota()
	_cambiar_modo(ModoVista.COMPILATORIO)
	_generar_compilatorio()

# ─── Lógica de modos de vista ───────────────────────────────────────────────────

## Centraliza la lógica de cambio entre los tres modos de vista,
## actualizando paneles visibles, botones habilitados y la etiqueta de página.
func _cambiar_modo(nuevo_modo: ModoVista) -> void:
	modo_actual = nuevo_modo

	# Visibilidad de paneles
	panel_lectura.visible = (nuevo_modo == ModoVista.LECTURA)
	panel_notas.visible = (nuevo_modo == ModoVista.NOTAS)
	panel_compilatorio.visible = (nuevo_modo == ModoVista.COMPILATORIO)

	# Estado de botones de modo
	boton_lectura.disabled = (nuevo_modo == ModoVista.LECTURA)
	boton_notas.disabled = (nuevo_modo == ModoVista.NOTAS)
	boton_compilatorio.disabled = (nuevo_modo == ModoVista.COMPILATORIO)

	_marcar_seleccion(boton_lectura, nuevo_modo == ModoVista.LECTURA)
	_marcar_seleccion(boton_notas, nuevo_modo == ModoVista.NOTAS)
	_marcar_seleccion(boton_compilatorio, nuevo_modo == ModoVista.COMPILATORIO)

	# Las herramientas de marcado solo actúan sobre el texto: en Notas y
	# Compilatorio se ocultan y se suelta la que estuviera activa, para que al
	# volver a Lectura no quede una selección fantasma.
	var en_lectura := (nuevo_modo == ModoVista.LECTURA)
	resaltar_button.visible = en_lectura
	subrayar_button.visible = en_lectura
	borrar_button.visible = en_lectura
	if not en_lectura and herramienta_actual != Herramienta.NINGUNA:
		herramienta_actual = Herramienta.NINGUNA
		_actualizar_estado_botones()

	# Actualizar encabezado según el modo
	_refrescar_texto_actual()
	match nuevo_modo:
		ModoVista.LECTURA:
			label_pagina.text = _texto_encabezado_pagina()
		ModoVista.NOTAS:
			label_pagina.text = "\n\tNotas - Pag %d" % [pagina_actual + 1]
		ModoVista.COMPILATORIO:
			label_pagina.text = "\n\tAgrupación de todas las notas"

	_actualizar_flechas()
	_actualizar_indicador_notas()

# ─── Herramientas de formato ────────────────────────────────────────────────────

func _configurar_botones_herramientas() -> void:
	resaltar_button.toggle_mode = true
	subrayar_button.toggle_mode = true
	borrar_button.toggle_mode = true

	resaltar_button.tooltip_text = "Resaltar (tecla 1)"
	subrayar_button.tooltip_text = "Subrayar (tecla 2)"
	borrar_button.tooltip_text = "Borrar marcas (tecla 3)"

	# Distintivo con el atajo de teclado sobre cada herramienta.
	_anadir_distintivo_atajo(resaltar_button, "1")
	_anadir_distintivo_atajo(subrayar_button, "2")
	_anadir_distintivo_atajo(borrar_button, "3")


## Dibuja un número pequeño en la esquina del botón para anunciar su atajo.
func _anadir_distintivo_atajo(boton: TextureButton, tecla: String) -> void:
	if boton == null or boton.has_node("AtajoBadge"):
		return

	var badge := Label.new()
	badge.name = "AtajoBadge"
	badge.text = tecla
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	badge.offset_left = 3.0
	badge.offset_top = 3.0
	badge.offset_right = 21.0
	badge.offset_bottom = 21.0
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color(1, 1, 1))

	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.10, 0.10, 0.16, 0.85)
	estilo.set_corner_radius_all(5)
	estilo.set_border_width_all(1)
	estilo.border_color = Color(0.93, 0.79, 0.28, 0.85)
	badge.add_theme_stylebox_override("normal", estilo)

	boton.add_child(badge)


## Prepara el contorno dorado en los botones que tienen estado activo: las tres
## herramientas de marcado y las tres vistas del libro. Hecho, las flechas de
## página y la ✖ de cerrar son acciones puntuales y no tienen nada que marcar.
func _configurar_contornos_seleccion() -> void:
	for boton in [resaltar_button, subrayar_button, borrar_button,
			boton_lectura, boton_notas, boton_compilatorio]:
		_anadir_contorno_seleccion(boton)


## Añade a un botón el contorno que lo señala como activo. Reutiliza el dorado
## de DialogFocus para que el libro hable el mismo idioma visual que los
## diálogos, pero lo dibuja como nodo hijo: un TextureButton solo cambia de
## textura y no pinta styleboxes de tema, así que un override de "focus" no se
## vería. La textura pulsada ya distingue la herramienta activa, pero es sutil.
func _anadir_contorno_seleccion(boton: BaseButton) -> void:
	if boton == null or boton.has_node(NOMBRE_CONTORNO):
		return

	var contorno := Panel.new()
	contorno.name = NOMBRE_CONTORNO
	contorno.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contorno.visible = false

	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(DialogFocus.COLOR_FOCO, 0.13)
	estilo.set_border_width_all(3)
	estilo.border_color = DialogFocus.COLOR_FOCO
	estilo.set_corner_radius_all(8)
	estilo.set_expand_margin_all(2.0)
	contorno.add_theme_stylebox_override("panel", estilo)

	boton.add_child(contorno)
	contorno.set_anchors_preset(Control.PRESET_FULL_RECT)
	contorno.offset_left = 0.0
	contorno.offset_top = 0.0
	contorno.offset_right = 0.0
	contorno.offset_bottom = 0.0

	# Los hermanos se dibujan en orden de lista, y los botones de vista llevan
	# dentro un sprite que cubre todo el botón. Si el contorno fuera primero, ese
	# sprite lo taparía, así que va el último. El distintivo del atajo se
	# devuelve al final para que siga leyéndose por encima del contorno.
	var badge := boton.get_node_or_null("AtajoBadge")
	if badge != null:
		boton.move_child(badge, -1)


## Enciende o apaga el contorno dorado de un botón.
func _marcar_seleccion(boton: BaseButton, activo: bool) -> void:
	if boton == null:
		return
	var contorno := boton.get_node_or_null(NOMBRE_CONTORNO)
	if contorno is Control:
		(contorno as Control).visible = activo


## Le da al botón de cerrar el mismo lenguaje visual (rojo, redondeado, con
## borde y hover) que la ✖ de los paneles de logros y marcador.
func _estilizar_boton_cerrar() -> void:
	if boton_cerrar == null:
		return

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.08, 0.08, 0.85)
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.75, 0.28, 0.28, 0.9)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.45, 0.13, 0.13, 0.95)
	hover.set_corner_radius_all(10)
	hover.set_border_width_all(2)
	hover.border_color = Color(1.0, 0.4, 0.4, 1.0)

	boton_cerrar.add_theme_stylebox_override("normal", normal)
	boton_cerrar.add_theme_stylebox_override("hover", hover)
	boton_cerrar.add_theme_stylebox_override("pressed", hover)
	boton_cerrar.add_theme_stylebox_override("focus", hover)
	boton_cerrar.add_theme_color_override("font_color", Color(0.95, 0.6, 0.6))
	boton_cerrar.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	boton_cerrar.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	boton_cerrar.add_theme_font_size_override("font_size", 18)
	boton_cerrar.tooltip_text = "Cerrar el libro"


## Vuelca el uso de herramientas en GameSession en cuanto ocurre, y no solo al
## confirmar los desafíos: la lista de objetivos lee de ahí para ir marcando
## los pasos completados mientras el jugador lee.
func _reportar_herramientas() -> void:
	GameSession.tools_used = {
		"highlight": _used_highlight,
		"underline": _used_underline,
		"notes": _used_notes,
	}


func _toggle_herramienta(herramienta: Herramienta) -> void:
	if herramienta_actual == herramienta:
		herramienta_actual = Herramienta.NINGUNA
	else:
		herramienta_actual = herramienta
	_actualizar_estado_botones()


func _actualizar_estado_botones() -> void:
	resaltar_button.button_pressed = (herramienta_actual == Herramienta.RESALTAR)
	subrayar_button.button_pressed = (herramienta_actual == Herramienta.SUBRAYAR)
	borrar_button.button_pressed = (herramienta_actual == Herramienta.BORRAR)

	_marcar_seleccion(resaltar_button, herramienta_actual == Herramienta.RESALTAR)
	_marcar_seleccion(subrayar_button, herramienta_actual == Herramienta.SUBRAYAR)
	_marcar_seleccion(borrar_button, herramienta_actual == Herramienta.BORRAR)


func _aplicar_formato() -> void:
	# La portada no tiene texto marcable.
	if pagina_actual < 0 or pagina_actual >= estilos_por_pagina.size():
		return

	var desde: int = rtl.get_selection_from()
	var hasta: int = rtl.get_selection_to()

	if desde == -1 or hasta == -1 or desde == hasta:
		return

	if desde > hasta:
		var temp := desde
		desde = hasta
		hasta = temp

	var estilos_actuales: Array = estilos_por_pagina[pagina_actual]
	hasta = mini(hasta, estilos_actuales.size())

	for i: int in range(desde, hasta):
		var estado: Dictionary = estilos_actuales[i]
		match herramienta_actual:
			Herramienta.RESALTAR:
				estado["resaltar"] = true
				_used_highlight = true
			Herramienta.SUBRAYAR:
				estado["subrayar"] = true
				_used_underline = true
			Herramienta.BORRAR:
				estado["resaltar"] = false
				estado["subrayar"] = false
			_:
				return

	rtl.deselect()
	_reportar_herramientas()
	_refrescar_texto_actual()

# ─── Paginación y renderizado ────────────────────────────────────────────────────

func _fragmentar_texto(texto: String, tamano_objetivo: int) -> Array[String]:
	var resultado: Array[String] = []
	var inicio := 0
	var largo := texto.length()

	while inicio < largo:
		var fin: int = mini(inicio + tamano_objetivo, largo)

		if fin < largo:
			var corte: int = fin
			while corte > inicio and texto[corte - 1] != " " and texto[corte - 1] != "\n":
				corte -= 1
			if corte > inicio + int(tamano_objetivo * PROPORCION_MINIMA_PAGINA):
				fin = corte

		var pagina := texto.substr(inicio, fin - inicio).strip_edges()
		if not pagina.is_empty():
			resultado.append(pagina)
		inicio = fin

	if resultado.is_empty():
		resultado.append("")

	return resultado


func _inicializar_estilos() -> void:
	estilos_por_pagina.clear()
	for texto in paginas:
		var estilos: Array = []
		for i: int in texto.length():
			estilos.append({"resaltar": false, "subrayar": false})
		estilos_por_pagina.append(estilos)


func _mostrar_pagina() -> void:
	_refrescar_texto_actual()
	label_pagina.text = _texto_encabezado_pagina()
	_actualizar_flechas()
	_actualizar_indicador_notas()


## Encabezado del libro. La portada se anuncia como título y no consume número,
## así que la primera página con texto sigue siendo "Pag 1".
func _texto_encabezado_pagina() -> String:
	if pagina_actual == PAGINA_PORTADA:
		return "\n\tTítulo"
	return "\n\tPag %d de %d" % [pagina_actual + 1, paginas.size()]


## Muestra u oculta las flechas según dónde esté el lector: en la portada no
## hay nada a la izquierda, y en la última página nada a la derecha.
func _actualizar_flechas() -> void:
	if _is_loading or paginas.is_empty() or modo_actual != ModoVista.LECTURA:
		boton_izq.visible = false
		boton_der.visible = false
		return

	boton_izq.visible = pagina_actual > PAGINA_PORTADA
	boton_der.visible = pagina_actual < paginas.size() - 1


func _refrescar_texto_actual() -> void:
	# Si estamos cargando o no hay páginas, no refrescar
	if _is_loading or paginas.is_empty():
		return

	if pagina_actual == PAGINA_PORTADA:
		rtl.text = _construir_portada()
		return

	var texto_base: String = paginas[pagina_actual]
	var estilos_actuales: Array = estilos_por_pagina[pagina_actual]
	var bbcode: String = "[color=black]"
	var resaltar_activo: bool = false
	var subrayar_activo: bool = false

	for i: int in texto_base.length():
		var estado: Dictionary = estilos_actuales[i] as Dictionary
		var debe_resaltar: bool = estado["resaltar"]
		var debe_subrayar: bool = estado["subrayar"]

		# Si cualquier estilo cambia, cerrar TODAS las etiquetas activas
		# y reabrir las necesarias. Esto evita cruces de etiquetas BBCode
		# (ej: [u][bgcolor]...[/u][/bgcolor] → inválido).
		var hay_cambio: bool = (debe_resaltar != resaltar_activo) or (debe_subrayar != subrayar_activo)

		if hay_cambio:
			# Cerrar en orden inverso al de apertura (interior primero)
			if subrayar_activo:
				bbcode += "[/u]"
			if resaltar_activo:
				bbcode += "[/bgcolor]"

			# Reabrir solo las etiquetas que siguen siendo necesarias
			if debe_resaltar:
				bbcode += "[bgcolor=yellow]"
			if debe_subrayar:
				bbcode += "[u]"

			resaltar_activo = debe_resaltar
			subrayar_activo = debe_subrayar

		bbcode += _escapar_bbcode(texto_base[i])

	# Cerrar etiquetas abiertas al final del texto
	if subrayar_activo:
		bbcode += "[/u]"
	if resaltar_activo:
		bbcode += "[/bgcolor]"

	bbcode += "[/color]"
	rtl.text = bbcode


## Portada del libro: título centrado, tipología y número de páginas.
## Es una hoja de cortesía, por eso no entra en la numeración.
func _construir_portada() -> String:
	var titulo := _escapar_bbcode(_titulo_lectura.strip_edges())
	if titulo.is_empty():
		titulo = "Lectura sin título"

	var lineas: Array[String] = []
	lineas.append("[color=black][center]")
	lineas.append("")
	lineas.append("")
	lineas.append("[font_size=32][b]%s[/b][/font_size]" % titulo)
	lineas.append("")
	lineas.append("[color=#8a7455]─────────────[/color]")
	lineas.append("")

	if not typology_filter.is_empty():
		lineas.append("[font_size=17]Texto %s[/font_size]" % _escapar_bbcode(typology_filter))
	lineas.append("[font_size=17]%d páginas[/font_size]" % paginas.size())
	lineas.append("")
	lineas.append("")
	lineas.append("[color=#7a6a4e][font_size=15][i]Pulsa ▶ para empezar a leer[/i][/font_size][/color]")
	lineas.append("[/center][/color]")

	return "\n".join(lineas)


func _escapar_bbcode(texto: String) -> String:
	return texto.replace("[", "[lb]").replace("]", "[rb]")

# ─── Sistema de notas ───────────────────────────────────────────────────────────

func _guardar_nota() -> void:
	if modo_actual == ModoVista.NOTAS and pagina_actual >= 0:
		notas_por_pagina[pagina_actual] = text_notas.text
		if not text_notas.text.strip_edges().is_empty():
			_used_notes = true
		_reportar_herramientas()
		_actualizar_indicador_notas()


## Muestra u oculta el indicador "📝 Notas" según si la página actual tiene
## notas escritas por el jugador.
func _actualizar_indicador_notas() -> void:
	var nota: String = notas_por_pagina.get(pagina_actual, "")
	var tiene_notas := not nota.strip_edges().is_empty()
	label_notas_guardadas.visible = tiene_notas and modo_actual == ModoVista.LECTURA


func _cargar_nota() -> void:
	text_notas.text = notas_por_pagina.get(pagina_actual, "")


func _generar_compilatorio() -> void:
	var texto: String = ""
	var paginas_ordenadas: Array = notas_por_pagina.keys()
	paginas_ordenadas.sort()

	for pagina: int in paginas_ordenadas:
		var nota: String = notas_por_pagina[pagina]
		if not nota.strip_edges().is_empty():
			texto += "[b]Página %d:[/b]\n" % (pagina + 1)
			texto += nota + "\n\n"

	rtl_compilatorio.bbcode_enabled = true
	rtl_compilatorio.text = texto

# ─── Persistencia de marcas y notas ─────────────────────────────────────────────

## Clave con la que se guardan las marcas de esta lectura. Lleva el id del
## jugador para que dos cuentas del mismo equipo no se pisen entre sí.
func _clave_marcas() -> String:
	if _uses_api:
		if _current_reading_id <= 0:
			return ""
		return "u%d_r%d" % [AuthManager.get_user_id(), _current_reading_id]
	if ruta_texto.is_empty():
		return ""
	return "u%d_f%d" % [AuthManager.get_user_id(), abs(ruta_texto.hash())]


## Guarda resaltados, subrayados y notas en disco. Se llama al cerrar el libro
## y al salir del escenario, que es justo donde antes se perdía todo.
func _guardar_marcas() -> void:
	if not _contenido_listo:
		return
	var clave := _clave_marcas()
	if clave.is_empty():
		return

	var cfg := ConfigFile.new()
	cfg.load(MARCAS_PATH)

	var tramos := _serializar_estilos()
	var notas := _notas_serializables()

	if tramos.is_empty() and notas.is_empty():
		# Nada que conservar: no dejamos una entrada vacía ocupando sitio.
		if cfg.has_section(clave):
			cfg.erase_section(clave)
			cfg.save(MARCAS_PATH)
		return

	cfg.set_value(clave, "paginas", paginas.size())
	cfg.set_value(clave, "longitud", _longitud_total())
	cfg.set_value(clave, "tramos", JSON.stringify(tramos))
	cfg.set_value(clave, "notas", JSON.stringify(notas))
	cfg.set_value(clave, "guardado", int(Time.get_unix_time_from_system()))

	_podar_marcas(cfg, clave)
	cfg.save(MARCAS_PATH)


## Restaura las marcas guardadas si corresponden exactamente a este texto.
## Si la lectura cambió en el servidor la paginación ya no coincide, y entonces
## se descartan en vez de pintar tramos en sitios equivocados.
func _restaurar_marcas() -> void:
	var clave := _clave_marcas()
	if clave.is_empty():
		return

	var cfg := ConfigFile.new()
	if cfg.load(MARCAS_PATH) != OK or not cfg.has_section(clave):
		return

	var mismas_paginas := int(cfg.get_value(clave, "paginas", -1)) == paginas.size()
	var misma_longitud := int(cfg.get_value(clave, "longitud", -1)) == _longitud_total()
	if not mismas_paginas or not misma_longitud:
		cfg.erase_section(clave)
		cfg.save(MARCAS_PATH)
		return

	_aplicar_tramos(str(cfg.get_value(clave, "tramos", "[]")))
	_aplicar_notas(str(cfg.get_value(clave, "notas", "{}")))
	_reportar_herramientas()
	print("[BookAndTools] Marcas restauradas para %s" % clave)


func _longitud_total() -> int:
	var total := 0
	for texto in paginas:
		total += texto.length()
	return total


## Comprime los estilos por carácter en tramos [pagina, inicio, fin, banderas],
## donde banderas es 1 = resaltado, 2 = subrayado, 3 = ambos.
func _serializar_estilos() -> Array:
	var tramos: Array = []

	for pagina_idx in estilos_por_pagina.size():
		var estilos: Array = estilos_por_pagina[pagina_idx]
		var inicio := -1
		var banderas_actuales := 0

		for i in estilos.size():
			var estado: Dictionary = estilos[i]
			var banderas := (1 if estado["resaltar"] else 0) | (2 if estado["subrayar"] else 0)
			if banderas != banderas_actuales:
				if banderas_actuales != 0 and inicio >= 0:
					tramos.append([pagina_idx, inicio, i, banderas_actuales])
				inicio = i if banderas != 0 else -1
				banderas_actuales = banderas

		if banderas_actuales != 0 and inicio >= 0:
			tramos.append([pagina_idx, inicio, estilos.size(), banderas_actuales])

	return tramos


func _aplicar_tramos(json_tramos: String) -> void:
	var parseado = JSON.parse_string(json_tramos)
	if not (parseado is Array):
		return

	for tramo in parseado:
		if not (tramo is Array) or tramo.size() < 4:
			continue
		var pagina_idx := int(tramo[0])
		if pagina_idx < 0 or pagina_idx >= estilos_por_pagina.size():
			continue

		var estilos: Array = estilos_por_pagina[pagina_idx]
		var inicio: int = clampi(int(tramo[1]), 0, estilos.size())
		var fin: int = clampi(int(tramo[2]), 0, estilos.size())
		var banderas := int(tramo[3])

		for i in range(inicio, fin):
			var estado: Dictionary = estilos[i]
			if banderas & 1:
				estado["resaltar"] = true
				_used_highlight = true
			if banderas & 2:
				estado["subrayar"] = true
				_used_underline = true


func _notas_serializables() -> Dictionary:
	var salida: Dictionary = {}
	for pagina in notas_por_pagina.keys():
		var contenido: String = str(notas_por_pagina[pagina])
		if not contenido.strip_edges().is_empty():
			salida[str(pagina)] = contenido
	return salida


func _aplicar_notas(json_notas: String) -> void:
	var parseado = JSON.parse_string(json_notas)
	if not (parseado is Dictionary):
		return

	for clave in parseado.keys():
		var pagina := int(str(clave))
		if pagina < 0 or pagina >= paginas.size():
			continue
		var contenido: String = str(parseado[clave])
		notas_por_pagina[pagina] = contenido
		if not contenido.strip_edges().is_empty():
			_used_notes = true


## Conserva solo las MAX_LECTURAS_GUARDADAS entradas más recientes, para que el
## archivo no crezca sin límite a lo largo del curso.
func _podar_marcas(cfg: ConfigFile, clave_actual: String) -> void:
	var secciones := cfg.get_sections()
	if secciones.size() <= MAX_LECTURAS_GUARDADAS:
		return

	var ordenadas: Array = []
	for seccion in secciones:
		if seccion == clave_actual:
			continue
		ordenadas.append({"nombre": seccion, "ts": int(cfg.get_value(seccion, "guardado", 0))})
	ordenadas.sort_custom(func(a, b): return a["ts"] < b["ts"])

	var sobrantes := secciones.size() - MAX_LECTURAS_GUARDADAS
	for i in range(mini(sobrantes, ordenadas.size())):
		cfg.erase_section(ordenadas[i]["nombre"])

# ─── Navegación de escenas ──────────────────────────────────────────────────────

func _cambiar_escena() -> void:
	# Desconectar señales de la API al salir de la escena
	if _uses_api:
		_disconnect_api_signals()
	SceneManager.is_ui_open = false
	SceneManager.transition_to(target_scene_path)


func _on_button_cerrar_pressed() -> void:
	_guardar_nota()
	_guardar_marcas()

	var canvas := get_parent() as CanvasLayer
	if canvas:
		canvas.visible = false
	else:
		visible = false
	SceneManager.is_ui_open = false


## Desconecta las señales de ReadingAPI para evitar callbacks huérfanos.
func _disconnect_api_signals() -> void:
	if ReadingAPI.full_reading_loaded.is_connected(_on_api_reading_received):
		ReadingAPI.full_reading_loaded.disconnect(_on_api_reading_received)
	if ReadingAPI.request_failed.is_connected(_on_api_request_failed):
		ReadingAPI.request_failed.disconnect(_on_api_request_failed)
