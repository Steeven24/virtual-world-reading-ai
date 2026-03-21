extends Control

@onready var rtl = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/RichTextLabel
@onready var label_pagina = $PanelContainer/HBoxContainer/Libro/PanelContainer/Label

enum Herramienta {
	NINGUNA,
	RESALTAR,
	SUBRAYAR,
	BORRAR
}

var herramienta_actual: Herramienta = Herramienta.NINGUNA

var paginas = [
	"Texto de la página 1 - Lorem ipsum dolor sit amet  facilisis egestas nam, sem vivamus porttitor proin ad integer et litora lobortis imperdiet, turpis a pretium sed ac ultricies mus primis quam viverra. Duis condimentum vitae sollicitudin vestibulum per sagittis, posuere luctus purus quis facilisis.

Lobortis litora pulvinar non dapibus netus duis congue, conubia neque donec praesent tellus sed etiam, eleifend primis ut morbi cum potenti. At vivamus cum conubia fames lacinia scelerisque sodales fermentum aliquam cursus blandit, mi cubilia morbi tempus parturient volutpat hac magna eros. Congue eros venenatis pellentesque auctor potenti euismod platea ligula, vulputate id integer duis urna facilisi magnis dictum, lacinia mi ridiculus laoreet etiam ultrices morbi.",
	"Texto de la página 2 - adipiscing elit maecenas suspendisse, ornare ante scelerisque interdum libero dis malesuada morbi penatibus, nunc eu nullam rutrum semper id dignissim placerat. Duis dis condimentum nascetur euismod libero fusce dignissim placerat facilisis egestas nam, sem vivamus porttitor proin ad integer et litora lobortis imperdiet, turpis a pretium sed ac ultricies mus primis quam viverra. Duis condimentum vitae sollicitudin vestibulum per sagittis, posuere luctus purus quis facilisis.

Lobortis litora pulvinar non dapibus netus duis congue, conubia neque donec praesent tellus sed etiam, eleifend primis ut morbi cum potenti. At vivamus cum conubia fames lacinia scelerisque sodales fermentum aliquam cursus blandit, mi cubilia morbi tempus parturient volutpat hac magna eros. Congue eros venenatis pellentesque auctor potenti euismod platea ligula, vulputate id integer duis urna facilisi magnis dictum, lacinia mi ridiculus laoreet etiam ultrices morbi.",
    "Texto de la página 3 - ipsum dolor sit amet consectetur adipiscing elit maecenas suspendisse, ornare ante scelerisque interdum libero dis malesuada morbi penatibus, nunc eu nullam rutrum semper id dignissim placerat. Duis dis condimentum nascetur euismod libero fusce dignissim placerat facilisis egestas nam, sem vivamus porttitor proin ad integer et litora lobortis imperdiet, turpis a pretium sed ac ultricies mus primis quam viverra. Duis condimentum vitae sollicitudin vestibulum per sagittis, posuere luctus purus quis facilisis.

Lobortis litora pulvinar non dapibus netus duis congue, conubiconubia fames lacinia scelerisque sodales fermentum aliquam cursus blandit, mi cubilia morbi tempus parturient volutpat hac magna eros. Congue eros venenatis pellentesque auctor potenti euismod platea ligula, vulputate id integer duis urna facilisi magnis dictum, lacinia mi ridiculus laoreet etiam ultrices morbi."
]

var pagina_actual = 0
var estilos_por_pagina: Array = []

func _ready():
	rtl.bbcode_enabled = true
	rtl.selection_enabled = true
	#rtl.theme_override_colors.default_color = Color.BLACK
	_inicializar_estilos()
	mostrar_pagina()

func _on_resaltar_button_pressed() -> void:
	herramienta_actual = Herramienta.RESALTAR


func _on_subrayar_button_pressed() -> void:
	herramienta_actual = Herramienta.SUBRAYAR


func _on_borrar_button_pressed() -> void:
	herramienta_actual = Herramienta.BORRAR
	aplicar_formato()
	
	
func _on_hecho_button_pressed() -> void:
	aplicar_formato()

func _inicializar_estilos() -> void:
	estilos_por_pagina.clear()
	for texto in paginas:
		var estilos: Array = []
		for i in texto.length():
			estilos.append({"resaltar": false, "subrayar": false})
		estilos_por_pagina.append(estilos)

func aplicar_formato() -> void:
	var desde: int = rtl.get_selection_from()
	var hasta: int = rtl.get_selection_to()

	if desde == -1 or hasta == -1 or desde == hasta:
		return

	if desde > hasta:
		var temp := desde
		desde = hasta
		hasta = temp

	var estilos_actuales: Array = estilos_por_pagina[pagina_actual]
	hasta = min(hasta, estilos_actuales.size())

	for i in range(desde, hasta):
		match herramienta_actual:
			Herramienta.RESALTAR:
				estilos_actuales[i]["resaltar"] = true
			Herramienta.SUBRAYAR:
				estilos_actuales[i]["subrayar"] = true
			Herramienta.BORRAR:
				estilos_actuales[i]["resaltar"] = false
				estilos_actuales[i]["subrayar"] = false
			_:
				return

	rtl.deselect()
	_refrescar_texto_actual()

func _escapar_bbcode(texto: String) -> String:
	return texto.replace("[", "[lb]").replace("]", "[rb]")

func _refrescar_texto_actual() -> void:
	var texto_base: String = paginas[pagina_actual]
	var estilos_actuales: Array = estilos_por_pagina[pagina_actual]
	var bbcode := "[color=black]"
	var resaltar_activo := false
	var subrayar_activo := false

	for i in texto_base.length():
		var estado: Dictionary = estilos_actuales[i]
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

	if subrayar_activo:
		bbcode += "[/u]"
	if resaltar_activo:
		bbcode += "[/bgcolor]"

	bbcode += "[/color]"
	rtl.text = bbcode

func mostrar_pagina():
	_refrescar_texto_actual()
	label_pagina.text = "
	Pag %d de %d" % [pagina_actual + 1, paginas.size()]


func _on_button_right_pressed() -> void:
	if pagina_actual < paginas.size() - 1:
		pagina_actual += 1
		mostrar_pagina()


func _on_button_left_pressed() -> void:
	if pagina_actual > 0:
		pagina_actual -= 1
		mostrar_pagina()
