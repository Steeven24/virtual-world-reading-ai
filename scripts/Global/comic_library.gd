## comic_library.gd
## Autoload que es la única puerta a los cómics de la zona de Archivos olvidados.
##
## El catálogo (assets/Comics/catalogo.json) y las páginas viajan dentro del juego,
## así que abrirlos nunca depende de la red. El servidor solo guarda el progreso
## del alumno: se baja con GET /comics/progress al entrar y se escribe con PUT.
## Si no hay red, el progreso devuelve ceros y las escrituras quedan pendientes
## en disco hasta el siguiente intento.
extends Node

## Se emite cuando termina la carga del progreso, haya habido red o no.
signal progreso_cargado

const RUTA_CATALOGO := "res://assets/Comics/catalogo.json"
const DIR_COMICS := "res://assets/Comics/"
const ARCHIVO_PENDIENTE := "user://comics_pendiente.json"

var _atribucion: Dictionary = {}
var _episodios: Array[Dictionary] = []
## Bocadillos por episodio: {"ep01": [[{...}, ...], ...]}.
var _bocadillos: Dictionary = {}
## Progreso en memoria: {"ep01": {"last_page": int, "finished": bool}}.
var _progreso: Dictionary = {}
var _visitas: int = 0

var _http: HTTPRequest
var _cola: Array[Dictionary] = []
var _ocupado := false


func _ready() -> void:
	_cargar_catalogo()
	_http = HTTPRequest.new()
	_http.timeout = ApiConfig.TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_al_completar_peticion)
	AuthManager.logged_out.connect(_al_cerrar_sesion)
	# Un cierre forzado (otro slot activo, entorno desactivado) no emite logged_out.
	AuthManager.session_invalidated.connect(_al_cerrar_sesion)
	if AuthManager.is_authenticated:
		cargar_progreso()


# ─── API pública ────────────────────────────────────────────────────────────

## Episodios del catálogo: id, titulo, paginas (rutas) y num_paginas.
func episodios() -> Array[Dictionary]:
	return _episodios.duplicate()


## Autor, título de la obra, licencia y enlace, para la pantalla de créditos.
func atribucion() -> Dictionary:
	return _atribucion


## Textura de una página, o null si el episodio o el índice no existen.
func pagina(episode_id: String, indice: int) -> Texture2D:
	var ep := _episodio(episode_id)
	if ep.is_empty() or indice < 0 or indice >= ep["num_paginas"]:
		return null
	var ruta: String = DIR_COMICS + ep["paginas"][indice]
	if not ResourceLoader.exists(ruta):
		return null
	return load(ruta) as Texture2D


## Bocadillos de una página (x, y, ancho, alto relativos 0-1 y texto).
## Lista vacía si no hay ninguno o la página no existe.
func bocadillos(episode_id: String, indice: int) -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	var por_pagina: Array = _bocadillos.get(episode_id, [])
	if indice < 0 or indice >= por_pagina.size():
		return resultado
	for b in por_pagina[indice]:
		resultado.append(b)
	return resultado


## Dónde se quedó el alumno. Sin datos (o sin red) devuelve ceros.
func progreso(episode_id: String) -> Dictionary:
	var p: Dictionary = _progreso.get(episode_id, {})
	return {"last_page": _acotar_pagina(episode_id, int(p.get("last_page", 0))), "finished": bool(p.get("finished", false))}


## Guarda el progreso en memoria y lo manda al servidor (o lo deja pendiente).
func guardar_progreso(episode_id: String, last_page: int, finished: bool) -> void:
	if _episodio(episode_id).is_empty():
		return
	last_page = _acotar_pagina(episode_id, last_page)
	_progreso[episode_id] = {"last_page": last_page, "finished": finished}
	var cuerpo := {"last_page": last_page, "finished": finished}
	# Sin sesión no hay cuenta a la que atribuir el progreso: solo queda en memoria.
	if not AuthManager.is_authenticated:
		return
	_encolar("PUT", "/comics/progress/%s" % episode_id, cuerpo, {"episode_id": episode_id})


## Cuenta una visita a la zona de cómics.
func registrar_visita() -> void:
	if not AuthManager.is_authenticated:
		return
	_encolar("POST", "/comics/visit", {}, {})


