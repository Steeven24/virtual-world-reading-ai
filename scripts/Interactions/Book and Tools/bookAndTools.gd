## Script que gestiona la interfaz del libro interactivo con herramientas
## de lectura (resaltar, subrayar, borrar) y sistema de notas por página.
extends Control

# ─── Enumeraciones ──────────────────────────────────────────────────────────────

enum Herramienta {NINGUNA, RESALTAR, SUBRAYAR, BORRAR}

enum ModoVista {LECTURA, NOTAS, COMPILATORIO}

# ─── Constantes ─────────────────────────────────────────────────────────────────

const CARACTERES_POR_PAGINA: int = 800
## Proporción mínima de llenado de una página al fragmentar texto.
const PROPORCION_MINIMA_PAGINA: float = 0.6

# ─── Exports ────────────────────────────────────────────────────────────────────

@export_file("*.tscn") var target_scene_path: String
@export_global_file("*.txt", "*.md") var ruta_texto: String

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

# ─── Estado interno ─────────────────────────────────────────────────────────────

var modo_actual: ModoVista = ModoVista.LECTURA
var herramienta_actual: Herramienta = Herramienta.NINGUNA
var pagina_actual: int = 0
var paginas: Array[String] = []
var estilos_por_pagina: Array[Array] = []
var notas_por_pagina: Dictionary = {}

# ─── Ciclo de vida ──────────────────────────────────────────────────────────────

func _ready() -> void:
	panel_notas.visible = false
	panel_compilatorio.visible = false

	var file := FileAccess.open(ruta_texto, FileAccess.READ)
	var texto_completo := file.get_as_text()

	rtl.bbcode_enabled = true
	rtl.selection_enabled = true
	_configurar_botones_herramientas()
	paginas = _fragmentar_texto(texto_completo, CARACTERES_POR_PAGINA)
	_inicializar_estilos()
	_actualizar_estado_botones()
	_mostrar_pagina()

# ─── Señales de botones de herramientas ─────────────────────────────────────────

func _on_resaltar_button_pressed() -> void:
	_toggle_herramienta(Herramienta.RESALTAR)


func _on_subrayar_button_pressed() -> void:
	_toggle_herramienta(Herramienta.SUBRAYAR)


func _on_borrar_button_pressed() -> void:
	_toggle_herramienta(Herramienta.BORRAR)


func _on_hecho_button_pressed() -> void:
	_aplicar_formato()
	_cambiar_escena()

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
			Herramienta.SUBRAYAR:
				estado["subrayar"] = true
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


func _refrescar_texto_actual() -> void:
	var texto_base: String = paginas[pagina_actual]
	var estilos_actuales: Array = estilos_por_pagina[pagina_actual]
	var bbcode: String = "[color=black]"
	var resaltar_activo: bool = false
	var subrayar_activo: bool = false

	for i: int in texto_base.length():
		var estado: Dictionary = estilos_actuales[i] as Dictionary
		var debe_resaltar: bool = estado["resaltar"]
		var debe_subrayar: bool = estado["subrayar"]

		# Cerrar etiquetas que ya no aplican (orden inverso al de apertura)
		if subrayar_activo and not debe_subrayar:
			bbcode += "[/u]"
			subrayar_activo = false
		if resaltar_activo and not debe_resaltar:
			bbcode += "[/bgcolor]"
			resaltar_activo = false

		# Abrir etiquetas necesarias
		if not resaltar_activo and debe_resaltar:
			bbcode += "[bgcolor=yellow]"
			resaltar_activo = true
		if not subrayar_activo and debe_subrayar:
			bbcode += "[u]"
			subrayar_activo = true

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
	notas_por_pagina[pagina_actual] = text_notas.text


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
	SceneManager.transition_to(target_scene_path)
