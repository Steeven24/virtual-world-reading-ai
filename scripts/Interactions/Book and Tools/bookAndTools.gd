extends Control

@onready var rtl: RichTextLabel = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/LecturaContainer/RichTextLabel
@onready var label_pagina: Label = $PanelContainer/HBoxContainer/Libro/PanelContainer/Label
@onready var resaltar_button: TextureButton = $PanelContainer/HBoxContainer/PanelContainer/Herramientas/ResaltarButton
@onready var subrayar_button: TextureButton = $PanelContainer/HBoxContainer/PanelContainer/Herramientas/SubrayarButton
@onready var borrar_button: TextureButton = $PanelContainer/HBoxContainer/PanelContainer/Herramientas/BorrarButton
@onready var text_notas: TextEdit = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/NotasContainer/TextEdit
@onready var panel_boton_lectura: PanelContainer = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/LecturaContainer
@onready var panel_boton_notas: PanelContainer = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/NotasContainer

@onready var boton_izq: TextureButton = $ButtonLeft
@onready var boton_der: TextureButton = $ButtonRight

@onready var boton_lectura: Button = $ButtonReading
@onready var boton_notas: Button = $ButtonNotes

@export var target_scene: PackedScene
#@export var texto_completo: 
@export_global_file("*.txt", "*.md") var ruta_texto: String
		
#@export var next_scene_path: String
var modo_actual = "lectura"
var notas_por_pagina = {}


enum Herramienta {
	NINGUNA,
	RESALTAR,
	SUBRAYAR,
	BORRAR
}

const CARACTERES_POR_PAGINA := 800

var herramienta_actual: Herramienta = Herramienta.NINGUNA

#var texto_completo := "Texto de la página 1 - Lorem ipsum dolor sit amet facilisis egestas nam, sem vivamus porttitor proin ad integer et litora lobortis imperdiet, turpis a pretium sed ac ultricies mus primis quam viverra. Duis condimentum vitae sollicitudin vestibulum per sagittis, posuere luctus purus quis facilisis.
#
#Lobortis litora pulvinar non dapibus netus duis congue, conubia neque donec praesent tellus sed etiam, eleifend primis ut morbi cum potenti. At vivamus cum conubia fames lacinia scelerisque sodales fermentum aliquam cursus blandit, mi cubilia morbi tempus parturient volutpat hac magna eros. Congue eros venenatis pellentesque auctor potenti euismod platea ligula, vulputate id integer duis urna facilisi magnis dictum, lacinia mi ridiculus laoreet etiam ultrices morbi.
#
#adipiscing elit maecenas suspendisse, ornare ante scelerisque interdum libero dis malesuada morbi penatibus, nunc eu nullam rutrum semper id dignissim placerat. Duis dis condimentum nascetur euismod libero fusce dignissim placerat facilisis egestas nam, sem vivamus porttitor proin ad integer et litora lobortis imperdiet, turpis a pretium sed ac ultricies mus primis quam viverra. Duis condimentum vitae sollicitudin vestibulum per sagittis, posuere luctus purus quis facilisis.
#
#Lobortis litora pulvinar non dapibus netus duis congue, conubia neque donec praesent tellus sed etiam, eleifend primis ut morbi cum potenti. At vivamus cum conubia fames lacinia scelerisque sodales fermentum aliquam cursus blandit, mi cubilia morbi tempus parturient volutpat hac magna eros. Congue eros venenatis pellentesque auctor potenti euismod platea ligula, vulputate id integer duis urna facilisi magnis dictum, lacinia mi ridiculus laoreet etiam ultrices morbi.
#
#ipsum dolor sit amet consectetur adipiscing elit maecenas suspendisse, ornare ante scelerisque interdum libero dis malesuada morbi penatibus, nunc eu nullam rutrum semper id dignissim placerat. Duis dis condimentum nascetur euismod libero fusce dignissim placerat facilisis egestas nam, sem vivamus porttitor proin ad integer et litora lobortis imperdiet, turpis a pretium sed ac ultricies mus primis quam viverra. Duis condimentum vitae sollicitudin vestibulum per sagittis, posuere luctus purus quis facilisis.
#
#Lobortis litora pulvinar non dapibus netus duis congue, conubia fames lacinia scelerisque sodales fermentum aliquam cursus blandit, mi cubilia morbi tempus parturient volutpat hac magna eros. Congue eros venenatis pellentesque auctor potenti euismod platea ligula, vulputate id integer duis urna facilisi magnis dictum, lacinia mi ridiculus laoreet etiam ultrices morbi."

var paginas: Array[String] = []

var pagina_actual: int = 0
var estilos_por_pagina: Array[Array] = []

func _ready() -> void:
	$PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/NotasContainer.visible = false
	var file = FileAccess.open(ruta_texto, FileAccess.READ)
	var texto_completo = file.get_as_text()
	#$RichTextLabel.text = texto_completo # O el nodo donde muestres el texto
	
	
	rtl.bbcode_enabled = true
	rtl.selection_enabled = true
	#rtl.theme_override_colors.default_color = Color.BLACK
	_configurar_botones_herramientas()
	paginas = _fragmentar_texto(texto_completo, CARACTERES_POR_PAGINA)
	_inicializar_estilos()
	_actualizar_estado_botones()
	mostrar_pagina()


func _on_resaltar_button_pressed() -> void:
	_toggle_herramienta(Herramienta.RESALTAR)


func _on_subrayar_button_pressed() -> void:
	_toggle_herramienta(Herramienta.SUBRAYAR)


