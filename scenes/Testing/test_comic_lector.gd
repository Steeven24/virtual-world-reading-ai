## Prueba del lector de cómics. Se lanza en headless:
##   Godot --headless --path <copia aislada> --quit-after 60000 res://scenes/Testing/test_comic_lector.tscn
## IMPORTANTE: ejecutar sobre una copia con use_custom_user_dir, nunca sobre el
## user:// real: AuthManager restaura el token guardado y se harían peticiones
## reales con la cuenta del alumno. La prueba aborta si detecta una sesión.
extends Node

const ESCENA_LECTOR := "res://scenes/UI/comic_lector.tscn"
const ESCENA_CATALOGO := "res://scenes/UI/comic_catalogo.tscn"
const FUENTE := preload("res://fonts/fuente_juego.tres")

var _fallos := 0
var _terminados: Array = []
var _salidas := [0]


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK    - %s" % descripcion)
	else:
		_fallos += 1
		print("FALLO - %s" % descripcion)


func _ready() -> void:
	print("USERDIR: %s" % OS.get_user_data_dir())
	if not OS.get_user_data_dir().contains("vw_prueba_t8"):
		push_error("ABORTADO: el user:// no es el aislado de la prueba.")
		get_tree().quit(2)
		return
	if AuthManager.is_authenticated or not AuthManager.auth_token.is_empty():
		push_error("ABORTADO: hay una sesión real restaurada; ejecuta la prueba en una copia con user:// aislado.")
		get_tree().quit(2)
		return
	await _probar()
	print("RESULTADO: %s (%d fallos)" % ["VERDE" if _fallos == 0 else "ROJO", _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)


func _abrir_lector(episodio: String, pagina: int) -> Node:
	var lector: Node = load(ESCENA_LECTOR).instantiate()
	add_child(lector)
	await get_tree().process_frame
	await get_tree().process_frame
	lector.abrir(episodio, pagina)
	await _esperar()
	return lector


func _esperar() -> void:
	# Tipografia escala los controles nuevos en diferido: dos fotogramas bastan.
	await get_tree().process_frame
	await get_tree().process_frame


func _fijar_fuente(id: String) -> void:
	Ajustes.fijar("fuente", id)
	await _esperar()


## Índice del bocadillo con el texto más largo de la página abierta.
func _mas_largo(lector: Node, episodio: String, pagina: int) -> int:
	var lista := ComicLibrary.bocadillos(episodio, pagina)
	var mejor := 0
	for i in lista.size():
		if lista[i]["texto"].length() > lista[mejor]["texto"].length():
			mejor = i
	return mejor


## Lo que haría el Label real con esa caja y ese texto, sin pasar por mi medida:
## ¿se queda sin recortar? Sirve de contraste independiente de Lector.cabe().
func _label_cabe(texto: String, caja: Vector2, tam_real: int) -> bool:
	var l := Label.new()
	l.text = texto
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", FUENTE)
	l.add_theme_font_size_override("font_size", tam_real)
	l.size = Vector2(caja.x - 6.0, caja.y - 6.0)
	var lineas := l.get_line_count()
	var alto_linea := l.get_line_height()
	var cabe_alto := lineas * alto_linea <= caja.y - 6.0
	var palabra_ancha := false
	for palabra in texto.split(" ", false):
		if FUENTE.get_string_size(palabra, HORIZONTAL_ALIGNMENT_LEFT, -1, tam_real).x > caja.x - 6.0:
			palabra_ancha = true
	l.free()
	return cabe_alto and not palabra_ancha


func _probar() -> void:
	ComicLibrary.cargar_progreso()
	ComicLibrary.progreso_cargado.connect(func(): pass)

	# ── Tipografía normal (Literata): ningún bocadillo usa el panel ──
	await _fijar_fuente("literata")
	var lector := await _abrir_lector("ep01", 1)
	lector.salir.connect(func(): _salidas[0] += 1)
	lector.episodio_terminado.connect(func(id): _terminados.append(id))
	_comprobar(lector.episodio_actual() == "ep01" and lector.pagina_actual() == 1, "abre ep01 en la página 1")
	var total: int = lector.total_bocadillos()
	_comprobar(total > 0, "la página tiene bocadillos (%d)" % total)
	_comprobar(lector.nivel_texto() == 0, "el tamaño de texto arranca en normal")
	_comprobar(lector.bocadillos_en_panel().is_empty(), "literata normal: ningún bocadillo usa el panel (%s)" % str(lector.bocadillos_en_panel()))
	_comprobar(not lector.panel_visible(), "literata normal: el panel de lectura está oculto")
	var l0: Label = lector.etiqueta(0)
	_comprobar(l0 != null and l0.text == ComicLibrary.bocadillos("ep01", 1)[0]["texto"], "el texto va en un Label real")
	_comprobar(l0.get_theme_font("font") == FUENTE, "el Label usa la fuente compartida del juego")
	_comprobar(l0.get_theme_font_size("font_size") == Tipografia.tam(16) and Tipografia.tam(16) == roundi(16 * 0.9), "literata: el Label tiene el tamaño escalado por Tipografia (%d)" % l0.get_theme_font_size("font_size"))

	# Atribución
	var atr: Label = lector.get_node("%Atribucion")
	_comprobar(atr.visible and atr.text.contains("David Revoy") and atr.text.contains("CC BY"), "atribución a Pepper&Carrot visible (%s)" % atr.text)

	# ── OpenDyslexic a tamaño máximo: el bocadillo largo SÍ usa el panel ──
	var largo: int = _mas_largo(lector, "ep01", 2)
	lector.ir_a(2)
	await _esperar()
	largo = _mas_largo(lector, "ep01", 2)
	_comprobar(lector.etiqueta(largo) != null, "literata normal, ep01/2: el bocadillo largo cabe en su globo")
	await _fijar_fuente("opendyslexic")
	lector.fijar_nivel_texto(2)
	await _esperar()
	var l_od: Label = lector.etiqueta(0)
	_comprobar(Tipografia.escala() == 0.68, "OpenDyslexic activa (escala 0,68)")
	_comprobar(lector.tam_texto_diseno() == 28, "tamaño máximo = 28 de diseño")
	_comprobar(lector.bocadillos_en_panel().has(largo), "opendyslexic máximo: el bocadillo largo usa el panel (%s)" % str(lector.bocadillos_en_panel()))
	_comprobar(lector.etiqueta(largo) == null, "ese bocadillo ya no está en un Label dentro del globo")
	_comprobar(lector.panel_visible(), "el panel de lectura se muestra")
	var textos_panel: Array[String] = []
	for e in lector.etiquetas_panel():
		textos_panel.append(e.text)
	_comprobar(textos_panel.has(ComicLibrary.bocadillos("ep01", 2)[largo]["texto"]), "el panel contiene el texto completo del bocadillo largo")
	for i in lector.total_bocadillos():
		var et: Label = lector.etiqueta(i)
		if et != null:
			var lineas := et.get_line_count() * et.get_line_height()
			_comprobar(lineas <= et.size.y, "ep01/2 bocadillo %d sin recortar (%d <= %d)" % [i, lineas, int(et.size.y)])
			_comprobar(et.get_theme_font_size("font_size") == Tipografia.tam(28), "ep01/2 bocadillo %d a tamaño máximo escalado (%d)" % [i, et.get_theme_font_size("font_size")])

	# El panel se puede ocultar y volver a mostrar sin perder el texto
	var boton_panel: Button = lector.get_node("%BotonPanel")
	boton_panel.pressed.emit()
	_comprobar(not lector.get_node("%Desplazable").visible and boton_panel.text == "Mostrar", "Ocultar pliega el panel")
	boton_panel.pressed.emit()
	_comprobar(lector.get_node("%Desplazable").visible, "Mostrar lo despliega")

	# ── Invariante global: nada recortado y la medida coincide con la del Label ──
	var desacuerdos := 0
	var recortados := 0
	var revisados := 0
	var en_panel := 0
	for fam in ["adventor", "literata", "opendyslexic"]:
		await _fijar_fuente(fam)
		for nivel in 3:
			lector.fijar_nivel_texto(nivel)
			for ep in ComicLibrary.episodios():
				for p in ep["num_paginas"]:
					lector.abrir(ep["id"], p)
					var lista := ComicLibrary.bocadillos(ep["id"], p)
					var tam_real: int = Tipografia.tam(lector.tam_texto_diseno())
					var tam_pagina: Vector2 = lector.tam_pagina()
					for i in lista.size():
						var caja := Vector2(lista[i]["ancho"] * tam_pagina.x, lista[i]["alto"] * tam_pagina.y)
						var et: Label = lector.etiqueta(i)
						revisados += 1
						if et != null:
							if et.get_line_count() * et.get_line_height() > et.size.y + 0.5:
								recortados += 1
						else:
							en_panel += 1
						# El Label real dice lo mismo que la medida
						if _label_cabe(lista[i]["texto"], caja, tam_real) != (et != null):
							desacuerdos += 1
							print("  desacuerdo %s %s/%d/%d nivel %d: %s" % [fam, ep["id"], p, i, nivel, lista[i]["texto"]])
	_comprobar(revisados > 1000, "revisados todos los bocadillos en 3 familias x 3 tamaños (%d, %d al panel)" % [revisados, en_panel])
	_comprobar(recortados == 0, "ningún Label dentro del globo queda recortado (%d recortados)" % recortados)
	_comprobar(desacuerdos == 0, "la medida y el Label real deciden igual en todos los casos (%d desacuerdos)" % desacuerdos)

	# ── Globos diminutos (ep02, página 3): van al panel, ninguno se pierde ──
	await _fijar_fuente("adventor")
	lector.fijar_nivel_texto(0)
	lector.abrir("ep02", 2)
	await _esperar()
	var diminutos := ["FLAME", "OCÉANO", "VIOLE(N)TO"]
	var lista_ep2 := ComicLibrary.bocadillos("ep02", 2)
	var en_panel_ep2: Array[String] = []
	for i in lector.bocadillos_en_panel():
		en_panel_ep2.append(lista_ep2[i]["texto"])
	for t in diminutos:
		_comprobar(en_panel_ep2.has(t), "ep02/3 «%s» (caja diminuta) se lee en el panel" % t)
	_comprobar(lector.etiquetas_panel().size() == lector.bocadillos_en_panel().size(), "el panel tiene una entrada por bocadillo desbordado")

	# ── Zoom y desplazamiento ──
	lector.abrir("ep01", 1)
	await _esperar()
	var visor: Vector2 = lector.tam_visor()
	_comprobar(lector.zoom() == 1.0 and is_equal_approx(lector.tam_pagina().x, visor.x), "zoom 1: la página ocupa todo el ancho del visor (%s)" % lector.tam_pagina())
	var ancho1: float = lector.tam_pagina().x
	var etiqueta_ancho1: float = lector.etiqueta(0).size.x
	lector.cambiar_zoom(1.25)
	await _esperar()
	_comprobar(is_equal_approx(lector.zoom(), 1.25) and is_equal_approx(lector.tam_pagina().x, ancho1 * 1.25), "zoom 1,25 amplía la página (%s)" % lector.tam_pagina())
	_comprobar(lector.etiqueta(0) != null and is_equal_approx(lector.etiqueta(0).size.x, etiqueta_ancho1 * 1.25), "los globos crecen con la página")
	for _i in 10:
		lector.cambiar_zoom(1.25)
	_comprobar(is_equal_approx(lector.zoom(), 3.0), "el zoom no pasa del máximo (%s)" % lector.zoom())
	for _i in 10:
		lector.cambiar_zoom(0.8)
	_comprobar(is_equal_approx(lector.zoom(), 1.0), "el zoom no baja del mínimo (%s)" % lector.zoom())
	lector.cambiar_zoom(2.0)
	await _esperar()
	var pag: Vector2 = lector.tam_pagina()
	for delta in [Vector2(-99999, -99999), Vector2(99999, 99999), Vector2(-120, -75)]:
		lector.desplazar(delta)
		var d: Vector2 = lector.desplazamiento()
		var dentro: bool = d.x <= 0.001 and d.y <= 0.001 and d.x + pag.x >= visor.x - 0.001 and d.y + pag.y >= visor.y - 0.001
		_comprobar(dentro, "desplazar %s no deja ver fuera de la página (pos %s)" % [str(delta), str(d)])
	lector.desplazar(Vector2(99999, 99999))
	var antes: Vector2 = lector.desplazamiento()
	lector.desplazar(Vector2(-50, -30))
	_comprobar(lector.desplazamiento() == antes + Vector2(-50, -30), "desplazar mueve la página lo pedido (%s)" % lector.desplazamiento())
	# Arrastre con el ratón sobre el visor
	var visor_nodo: Control = lector.get_node("%Visor")
	var pulsar := InputEventMouseButton.new()
	pulsar.button_index = MOUSE_BUTTON_LEFT
	pulsar.pressed = true
	visor_nodo.gui_input.emit(pulsar)
	var mov := InputEventMouseMotion.new()
	mov.relative = Vector2(-40, -20)
	visor_nodo.gui_input.emit(mov)
	pulsar = InputEventMouseButton.new()
	pulsar.button_index = MOUSE_BUTTON_LEFT
	pulsar.pressed = false
	visor_nodo.gui_input.emit(pulsar)
	var tras_arrastre: Vector2 = lector.desplazamiento()
	mov.relative = Vector2(500, 500)
	visor_nodo.gui_input.emit(mov)
	_comprobar(tras_arrastre == antes + Vector2(-90, -50) and lector.desplazamiento() == tras_arrastre, "el arrastre mueve la página y al soltar deja de moverla (%s)" % str(tras_arrastre))
	# Un zoom no cambia el punto del centro
	lector.cambiar_zoom(0.0001)
	lector.cambiar_zoom(1.0)
	_comprobar(is_equal_approx(lector.zoom(), 1.0), "volver a zoom 1")

	# ── Teclado y foco ──
	lector.abrir("ep03", 0)
	await _esperar()
	for nombre in ["BotonSalir", "BotonAnterior", "BotonSiguiente", "BotonZoomMas", "BotonZoomMenos", "BotonTextoMas", "BotonTextoMenos", "BotonPanel"]:
		var b: Button = lector.get_node("%" + nombre)
		b.grab_focus()
		_comprobar(get_viewport().gui_get_focus_owner() == null, "%s no toma foco" % nombre)
	lector.get_node("%BotonZoomMas").pressed.emit()
	_pulsar("ui_right")
	await get_tree().process_frame
	_comprobar(lector.pagina_actual() == 1, "tras usar un botón, la flecha derecha sigue pasando página (%d)" % lector.pagina_actual())
	_pulsar("ui_left")
	await get_tree().process_frame
	_comprobar(lector.pagina_actual() == 0, "la flecha izquierda vuelve (%d)" % lector.pagina_actual())
	_pulsar("ui_left")
	await get_tree().process_frame
	_comprobar(lector.pagina_actual() == 0, "no se sale por delante de la portada")
	var p3: Dictionary = ComicLibrary.progreso("ep03")
	_comprobar(p3["last_page"] == 0 and not p3["finished"], "ep03 en la portada queda a cero (%s)" % str(p3))
	lector.siguiente()
	lector.siguiente()
	p3 = ComicLibrary.progreso("ep03")
	_comprobar(p3["last_page"] == 2 and not p3["finished"], "pasar páginas guarda dónde se queda el alumno (%s)" % str(p3))
	lector.get_node("%BotonSalir").pressed.emit()
	_comprobar(_salidas[0] == 1, "BotonSalir emite salir (%d)" % _salidas[0])
	_pulsar("ui_cancel")
	await get_tree().process_frame
	_comprobar(_salidas[0] == 2, "Escape emite salir (%d)" % _salidas[0])

	# ── Pasar de la última página termina el episodio ──
	var ultimo: int = ComicLibrary.episodios()[0]["num_paginas"] - 1
	lector.abrir("ep01", ultimo)
	await _esperar()
	_comprobar(lector.get_node("%BotonSiguiente").text == "Terminar", "en la última página el botón dice «Terminar»")
	_terminados.clear()
	var salidas_antes: int = _salidas[0]
	lector.siguiente()
	_comprobar(_terminados == ["ep01"], "pasar de la última página emite episodio_terminado (%s)" % str(_terminados))
	var p1: Dictionary = ComicLibrary.progreso("ep01")
	_comprobar(p1["finished"] and p1["last_page"] == ultimo, "queda guardado finished=true en la última página (%s)" % str(p1))
	_comprobar(_salidas[0] == salidas_antes + 1, "y el lector emite salir")
	lector.abrir("ep01", 0)
	await _esperar()
	lector.siguiente()
	_comprobar(ComicLibrary.progreso("ep01")["finished"], "releer un episodio terminado no le quita el «leído»")
	lector.queue_free()
	await get_tree().process_frame

	# ── Recorrido completo: catálogo → episodio → lector → salir → catálogo ──
	await _fijar_fuente("adventor")
	var cat: Node = load(ESCENA_CATALOGO).instantiate()
	add_child(cat)
	await _esperar()
	var cierres := [0]
	cat.cerrado.connect(func(): cierres[0] += 1)
	_comprobar(cat.lector_abierto() == null, "el catálogo arranca sin lector")
	cat.elegir("ep04")
	await _esperar()
	var l: Node = cat.lector_abierto()
	_comprobar(l != null and l.episodio_actual() == "ep04" and l.pagina_actual() == 0, "elegir en el catálogo abre el lector en ep04, página 0")
	_comprobar(l.get_parent() == cat, "el lector es hijo del catálogo")
	cat.elegir("ep05")
	_pulsar("ui_accept")
	await get_tree().process_frame
	_comprobar(cat.lector_abierto() == l and l.episodio_actual() == "ep04", "con el lector abierto no se abre otro episodio")
	_comprobar(l.pagina_actual() == 1, "Intro dentro del lector pasa página y no llega al catálogo (%d)" % l.pagina_actual())
	l.siguiente()
	l.get_node("%BotonSalir").pressed.emit()
	await _esperar()
	_comprobar(cat.lector_abierto() == null and not is_instance_valid(l), "salir libera el lector")
	_comprobar(cat.visible and cierres[0] == 0, "y el catálogo sigue abierto")
	_comprobar(cat.episodio_a_continuar() == "ep04", "el catálogo señala ep04 como a medias (%s)" % cat.episodio_a_continuar())
	_comprobar(cat.get_node("%TextoContinuar").text == "Página 3 de %d" % ComicLibrary.episodios()[3]["num_paginas"], "el panel de continuar muestra la página 3 (%s)" % cat.get_node("%TextoContinuar").text)
	# Escape dentro del lector lo cierra pero no cierra el catálogo
	cat.get_node("%BotonContinuar").pressed.emit()
	await _esperar()
	l = cat.lector_abierto()
	_comprobar(l != null and l.pagina_actual() == 2, "Continuar abre el lector donde se quedó (página %d)" % (l.pagina_actual() if l != null else -1))
	_pulsar("ui_cancel")
	await _esperar()
	_comprobar(cat.lector_abierto() == null and cierres[0] == 0, "Escape cierra solo el lector, no el catálogo")
	_pulsar("ui_cancel")
	await get_tree().process_frame
	_comprobar(cierres[0] == 1, "con el lector cerrado, Escape vuelve a cerrar el catálogo")
	# Terminar un episodio desde el catálogo actualiza el contador
	var ultima10: int = ComicLibrary.episodios()[9]["num_paginas"] - 1
	ComicLibrary.guardar_progreso("ep10", ultima10, false)
	cat.refrescar()
	var antes_leidos: String = cat.get_node("%Contador").text
	cat.elegir("ep10")
	await _esperar()
	l = cat.lector_abierto()
	_comprobar(l != null and l.pagina_actual() == ultima10, "ep10 a medias se abre en su última página")
	l.siguiente()
	await _esperar()
	_comprobar(cat.lector_abierto() == null, "terminar el episodio devuelve al catálogo")
	_comprobar(cat.get_node("%Contador").text != antes_leidos and cat.get_node("%Contador").text.begins_with("2 /"), "el contador cuenta el episodio terminado (%s -> %s)" % [antes_leidos, cat.get_node("%Contador").text])
	cat.queue_free()
	await get_tree().process_frame


## Inyecta una acción de interfaz como si el alumno pulsara la tecla.
func _pulsar(accion: String) -> void:
	var ev := InputEventAction.new()
	ev.action = accion
	ev.pressed = true
	Input.parse_input_event(ev)
