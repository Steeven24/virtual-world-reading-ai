## Prueba del catálogo de cómics. Se lanza en headless:
##   Godot --headless --path <copia aislada> --quit-after 4000 res://scenes/Testing/test_comic_catalogo.tscn
## IMPORTANTE: ejecutar sobre una copia con use_custom_user_dir, nunca sobre el
## user:// real: AuthManager restaura el token guardado y se harían peticiones
## reales con la cuenta del alumno. La prueba aborta si detecta una sesión.
extends Node

const ESCENA := "res://scenes/UI/comic_catalogo.tscn"

var _fallos := 0
var _elegidos: Array = []


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK    - %s" % descripcion)
	else:
		_fallos += 1
		print("FALLO - %s" % descripcion)


func _ready() -> void:
	print("USERDIR: %s" % OS.get_user_data_dir())
	if not OS.get_user_data_dir().contains("vw_prueba_t7"):
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


func _abrir() -> Node:
	var catalogo: Node = load(ESCENA).instantiate()
	add_child(catalogo)
	await get_tree().process_frame
	return catalogo


func _probar() -> void:
	Ajustes.fijar("comics_vista", "expositor")
	var cat := await _abrir()
	_comprobar(cat.vista_actual() == "expositor", "arranca en la vista expositor")
	_comprobar(cat.get_node("%Expositor").visible and not cat.get_node("%Rejilla").visible, "solo el expositor es visible")
	_comprobar(cat.get_node("%Contador").text == "0 / 10 leídos", "contador a cero sin progreso (%s)" % cat.get_node("%Contador").text)
	_comprobar(cat.get_node("%Cuadricula").get_child_count() == 10, "la rejilla tiene 10 portadas")
	_comprobar(cat.episodio_a_continuar() == "", "sin progreso no hay episodio a continuar")

	# Expositor: portada central a 1,0 y vecinas a 0,8 con menos opacidad
	var centro: Control = cat.item_expositor(0)
	var vecino: Control = cat.item_expositor(1)
	await get_tree().create_timer(0.6).timeout
	_comprobar(is_equal_approx(centro.scale.x, 1.0), "portada central a escala 1,0 (%s)" % centro.scale)
	_comprobar(is_equal_approx(vecino.scale.x, 0.8), "vecina a escala 0,8 (%s)" % vecino.scale)
	_comprobar(vecino.modulate.a < 1.0, "vecina con opacidad reducida (%s)" % vecino.modulate.a)

	# Navegación con teclado
	var tecla := InputEventAction.new()
	tecla.action = "ui_right"
	tecla.pressed = true
	Input.parse_input_event(tecla)
	await get_tree().process_frame
	await get_tree().process_frame
	_comprobar(cat.indice_expositor() == 1, "ui_right avanza al episodio 2 (%d)" % cat.indice_expositor())
	cat.mover_expositor(-1)
	_comprobar(cat.indice_expositor() == 0, "mover(-1) vuelve al primero")
	cat.mover_expositor(-1)
	_comprobar(cat.indice_expositor() == 0, "no se sale por la izquierda")

	# Cambio de vista y memoria
	cat.cambiar_vista()
	_comprobar(cat.vista_actual() == "rejilla", "cambiar_vista pasa a rejilla")
	_comprobar(cat.get_node("%Rejilla").visible and not cat.get_node("%Expositor").visible, "solo la rejilla es visible")
	_comprobar(Ajustes.obtener("comics_vista") == "rejilla", "la vista queda en Ajustes")
	cat.queue_free()
	await get_tree().process_frame
	cat = await _abrir()
	_comprobar(cat.vista_actual() == "rejilla", "tras recargar sigue en rejilla")
	cat.cambiar_vista()
	_comprobar(cat.vista_actual() == "expositor", "cambiar_vista vuelve a expositor")

	# Progreso: ep01 terminado, ep02 terminado, ep03 a medias
	ComicLibrary.guardar_progreso("ep01", 3, true)
	ComicLibrary.guardar_progreso("ep02", 5, true)
	var ep3: Dictionary = ComicLibrary.episodios()[2]
	var pag := mini(2, ep3["num_paginas"] - 1)
	ComicLibrary.guardar_progreso(ep3["id"], pag, false)
	cat.refrescar()
	_comprobar(cat.get_node("%Contador").text == "2 / 10 leídos", "contador «2 / 10 leídos» (%s)" % cat.get_node("%Contador").text)
	_comprobar(cat.episodio_a_continuar() == ep3["id"], "el panel señala %s (%s)" % [ep3["id"], cat.episodio_a_continuar()])
	_comprobar(cat.get_node("%BarraContinuar").value > 0.0, "barra de progreso con valor (%s)" % cat.get_node("%BarraContinuar").value)
	_comprobar(cat.get_node("%TituloContinuar").text == ep3["titulo"], "el panel muestra el título")
	var marcas := 0
	for celda in cat.get_node("%Cuadricula").get_children():
		if celda.has_node("MarcaLeido") and celda.get_node("MarcaLeido").visible:
			marcas += 1
	_comprobar(marcas == 2, "dos portadas con marca de terminado (%d)" % marcas)

	# Señal
	cat.episodio_elegido.connect(func(id, p): _elegidos.append([id, p]))
	cat.get_node("%BotonContinuar").pressed.emit()
	_comprobar(_elegidos == [[ep3["id"], pag]], "Continuar emite episodio_elegido con su página (%s)" % str(_elegidos))
	_elegidos.clear()
	cat.elegir("ep01")
	_comprobar(_elegidos == [["ep01", 0]], "un episodio terminado se abre desde la página 0 (%s)" % str(_elegidos))

	# Conexiones de la escena (un .tscn con rutas viejas las descarta en silencio)
	_comprobar(cat.get_node("%BotonVista").pressed.get_connections().size() > 0, "BotonVista conectado")
	_comprobar(cat.get_node("%BotonContinuar").pressed.get_connections().size() > 0, "BotonContinuar conectado")
	_comprobar(cat.get_node("%BotonCerrar").pressed.get_connections().size() > 0, "BotonCerrar conectado")
	cat.queue_free()