## Baja el progreso del servidor y reenvía lo que quedó pendiente.
func cargar_progreso() -> void:
	# El progreso en memoria es de la cuenta anterior: empezar de cero.
	_progreso.clear()
	if not AuthManager.is_authenticated:
		progreso_cargado.emit()
		return
	_reenviar_pendientes()
	_encolar("GET", "/comics/progress", {}, {})


# ─── Catálogo ───────────────────────────────────────────────────────────────

func _cargar_catalogo() -> void:
	var datos = JSON.parse_string(FileAccess.get_file_as_string(RUTA_CATALOGO))
	if not (datos is Dictionary):
		push_error("[ComicLibrary] No se pudo leer el catálogo: %s" % RUTA_CATALOGO)
		return
	_atribucion = datos.get("atribucion", {})
	for ep in datos.get("episodios", []):
		var paginas: Array = ep.get("paginas", [])
		_episodios.append({
			"id": ep["id"],
			"titulo": ep.get("titulo", ""),
			"paginas": paginas,
			"num_paginas": paginas.size(),
		})
		_bocadillos[ep["id"]] = ep.get("bocadillos", [])
	print("[ComicLibrary] Catálogo cargado: %d episodios" % _episodios.size())


## Mantiene la página dentro del episodio empaquetado.
func _acotar_pagina(episode_id: String, last_page: int) -> int:
	var ep := _episodio(episode_id)
	if ep.is_empty():
		return 0
	return clampi(last_page, 0, maxi(ep["num_paginas"] - 1, 0))


func _al_cerrar_sesion() -> void:
	_progreso.clear()
	_cola.clear()
	_visitas = 0
	# Sin esto, la respuesta en vuelo de la cuenta anterior se aplicaría al
	# primer elemento de la cola de la cuenta siguiente.
	_http.cancel_request()
	_ocupado = false


func _episodio(episode_id: String) -> Dictionary:
	for ep in _episodios:
		if ep["id"] == episode_id:
			return ep
	return {}


# ─── Respuestas del servidor ────────────────────────────────────────────────

## Vuelca la respuesta de GET /comics/progress en memoria. Las filas de episodios
## que este juego no tiene se ignoran: el catálogo manda.
func _aplicar_respuesta_progreso(datos: Dictionary) -> void:
	for fila in datos.get("episodios", []):
		if not (fila is Dictionary):
			continue
		var id := str(fila.get("episode_id", ""))
		if _episodio(id).is_empty():
			continue
		_progreso[id] = {
			"last_page": int(fila.get("last_page", 0)),
			"finished": bool(fila.get("finished", false)),
		}
	_visitas = int(datos.get("visitas", 0))


# ─── Cola de peticiones (mismo estilo que AuthManager) ──────────────────────

func _encolar(metodo: String, ruta: String, cuerpo: Dictionary, meta: Dictionary) -> void:
	_cola.append({"metodo": metodo, "ruta": ruta, "cuerpo": cuerpo, "meta": meta})
	_procesar_cola()


func _procesar_cola() -> void:
	if _ocupado or _cola.is_empty():
		return
	_ocupado = true
	var req: Dictionary = _cola[0]
	var cabeceras: PackedStringArray = ["Content-Type: application/json"]
	if not AuthManager.auth_token.is_empty():
		cabeceras.append("Authorization: Bearer %s" % AuthManager.auth_token)
	# Igual que AuthManager: el servidor rechaza con 409 si el slot o la versión
	# de sesión ya no son los activos.
	if AuthManager.current_slot_id > 0:
		cabeceras.append("X-Slot-Id: %d" % AuthManager.current_slot_id)
	if AuthManager.current_session_version > 0:
		cabeceras.append("X-Session-Version: %d" % AuthManager.current_session_version)
	var metodo := HTTPClient.METHOD_GET
	match req["metodo"]:
		"PUT": metodo = HTTPClient.METHOD_PUT
		"POST": metodo = HTTPClient.METHOD_POST
	var cuerpo := "" if req["metodo"] == "GET" else JSON.stringify(req["cuerpo"])
	var err := _http.request(ApiConfig.BASE_URL + req["ruta"], cabeceras, metodo, cuerpo)
	if err != OK:
		_cola.remove_at(0)
		_ocupado = false
		_al_fallar(req)
		_procesar_cola()


