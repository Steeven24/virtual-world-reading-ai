extends Node
## Prueba temporal (Task 16): resaltar y subrayar marcan toda la selección,
## también su última letra. get_selection_to() da el índice de la última letra
## seleccionada, no el de la siguiente.
var _fallos := 0

const LIBRO := "res://scenes/Book and Tools/book and tools.tscn"
const TEXTO := "El faro de la isla llevaba años apagado cuando Marta subió por primera vez la escalera de caracol.\n\nAquella noche encendió la lámpara y el pueblo entero salió a mirar."


func _ready() -> void:
	AuthManager.is_authenticated = false
	await _probar()
	print("TEST OK" if _fallos == 0 else "TEST FALLO: %d comprobaciones" % _fallos)
	get_tree().quit(1 if _fallos else 0)


func comprobar(condicion: bool, que: String) -> void:
	if not condicion:
		_fallos += 1
		print("TEST FALLO: ", que)


func _probar() -> void:
	SceneManager.is_ui_open = true
	var capa := CanvasLayer.new()
	add_child(capa)
	var libro = load(LIBRO).instantiate()
	capa.add_child(libro)
	await get_tree().create_timer(0.3).timeout
	var rtl: RichTextLabel = libro.rtl
	Tipografia.aplicar("adventor")
	libro._preparar_contenido(TEXTO)
	libro._on_button_right_pressed()
	await get_tree().process_frame

	# Las dos herramientas sobre la misma palabra, con doble clic.
	for palabra in ["faro", "noche"]:
		var inicio := TEXTO.find(palabra)
		var esperado: Array = [[inicio, inicio + palabra.length()]]
		for herramienta in ["RESALTAR", "SUBRAYAR"]:
			libro.herramienta_actual = libro.Herramienta[herramienta]
			await _doble_clic(libro, rtl, palabra)
		libro.herramienta_actual = libro.Herramienta.NINGUNA
		for clave in ["resaltar", "subrayar"]:
			var tramos := _tramos(libro, clave)
			comprobar(tramos == esperado, "«%s» con %s: marcado %s, esperado %s" % [palabra, clave, tramos, esperado])
		libro._preparar_contenido(TEXTO)
		libro._on_button_right_pressed()
		await get_tree().process_frame

	Tipografia.aplicar("adventor")
	libro.queue_free()
	await get_tree().process_frame


## Doble clic de verdad (por el viewport) en mitad de la palabra.
func _doble_clic(libro, rtl: RichTextLabel, palabra: String) -> void:
	var inicio := TEXTO.find(palabra)
	var linea := rtl.get_character_line(inicio)
	var desde_linea := inicio
	while desde_linea > 0 and rtl.get_character_line(desde_linea - 1) == linea:
		desde_linea -= 1
	var fuente := rtl.get_theme_font("normal_font")
	var tam := rtl.get_theme_font_size("normal_font_size")
	var antes := TEXTO.substr(desde_linea, inicio - desde_linea)
	var x := fuente.get_string_size(antes + palabra.substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	var y := rtl.get_line_offset(linea) + fuente.get_height(tam) / 2.0
	var pos := rtl.get_global_rect().position + Vector2(x, y)
	for doble in [false, true]:
		for pulsado in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pulsado
			ev.double_click = doble and pulsado
			ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pulsado else 0
			ev.position = pos
			ev.global_position = pos
			get_viewport().push_input(ev)
			await get_tree().process_frame


## Tramos [inicio, fin) de la página 1 con esa marca.
func _tramos(libro, clave: String) -> Array:
	var estilos: Array = libro.estilos_por_pagina[0]
	var tramos: Array = []
	var inicio := -1
	for i in estilos.size() + 1:
		var activo: bool = i < estilos.size() and estilos[i][clave]
		if activo and inicio < 0:
			inicio = i
		elif not activo and inicio >= 0:
			tramos.append([inicio, i])
			inicio = -1
	return tramos
