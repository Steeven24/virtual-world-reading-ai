## Prueba de ComicLibrary. Se lanza en headless:
##   Godot --headless --path <copia aislada> --quit-after 45 res://scenes/Testing/test_comic_library.tscn
## IMPORTANTE: ejecutar sobre una copia con config/use_custom_user_dir, nunca sobre
## el user:// real: AuthManager restaura el token guardado y se harían peticiones
## reales con la cuenta del alumno. La guarda de abajo es post-hoc: ComicLibrary
## ya lanzó su petición en su propio _ready, antes de este. La protección real es
## la copia aislada; la guarda solo evita seguir y escribir si no se usó.
extends Node

var _fallos := 0


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK    - %s" % descripcion)
	else:
		_fallos += 1
		print("FALLO - %s" % descripcion)


func _ready() -> void:
	print("USERDIR: %s" % OS.get_user_data_dir())
	if not OS.get_user_data_dir().contains("vw_prueba_t6"):
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


func _probar() -> void:
	# Estado limpio: un resto de una ejecución interrumpida falsearía las comprobaciones
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ComicLibrary.ARCHIVO_PENDIENTE))

	# Catálogo
	var eps := ComicLibrary.episodios()
	_comprobar(eps.size() == 10, "el catálogo trae 10 episodios (%d)" % eps.size())
	var total := 0
	for ep in eps:
		total += ep["num_paginas"]
	_comprobar(total == 77, "77 páginas en total (%d)" % total)
	_comprobar(ComicLibrary.atribucion().get("autor", "") == "David Revoy", "atribución con autor")
	_comprobar(ComicLibrary.pagina("ep01", 0) is Texture2D, "pagina(ep01, 0) devuelve una textura")
	_comprobar(ComicLibrary.pagina("ep01", 999) == null, "pagina fuera de rango devuelve null")
	_comprobar(ComicLibrary.pagina("nope", 0) == null, "pagina de episodio desconocido devuelve null")
	var bocadillos_ok := true
	for ep in eps:
		var contados := 0
		for i in ep["num_paginas"]:
			ComicLibrary.bocadillos(ep["id"], i)
			contados += 1
		# Una lista por página: el catálogo interno debe tener tantas como páginas.
		if ComicLibrary._bocadillos[ep["id"]].size() != ep["num_paginas"] or contados != ep["num_paginas"]:
			bocadillos_ok = false
			print("  episodio %s: %d listas, %d páginas" % [ep["id"], ComicLibrary._bocadillos[ep["id"]].size(), ep["num_paginas"]])
	_comprobar(bocadillos_ok, "cada episodio tiene tantas listas de bocadillos como páginas")
	_comprobar(ComicLibrary.bocadillos("ep01", 1).size() > 0, "ep01 pág. 1 tiene bocadillos")
	_comprobar(ComicLibrary.bocadillos("ep01", 999).is_empty(), "bocadillos fuera de rango vacío")

	# Sin sesión: ceros, sin colgarse
	var p := ComicLibrary.progreso("ep01")
	_comprobar(p == {"last_page": 0, "finished": false}, "sin datos, progreso devuelve ceros")

	# Fila del servidor con episodio desconocido: se ignora
	ComicLibrary._aplicar_respuesta_progreso({
		"episodios": [
			{"episode_id": "ep99", "last_page": 3, "finished": true, "updated_at": "x"},
			{"episode_id": "ep02", "last_page": 2, "finished": true, "updated_at": "x"},
		],
		"visitas": 4,
	})
	_comprobar(ComicLibrary.episodios().size() == 10, "fila desconocida no altera episodios()")
	_comprobar(ComicLibrary.progreso("ep99") == {"last_page": 0, "finished": false}, "ep99 ignorado")
	_comprobar(ComicLibrary.progreso("ep02") == {"last_page": 2, "finished": true}, "fila conocida sí se aplica")

	# Página fuera de rango: se acota al episodio
	var n_ep02: int = ComicLibrary.episodios()[1]["num_paginas"]
	ComicLibrary._aplicar_respuesta_progreso({"episodios": [{"episode_id": "ep02", "last_page": 999, "finished": false}]})
	_comprobar(ComicLibrary.progreso("ep02")["last_page"] == n_ep02 - 1, "last_page del servidor mayor que el episodio se acota a la última")
	ComicLibrary._aplicar_respuesta_progreso({"episodios": [{"episode_id": "ep02", "last_page": -5, "finished": false}]})
	_comprobar(ComicLibrary.progreso("ep02")["last_page"] == 0, "last_page negativo se acota a 0")
	ComicLibrary.guardar_progreso("ep02", 500, true)
	_comprobar(ComicLibrary.progreso("ep02")["last_page"] == n_ep02 - 1, "guardar_progreso acota la página")
	ComicLibrary.guardar_progreso("ep02", -3, false)
	_comprobar(ComicLibrary.progreso("ep02")["last_page"] == 0, "guardar_progreso acota negativos")
	_comprobar(not FileAccess.file_exists(ComicLibrary.ARCHIVO_PENDIENTE), "sin sesión no se escribe nada pendiente")

	# GET 2xx con cuerpo basura: la señal se emite igual
	var basura := {"emitida": false}
	ComicLibrary.progreso_cargado.connect(func(): basura["emitida"] = true, CONNECT_ONE_SHOT)
	ComicLibrary._cola.append({"metodo": "GET", "ruta": "/comics/progress", "cuerpo": {}, "meta": {}})
	ComicLibrary._ocupado = true
	ComicLibrary._al_completar_peticion(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "<html>proxy</html>".to_utf8_buffer())
	_comprobar(basura["emitida"], "GET con cuerpo no válido emite progreso_cargado")

	# Con sesión simulada y servidor inalcanzable
	ApiConfig.BASE_URL = "http://127.0.0.1:1"
	AuthManager.auth_token = "token-falso-de-prueba"
	AuthManager.is_authenticated = true
	var estado := {"emitida": false}
	ComicLibrary.progreso_cargado.connect(func(): estado["emitida"] = true, CONNECT_ONE_SHOT)
	ComicLibrary.cargar_progreso()
	var espera := 0.0
	while not estado["emitida"] and espera < 15.0:
		await get_tree().create_timer(0.1).timeout
		espera += 0.1
	_comprobar(estado["emitida"], "sin red, progreso_cargado se emite y no se cuelga (%.1f s)" % espera)
	_comprobar(ComicLibrary.episodios().size() == 10, "sin red, episodios() sigue dando 10")
	_comprobar(ComicLibrary.progreso("ep05") == {"last_page": 0, "finished": false}, "sin red, progreso devuelve ceros")

	# Escritura sin red: queda pendiente, atada a la cuenta que la hizo
	AuthManager.current_user = {"id": 1}
	ComicLibrary.guardar_progreso("ep03", 2, false)
	_comprobar(ComicLibrary.progreso("ep03")["last_page"] == 2, "guardar_progreso actualiza la memoria")
	espera = 0.0
	while not FileAccess.file_exists(ComicLibrary.ARCHIVO_PENDIENTE) and espera < 15.0:
		await get_tree().create_timer(0.1).timeout
		espera += 0.1
	var pend := ComicLibrary._leer_pendientes()
	_comprobar(pend.has("1") and pend["1"].has("ep03"), "el PUT fallido queda pendiente bajo el usuario 1")

	# Otro alumno en el mismo equipo: no hereda progreso ni reenvía lo ajeno
	AuthManager.current_user = {"id": 2}
	estado["emitida"] = false
	ComicLibrary.progreso_cargado.connect(func(): estado["emitida"] = true, CONNECT_ONE_SHOT)
	ComicLibrary.cargar_progreso()
	_comprobar(ComicLibrary.progreso("ep03") == {"last_page": 0, "finished": false}, "el usuario 2 no hereda el progreso del 1")
	_comprobar(ComicLibrary._cola.size() == 1 and ComicLibrary._cola[0]["metodo"] == "GET", "solo se encola su GET, ningún PUT ajeno")
	espera = 0.0
	while not estado["emitida"] and espera < 15.0:
		await get_tree().create_timer(0.1).timeout
		espera += 0.1
	pend = ComicLibrary._leer_pendientes()
	_comprobar(pend.has("1") and pend["1"].has("ep03") and not pend.has("2"), "lo pendiente del usuario 1 sigue intacto y nada pasa al 2")

	# Cerrar sesión vacía la memoria
	ComicLibrary.guardar_progreso("ep04", 1, false)
	AuthManager.logged_out.emit()
	_comprobar(ComicLibrary.progreso("ep04")["last_page"] == 0, "al cerrar sesión se vacía el progreso en memoria")

	# Sesión invalidada (otro slot activo) también vacía la memoria
	ComicLibrary.guardar_progreso("ep04", 1, false)
	AuthManager.session_invalidated.emit()
	_comprobar(ComicLibrary.progreso("ep04")["last_page"] == 0, "al invalidarse la sesión se vacía el progreso en memoria")

	# Carrera: la respuesta en vuelo de la cuenta anterior no puede aplicarse a la siguiente
	ComicLibrary._cola.append({"metodo": "GET", "ruta": "/comics/progress", "cuerpo": {}, "meta": {}})
	ComicLibrary._ocupado = true
	AuthManager.logged_out.emit()
	_comprobar(not ComicLibrary._ocupado and ComicLibrary._cola.is_empty(), "cerrar sesión libera la cola y no deja una petición en vuelo")

	# episodios() devuelve una copia
	var copia := ComicLibrary.episodios()
	copia.clear()
	_comprobar(ComicLibrary.episodios().size() == 10, "episodios() devuelve una copia: vaciarla no toca el catálogo")

	# Pendiente del formato antiguo (claves de episodio): se descarta
	var f := FileAccess.open(ComicLibrary.ARCHIVO_PENDIENTE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"ep01": {"last_page": 1, "finished": false}}))
	f.close()
	_comprobar(ComicLibrary._leer_pendientes().is_empty() and not FileAccess.file_exists(ComicLibrary.ARCHIVO_PENDIENTE), "el pendiente del formato antiguo se descarta")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(ComicLibrary.ARCHIVO_PENDIENTE))
	AuthManager.current_user = {}
	AuthManager.is_authenticated = false
	AuthManager.auth_token = ""
