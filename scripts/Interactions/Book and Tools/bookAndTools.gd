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

## Ruta del archivo que almacena el UUID del dispositivo.
const DEVICE_ID_PATH: String = "user://device_id.txt"

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

@onready var rtl: RichTextLabel = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/LecturaContainer/RichTextLabel
@onready var label_pagina: Label = $PanelContainer/HBoxContainer/Libro/PanelContainer/Label
@onready var text_notas: TextEdit = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/NotasContainer/TextEdit

@onready var resaltar_button: TextureButton = $PanelContainer/HBoxContainer/PanelContainer/Herramientas/ResaltarButton
@onready var subrayar_button: TextureButton = $PanelContainer/HBoxContainer/PanelContainer/Herramientas/SubrayarButton
@onready var borrar_button: TextureButton = $PanelContainer/HBoxContainer/PanelContainer/Herramientas/BorrarButton

@onready var panel_lectura: PanelContainer = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/LecturaContainer
@onready var panel_notas: PanelContainer = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/NotasContainer
@onready var panel_compilatorio: PanelContainer = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/CompilatorioContainer
@onready var rtl_compilatorio: RichTextLabel = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/CompilatorioContainer/RichTextLabel

@onready var boton_izq: TextureButton = $ButtonLeft
@onready var boton_der: TextureButton = $ButtonRight

@onready var boton_lectura: Button = $ButtonReading
@onready var boton_notas: Button = $ButtonNotes
@onready var boton_compilatorio: Button = $ButtonCompilatorio
@onready var label_notas_guardadas: Label = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer2/LabelNotasGuardadas
@onready var confirm_desafios: ConfirmationDialog = %ConfirmDesafios

# ─── Estado interno ─────────────────────────────────────────────────────────────

var modo_actual: ModoVista = ModoVista.LECTURA
var herramienta_actual: Herramienta = Herramienta.NINGUNA
var pagina_actual: int = 0
var paginas: Array[String] = []
var estilos_por_pagina: Array[Array] = []
var notas_por_pagina: Dictionary = {}

## ID de la lectura actualmente cargada desde la API (-1 si es archivo local).
var _current_reading_id: int = -1

## True mientras se espera la respuesta de la API.
var _is_loading: bool = false

## UUID del dispositivo, usado para marcar lecturas como vistas.
## Será reemplazado por el ID del usuario cuando se implemente el login.
var _user_id: String = ""

## True si el contenido se carga desde la API en lugar de un archivo local.
var _uses_api: bool = false

## Tracking de uso de herramientas para retroalimentación en resultados.
var _used_highlight: bool = false
var _used_underline: bool = false
var _used_notes: bool = false

# ─── Ciclo de vida ──────────────────────────────────────────────────────────────

func _ready() -> void:
	panel_notas.visible = false
	panel_compilatorio.visible = false

	rtl.bbcode_enabled = true
	rtl.selection_enabled = true
	_configurar_botones_herramientas()

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

# ─── Carga desde archivo local (comportamiento original) ───────────────────────

func _load_from_file() -> void:
	var file := FileAccess.open(ruta_texto, FileAccess.READ)
	var texto_completo := file.get_as_text()

	paginas = _fragmentar_texto(texto_completo, CARACTERES_POR_PAGINA)
	_inicializar_estilos()
	_actualizar_estado_botones()
	pagina_actual = 0
	_cambiar_modo(ModoVista.LECTURA)

# ─── Carga desde la API (precarga al entrar a la escena) ───────────────────────

## Conecta las señales del Autoload ReadingAPI para recibir respuestas.
func _connect_api_signals() -> void:
	ReadingAPI.full_reading_loaded.connect(_on_api_reading_received)
	ReadingAPI.request_failed.connect(_on_api_request_failed)