func _on_borrar_button_pressed() -> void:
	_toggle_herramienta(Herramienta.BORRAR)
	

func _on_hecho_button_pressed() -> void:
	aplicar_formato()
	if target_scene != null:
		get_tree().change_scene_to_packed(target_scene)
	else:
		print("Error: No has asignado una ruta de escena en el inspector.")
	

func _on_rich_text_label_gui_input(event: InputEvent) -> void:
	if herramienta_actual == Herramienta.NINGUNA:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			aplicar_formato()

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
	resaltar_button.button_pressed = herramienta_actual == Herramienta.RESALTAR
	subrayar_button.button_pressed = herramienta_actual == Herramienta.SUBRAYAR
	borrar_button.button_pressed = herramienta_actual == Herramienta.BORRAR

func _fragmentar_texto(texto: String, tamano_objetivo: int) -> Array[String]:
	var resultado: Array[String] = []
	var inicio := 0
	var largo := texto.length()

	while inicio < largo:
		var fin: int = int(min(inicio + tamano_objetivo, largo))

		if fin < largo:
			var corte: int = fin
			while corte > inicio and texto[corte - 1] != " " and texto[corte - 1] != "\n":
				corte -= 1

			if corte > inicio + int(tamano_objetivo * 0.6):
				fin = corte

		var pagina := texto.substr(inicio, fin - inicio).strip_edges()
		if not pagina.is_empty():
			resultado.append(pagina)

		inicio = fin

	while resultado.is_empty():
		resultado.append("")

	return resultado

func _inicializar_estilos() -> void:
	estilos_por_pagina.clear()
	for texto in paginas:
		var estilos: Array = []
		for i in texto.length():
			estilos.append({"resaltar": false, "subrayar": false})
		estilos_por_pagina.append(estilos)

func aplicar_formato() -> void:
	# Forzamos el tipo int explícitamente
	var desde: int = rtl.get_selection_from()
	var hasta: int = rtl.get_selection_to()

	if desde == -1 or hasta == -1 or desde == hasta:
		return

	if desde > hasta:
		var temp := desde
		desde = hasta
		hasta = temp

	# Aquí estaba el problema: especificamos que es un Array de Diccionarios
	var estilos_actuales: Array = estilos_por_pagina[pagina_actual]
	hasta = min(hasta, estilos_actuales.size())

	# Especificamos que 'i' es un int
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

func _escapar_bbcode(texto: String) -> String:
	return texto.replace("[", "[lb]").replace("]", "[rb]")

func _refrescar_texto_actual() -> void:
	var texto_base: String = paginas[pagina_actual]
	var estilos_actuales: Array = estilos_por_pagina[pagina_actual]
	var bbcode: String = "[color=black]"
	var resaltar_activo: bool = false
	var subrayar_activo: bool = false

	for i: int in texto_base.length():
		# Casteamos el elemento del array a Dictionary explícitamente
		var estado: Dictionary = estilos_actuales[i] as Dictionary
		var debe_resaltar: bool = estado["resaltar"]
		var debe_subrayar: bool = estado["subrayar"]

		if subrayar_activo and not debe_subrayar:
			bbcode += "[/u]"
			subrayar_activo = false

		if resaltar_activo and not debe_resaltar:
			bbcode += "[/bgcolor]"
			resaltar_activo = false

		if not resaltar_activo and debe_resaltar:
			bbcode += "[bgcolor=yellow]"
			resaltar_activo = true

		if not subrayar_activo and debe_subrayar:
			bbcode += "[u]"
			subrayar_activo = true

		bbcode += _escapar_bbcode(texto_base[i])

	if subrayar_activo: bbcode += "[/u]"
	if resaltar_activo: bbcode += "[/bgcolor]"

	bbcode += "[/color]"
	rtl.text = bbcode

func mostrar_pagina():
	_refrescar_texto_actual()
	label_pagina.text = "
	Pag %d de %d" % [pagina_actual + 1, paginas.size()]

func mostrar_notas():
	_refrescar_texto_actual()
	label_pagina.text = "
	Notas - Pag %d" % [pagina_actual + 1]
	
func guardar_nota():
	text_notas.text
	notas_por_pagina[pagina_actual] = text_notas.text

func aparecer_botones_izq_y_der():
	boton_der.visible = true
	boton_izq.visible = true
	
func ocultar_botones_izq_y_der():
	boton_der.visible = false
	boton_izq.visible = false

func cargar_nota():
	if pagina_actual in notas_por_pagina:
		text_notas.text = notas_por_pagina[pagina_actual]
	else:
		text_notas.text = ""

func _on_button_right_pressed() -> void:
	if pagina_actual < paginas.size() - 1:
		pagina_actual += 1
		mostrar_pagina()


func _on_button_left_pressed() -> void:
	if pagina_actual > 0:
		pagina_actual -= 1
		mostrar_pagina()


func _on_button_notes_pressed() -> void:
	boton_notas.disabled = true
	boton_lectura.disabled = false
	ocultar_botones_izq_y_der()
	mostrar_notas()
	cargar_nota()
	modo_actual = "notas"
	panel_boton_lectura.visible = false
	panel_boton_notas.visible = true
	
	
func _on_button_reading_pressed() -> void:
	boton_notas.disabled = false
	boton_lectura.disabled = true
	aparecer_botones_izq_y_der()
	guardar_nota()
	modo_actual = "lectura"
	mostrar_pagina()
	panel_boton_lectura.visible = true
	panel_boton_notas.visible = false
	
	
	
	
	
	
	
