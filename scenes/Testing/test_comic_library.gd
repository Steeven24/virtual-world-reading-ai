## Prueba de ComicLibrary. Se lanza en headless:
##   Godot --headless --path <copia aislada> --quit-after 45 res://scenes/Testing/test_comic_library.tscn
## IMPORTANTE: ejecutar sobre una copia con use_custom_user_dir, nunca sobre el
## user:// real: AuthManager restaura el token guardado y se harían peticiones
## reales con la cuenta del alumno. La prueba aborta si detecta una sesión.
extends Node

var _fallos := 0


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK    - %s" % descripcion)
	else:
		_fallos += 1
		print("FALLO - %s" % descripcion)


func _ready() -> void:
	if AuthManager.is_authenticated or not AuthManager.auth_token.is_empty():
		push_error("ABORTADO: hay una sesión real restaurada; ejecuta la prueba en una copia con user:// aislado.")
		get_tree().quit(2)
		return
	await _probar()
	print("RESULTADO: %s (%d fallos)" % ["VERDE" if _fallos == 0 else "ROJO", _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)


func _probar() -> void:
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
		for i in ep["num_paginas"]:
			if not (ComicLibrary.bocadillos(ep["id"], i) is Array):
				bocadillos_ok = false
	_comprobar(bocadillos_ok, "bocadillos devuelve una lista por cada página")
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

	# Escritura sin red: queda pendiente
	ComicLibrary.guardar_progreso("ep03", 4, false)
	_comprobar(ComicLibrary.progreso("ep03")["last_page"] == 4, "guardar_progreso actualiza la memoria")
	espera = 0.0
	while not FileAccess.file_exists(ComicLibrary.ARCHIVO_PENDIENTE) and espera < 15.0:
		await get_tree().create_timer(0.1).timeout
		espera += 0.1
	_comprobar(FileAccess.file_exists(ComicLibrary.ARCHIVO_PENDIENTE), "el PUT fallido queda pendiente en disco")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ComicLibrary.ARCHIVO_PENDIENTE))
	AuthManager.is_authenticated = false
	AuthManager.auth_token = ""