## Solicita una lectura aleatoria COMPLETA de la tipología configurada.
## Muestra un estado de carga mientras espera la respuesta.
func _preload_from_api() -> void:
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
	if content.is_empty():
		_show_error_state("La lectura no tiene contenido.")
		return

	# Alimentar GameSession con la lectura completa (preguntas incluidas)
	GameSession.start_session_with_data(data)
	# Solo reconfigurar escenas si los exports tienen valor (flujo Baños legacy).
	# Para el flujo genérico, las rutas ya fueron configuradas desde el Lobby.
	if not level2_scene_path.is_empty():
		GameSession.configure_scenes(level2_scene_path, level3_scene_path, lobby_scene_path)
		GameSession.level_scenes["Literal"] = level1_scene_path

	paginas = _fragmentar_texto(content, CARACTERES_POR_PAGINA)
	_inicializar_estilos()
	pagina_actual = 0
	_actualizar_estado_botones()
	_cambiar_modo(ModoVista.LECTURA)


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


# ─── Identificador de usuario (UUID de dispositivo) ─────────────────────────────

## Obtiene o genera un UUID único por dispositivo, almacenado en user://.
## Cuando se implemente el sistema de login, este valor será reemplazado
## por el ID del usuario autenticado.
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


func _on_confirm_challenges() -> void:
	# Reportar uso de herramientas a GameSession
	GameSession.tools_used = {
		"highlight": _used_highlight,
		"underline": _used_underline,
		"notes": _used_notes,
	}
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

# ─── Señales de navegación ──────────────────────────────────────────────────────

func _on_button_right_pressed() -> void:
	if pagina_actual < paginas.size() - 1:
		pagina_actual += 1
		_mostrar_pagina()


func _on_button_left_pressed() -> void:
	if pagina_actual > 0:
		pagina_actual -= 1
		_mostrar_pagina()

# ─── Señales de modo de vista ───────────────────────────────────────────────────

func _on_button_reading_pressed() -> void:
	_guardar_nota()
	_cambiar_modo(ModoVista.LECTURA)


func _on_button_notes_pressed() -> void:
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

	# Flechas de navegación solo visibles en modo lectura
	var mostrar_flechas := (nuevo_modo == ModoVista.LECTURA)
	boton_izq.visible = mostrar_flechas
	boton_der.visible = mostrar_flechas

	# Actualizar encabezado según el modo
	_refrescar_texto_actual()
	match nuevo_modo:
		ModoVista.LECTURA:
			label_pagina.text = "\n\tPag %d de %d" % [pagina_actual + 1, paginas.size()]
		ModoVista.NOTAS:
			label_pagina.text = "\n\tNotas - Pag %d" % [pagina_actual + 1]
		ModoVista.COMPILATORIO:
			label_pagina.text = "\n\tAgrupación de todas las notas"

	_actualizar_indicador_notas()

# ─── Herramientas de formato ────────────────────────────────────────────────────

func _configurar_botones_herramientas() -> void:
	resaltar_button.toggle_mode = true
	subrayar_button.toggle_mode = true
	borrar_button.toggle_mode = true


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


func _aplicar_formato() -> void:
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
	label_pagina.text = "\n\tPag %d de %d" % [pagina_actual + 1, paginas.size()]
	_actualizar_indicador_notas()


func _refrescar_texto_actual() -> void:
	# Si estamos cargando o no hay páginas, no refrescar
	if _is_loading or paginas.is_empty():
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


func _escapar_bbcode(texto: String) -> String:
	return texto.replace("[", "[lb]").replace("]", "[rb]")

# ─── Sistema de notas ───────────────────────────────────────────────────────────

func _guardar_nota() -> void:
	if modo_actual == ModoVista.NOTAS:
		notas_por_pagina[pagina_actual] = text_notas.text
		if not text_notas.text.strip_edges().is_empty():
			_used_notes = true
		_actualizar_indicador_notas()


## Muestra u oculta el indicador "📝 Notas guardadas" según si la página
## actual tiene notas escritas por el jugador.
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

# ─── Navegación de escenas ──────────────────────────────────────────────────────

func _cambiar_escena() -> void:
	# Desconectar señales de la API al salir de la escena
	if _uses_api:
		_disconnect_api_signals()
	SceneManager.is_ui_open = false
	SceneManager.transition_to(target_scene_path)

func _on_button_cerrar_pressed() -> void:
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
