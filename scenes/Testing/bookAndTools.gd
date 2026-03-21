extends Control

# 📖 Referencias
@onready var rtl = $PanelContainer/HBoxContainer/Libro/PanelContainer/MarginContainer/RichTextLabel
@onready var label_pagina = $PanelContainer/HBoxContainer/Libro/PanelContainer/Label

# 🧠 Estado
var herramienta_actual = "ninguna"

var paginas = [
	"Texto de la página 1 - Lorem ipsum dolor sit amet consectetur adipiscing elit maecenas suspendisse, ornare ante scelerisque interdum libero dis malesuada morbi penatibus, nunc eu nullam rutrum semper id dignissim placerat. Duis dis condimentum nascetur euismod libero fusce dignissim placerat facilisis egestas nam, sem vivamus porttitor proin ad integer et litora lobortis imperdiet, turpis a pretium sed ac ultricies mus primis quam viverra. Duis condimentum vitae sollicitudin vestibulum per sagittis, posuere luctus purus quis facilisis.

Lobortis litora pulvinar non dapibus netus duis congue, conubia neque donec praesent tellus sed etiam, eleifend primis ut morbi cum potenti. At vivamus cum conubia fames lacinia scelerisque sodales fermentum aliquam cursus blandit, mi cubilia morbi tempus parturient volutpat hac magna eros. Congue eros venenatis pellentesque auctor potenti euismod platea ligula, vulputate id integer duis urna facilisi magnis dictum, lacinia mi ridiculus laoreet etiam ultrices morbi.",
	"Texto de la página 2 - adipiscing elit maecenas suspendisse, ornare ante scelerisque interdum libero dis malesuada morbi penatibus, nunc eu nullam rutrum semper id dignissim placerat. Duis dis condimentum nascetur euismod libero fusce dignissim placerat facilisis egestas nam, sem vivamus porttitor proin ad integer et litora lobortis imperdiet, turpis a pretium sed ac ultricies mus primis quam viverra. Duis condimentum vitae sollicitudin vestibulum per sagittis, posuere luctus purus quis facilisis.

Lobortis litora pulvinar non dapibus netus duis congue, conubia neque donec praesent tellus sed etiam, eleifend primis ut morbi cum potenti. At vivamus cum conubia fames lacinia scelerisque sodales fermentum aliquam cursus blandit, mi cubilia morbi tempus parturient volutpat hac magna eros. Congue eros venenatis pellentesque auctor potenti euismod platea ligula, vulputate id integer duis urna facilisi magnis dictum, lacinia mi ridiculus laoreet etiam ultrices morbi.",
    "Texto de la página 3 - ipsum dolor sit amet consectetur adipiscing elit maecenas suspendisse, ornare ante scelerisque interdum libero dis malesuada morbi penatibus, nunc eu nullam rutrum semper id dignissim placerat. Duis dis condimentum nascetur euismod libero fusce dignissim placerat facilisis egestas nam, sem vivamus porttitor proin ad integer et litora lobortis imperdiet, turpis a pretium sed ac ultricies mus primis quam viverra. Duis condimentum vitae sollicitudin vestibulum per sagittis, posuere luctus purus quis facilisis.

Lobortis litora pulvinar non dapibus netus duis congue, conubia neque donec praesent tellus sed etiam, eleifend primis ut morbi cum potenti. At vivamus cum conubia fames lacinia scelerisque sodales fermentum aliquam cursus blandit, mi cubilia morbi tempus parturient volutpat hac magna eros. Congue eros venenatis pellentesque auctor potenti euismod platea ligula, vulputate id integer duis urna facilisi magnis dictum, lacinia mi ridiculus laoreet etiam ultrices morbi."
]

var pagina_actual = 0

func _ready():
	rtl.bbcode_enabled = true
	rtl.selection_enabled = true
	mostrar_pagina()

func _on_resaltar_button_pressed() -> void:
	herramienta_actual = "resaltar"


func _on_subrayar_button_pressed() -> void:
	herramienta_actual = "subrayar"


func _on_borrar_button_pressed() -> void:
	herramienta_actual = "borrar"
	aplicar_formato()
	
	
func _on_hecho_button_pressed() -> void:
	aplicar_formato()

func aplicar_formato():
	var seleccionado = rtl.get_selected_text()
	
	if seleccionado == "":
		return
	
	var texto_completo = rtl.text
	
	if herramienta_actual == "resaltar":
		seleccionado = "[bgcolor=yellow]" + seleccionado + "[/bgcolor]"
	
	elif herramienta_actual == "subrayar":
		seleccionado = "[u]" + seleccionado + "[/u]"
	
	elif herramienta_actual == "borrar":
		seleccionado = seleccionado.replace("[bgcolor=yellow]", "")
		seleccionado = seleccionado.replace("[/bgcolor]", "")
		seleccionado = seleccionado.replace("[u]", "")
		seleccionado = seleccionado.replace("[/u]", "")
	
	rtl.text = texto_completo.replace(rtl.get_selected_text(), seleccionado)

func mostrar_pagina():
	rtl.text = paginas[pagina_actual]
	label_pagina.text = "Pag %d de %d" % [pagina_actual + 1, paginas.size()]


func _on_button_right_pressed() -> void:
	if pagina_actual < paginas.size() - 1:
		pagina_actual += 1
		mostrar_pagina()


func _on_button_left_pressed() -> void:
	if pagina_actual > 0:
		pagina_actual -= 1
		mostrar_pagina()
