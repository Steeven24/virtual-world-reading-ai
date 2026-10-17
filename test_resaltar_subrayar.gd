extends Node
## Prueba temporal (Task 16, fallo visto por Kevin en Chrome): si un fragmento
## está resaltado y subrayado, el subrayado se ve en todas sus líneas; antes el
## resaltado de la línea siguiente lo tapaba. Mira píxeles: necesita ventana.
var _fallos := 0

const LIBRO := "res://scenes/Book and Tools/book and tools.tscn"
const FRASES := "El faro de la isla llevaba años apagado cuando Marta subió por primera vez la escalera de caracol. Desde arriba se veía todo el pueblo, las barcas amarradas y el camino que llevaba al bosque. "
## Fracción mínima de la línea que debe cubrir el subrayado.
const COBERTURA := 0.6


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
	SceneManager.is_ui_open = true  # sin el HUD de objetivos encima del libro
	var capa := CanvasLayer.new()
	add_child(capa)
	var libro = load(LIBRO).instantiate()
	capa.add_child(libro)
	await get_tree().create_timer(0.5).timeout
	var rtl: RichTextLabel = libro.rtl
	var densa := (FRASES + FRASES + FRASES + FRASES).substr(0, 690)
	for familia in Tipografia.ORDEN:
		Tipografia.aplicar(familia)
		for texto in [FRASES, densa]:
			libro._preparar_contenido(texto)
			libro._on_button_right_pressed()
			var nombre := "%s, %s, separación %d" % [familia, "densa" if texto == densa else "corta", rtl.get_theme_constant("line_separation")]
			if familia == "opendyslexic" and texto == densa:
				comprobar(rtl.get_theme_constant("line_separation") < 0, "%s: la hoja densa junta las líneas" % nombre)
			# Las tres primeras líneas, resaltadas y subrayadas.
			var fin := 0
			while fin < texto.length() and rtl.get_character_line(fin) < 3:
				fin += 1
			var estilos: Array = libro.estilos_por_pagina[0]
			for i in fin:
				estilos[i]["resaltar"] = true
				estilos[i]["subrayar"] = true
			libro._refrescar_texto_actual()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var imagen := get_viewport().get_texture().get_image()
			for linea in [0, 1]:
				var cobertura := _cobertura_subrayado(imagen, rtl, linea)
				comprobar(cobertura >= COBERTURA, "%s: el subrayado de la línea %d cubre %d %% (mínimo %d %%)" % [nombre, linea + 1, roundi(cobertura * 100), roundi(COBERTURA * 100)])
	Tipografia.aplicar("adventor")
	libro.queue_free()
	await get_tree().process_frame


## Fracción de la línea con píxeles oscuros a la altura del subrayado (la mejor
## de tres filas, porque el trazo es fino y puede caer entre dos).
func _cobertura_subrayado(imagen: Image, rtl: RichTextLabel, linea: int) -> float:
	var fuente := rtl.get_theme_font("normal_font")
	var tam := rtl.get_theme_font_size("normal_font_size")
	var origen := Vector2i(rtl.get_global_rect().position)
	var y := origen.y + rtl.get_line_offset(linea) + fuente.get_ascent(tam) + fuente.get_underline_position(tam)
	var x0 := origen.x + 8
	var x1 := origen.x + int(rtl.size.x) - 16
	var mejor := 0.0
	for fila in range(floori(y) - 1, ceili(y) + 2):
		var oscuros := 0
		for x in range(x0, x1):
			var c := imagen.get_pixel(x, fila)
			if 0.299 * c.r + 0.587 * c.g + 0.114 * c.b < 0.7:
				oscuros += 1
		mejor = maxf(mejor, float(oscuros) / (x1 - x0))
	return mejor
