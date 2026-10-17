extends Node
## Prueba temporal de la Task 15, repetida en la Task 16 tras corregir las
## herramientas: la hoja del libro se ajusta a la fuente y a la lectura.
var _fallos := 0

const LIBRO := "res://scenes/Book and Tools/book and tools.tscn"
const LECTURAS := "C:/Users/Kevin/AppData/Local/Temp/claude/C--Users-Kevin-Desktop-Proyecto-Godot-Pr-cticas-PROYECTO/8c33a80b-a622-4eda-a261-3434fcc49088/scratchpad/capturas/lecturas_reales.json"
const EXTREMA := 106
const TAM_HOJA := 16


func _ready() -> void:
	AuthManager.is_authenticated = false
	await _probar()
	print("TEST OK" if _fallos == 0 else "TEST FALLO: %d comprobaciones" % _fallos)
	get_tree().quit(1 if _fallos else 0)


func comprobar(condicion: bool, que: String) -> void:
	if not condicion:
		_fallos += 1
		print("TEST FALLO: ", que)


func _paginas_con_barra(libro, rtl: RichTextLabel) -> Array[int]:
	var con_barra: Array[int] = []
	for i in libro.paginas.size():
		libro.pagina_actual = i
		libro._refrescar_texto_actual()
		if rtl.get_content_height() > rtl.size.y:
			con_barra.append(i + 1)
	return con_barra


func _probar() -> void:
	var lecturas: Array = JSON.parse_string(FileAccess.get_file_as_string(LECTURAS))
	comprobar(lecturas.size() == 36, "36 lecturas de prueba")
	var capa := CanvasLayer.new()
	add_child(capa)
	var libro = load(LIBRO).instantiate()
	capa.add_child(libro)
	await get_tree().create_timer(0.3).timeout
	var rtl: RichTextLabel = libro.rtl

	for familia in Tipografia.ORDEN:
		Tipografia.aplicar(familia)
		var tam_familia := Tipografia.tam(TAM_HOJA)
		var minimo := ceili(tam_familia * 0.85)
		var no_caben: Array[String] = []
		for lectura in lecturas:
			libro._preparar_contenido(str(lectura["content"]))
			var tam := rtl.get_theme_font_size("normal_font_size")
			comprobar(tam <= tam_familia and tam >= minimo,
				"%s, lectura %d: letra de %d px, fuera de %d–%d" % [familia, lectura["id"], tam, minimo, tam_familia])
			if int(lectura["id"]) == EXTREMA:
				continue
			for pagina in _paginas_con_barra(libro, rtl):
				no_caben.append("%d/%d" % [lectura["id"], pagina])
		comprobar(no_caben.is_empty(), "%s: páginas con barra (lectura/página) %s" % [familia, no_caben])

	Tipografia.aplicar("opendyslexic")
	libro._preparar_contenido("Una frase corta.")
	comprobar(rtl.get_theme_font_size("normal_font_size") == Tipografia.tam(TAM_HOJA)
		and rtl.get_theme_constant("line_separation") == 0, "una lectura corta se queda tal cual")

	Tipografia.aplicar("adventor")
	libro._preparar_contenido(str(lecturas[0]["content"]))
	comprobar(_paginas_con_barra(libro, rtl).is_empty(), "lectura %d con Adventor" % lecturas[0]["id"])
	Tipografia.aplicar("opendyslexic")
	comprobar(_paginas_con_barra(libro, rtl).is_empty(), "pasar a OpenDyslexic con el libro abierto")

	Tipografia.aplicar("adventor")
	libro.queue_free()
	await get_tree().process_frame