func _al_completar_peticion(result: int, codigo: int, _cabeceras: PackedStringArray, body: PackedByteArray) -> void:
	if _cola.is_empty():
		_ocupado = false
		return
	var req: Dictionary = _cola[0]
	_cola.remove_at(0)
	_ocupado = false
	if codigo == 409 and _es_sesion_invalidada(body):
		# La sesión ya no es la activa: lo que se lee no es de esta cuenta/slot.
		# No se deja como pendiente; AuthManager expulsa y limpia (señal).
		AuthManager._handle_session_invalidated(_detalle_409(body))
		return
	if result != HTTPRequest.RESULT_SUCCESS or codigo < 200 or codigo >= 300:
		_al_fallar(req)
	else:
		# JSON.new() en vez de parse_string: un cuerpo inválido no debe lanzar error.
		var json := JSON.new()
		var datos = json.data if json.parse(body.get_string_from_utf8()) == OK else null
		if req["metodo"] == "GET":
			# Se emite aunque el cuerpo no sea válido (proxy, HTML de error...).
			if datos is Dictionary:
				_aplicar_respuesta_progreso(datos)
			progreso_cargado.emit()
		elif req["metodo"] == "POST" and datos is Dictionary:
			_visitas = int(datos.get("visitas", _visitas))
	_procesar_cola()


func _detalle_409(body: PackedByteArray) -> String:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
		return str(json.data.get("detail", ""))
	return ""


func _es_sesion_invalidada(body: PackedByteArray) -> bool:
	var detalle := _detalle_409(body)
	return detalle == "SESSION_INVALIDATED" or detalle == "WORKSPACE_INACTIVE"


func _al_fallar(req: Dictionary) -> void:
	push_warning("[ComicLibrary] Falló %s %s" % [req["metodo"], req["ruta"]])
	match req["metodo"]:
		"PUT":
			_guardar_pendiente(req["meta"]["episode_id"], req["cuerpo"])
		"GET":
			# Sin red el catálogo sigue abierto y el progreso a cero.
			progreso_cargado.emit()


# ─── Escrituras pendientes (sin red) ────────────────────────────────────────

## El archivo agrupa por id de usuario: {"7": {"ep01": {...}}}. Así lo pendiente
## de un alumno nunca se reenvía con el token de otro en un equipo compartido.
func _leer_pendientes() -> Dictionary:
	if not FileAccess.file_exists(ARCHIVO_PENDIENTE):
		return {}
	var datos = JSON.parse_string(FileAccess.get_file_as_string(ARCHIVO_PENDIENTE))
	if not (datos is Dictionary):
		return {}
	# Formato antiguo: claves de episodio ("ep01") en vez de id de usuario. No se
	# sabe de quién es, así que no se puede subir sin atribuirlo a otra cuenta: se descarta.
	for clave in datos:
		if not str(clave).is_valid_int():
			push_warning("[ComicLibrary] Descartado comics_pendiente.json del formato antiguo")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ARCHIVO_PENDIENTE))
			return {}
	return datos


func _escribir_pendientes(todos: Dictionary) -> void:
	var f := FileAccess.open(ARCHIVO_PENDIENTE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(todos))
		f.close()


## Solo importa lo último que hizo el alumno en cada episodio.
func _guardar_pendiente(episode_id: String, cuerpo: Dictionary) -> void:
	var todos := _leer_pendientes()
	var clave := str(AuthManager.get_user_id())
	var suyos: Dictionary = todos.get(clave, {})
	suyos[episode_id] = cuerpo
	todos[clave] = suyos
	_escribir_pendientes(todos)


func _reenviar_pendientes() -> void:
	var todos := _leer_pendientes()
	var clave := str(AuthManager.get_user_id())
	var suyos: Dictionary = todos.get(clave, {})
	if suyos.is_empty():
		return
	todos.erase(clave)
	_escribir_pendientes(todos)
	for id in suyos:
		var c: Dictionary = suyos[id]
		if _episodio(id).is_empty():
			continue
		_progreso[id] = {"last_page": _acotar_pagina(id, int(c.get("last_page", 0))), "finished": bool(c.get("finished", false))}
		_encolar("PUT", "/comics/progress/%s" % id, c, {"episode_id": id})
