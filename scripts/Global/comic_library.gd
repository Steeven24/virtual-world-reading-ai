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
	if AuthManager.is_authenticated:
		cargar_progreso()


# ─── API pública ────────────────────────────────────────────────────────────

## Episodios del catálogo: id, titulo, paginas (rutas) y num_paginas.
func episodios() -> Array[Dictionary]:
	return _episodios


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
	return {"last_page": int(p.get("last_page", 0)), "finished": bool(p.get("finished", false))}


## Guarda el progreso en memoria y lo manda al servidor (o lo deja pendiente).
func guardar_progreso(episode_id: String, last_page: int, finished: bool) -> void:
	if _episodio(episode_id).is_empty():
		return
	_progreso[episode_id] = {"last_page": last_page, "finished": finished}
	var cuerpo := {"last_page": last_page, "finished": finished}
	if not AuthManager.is_authenticated:
		_guardar_pendiente(episode_id, cuerpo)
		return
	_encolar("PUT", "/comics/progress/%s" % episode_id, cuerpo, {"episode_id": episode_id})


## Cuenta una visita a la zona de cómics.
func registrar_visita() -> void:
	if not AuthManager.is_authenticated:
		return
	_encolar("POST", "/comics/visit", {}, {})


## Baja el progreso del servidor y reenvía lo que quedó pendiente.
func cargar_progreso() -> void:
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
	if result != HTTPRequest.RESULT_SUCCESS or codigo < 200 or codigo >= 300:
		_al_fallar(req)
	else:
		var datos = JSON.parse_string(body.get_string_from_utf8())
		if req["metodo"] == "GET" and datos is Dictionary:
			_aplicar_respuesta_progreso(datos)
			progreso_cargado.emit()
		elif req["metodo"] == "POST" and datos is Dictionary:
			_visitas = int(datos.get("visitas", _visitas))
	_procesar_cola()


func _al_fallar(req: Dictionary) -> void:
	push_warning("[ComicLibrary] Falló %s %s" % [req["metodo"], req["ruta"]])
	match req["metodo"]:
		"PUT":
			_guardar_pendiente(req["meta"]["episode_id"], req["cuerpo"])
		"GET":
			# Sin red el catálogo sigue abierto y el progreso a cero.
			progreso_cargado.emit()


# ─── Escrituras pendientes (sin red) ────────────────────────────────────────

func _leer_pendientes() -> Dictionary:
	if not FileAccess.file_exists(ARCHIVO_PENDIENTE):
		return {}
	var datos = JSON.parse_string(FileAccess.get_file_as_string(ARCHIVO_PENDIENTE))
	return datos if datos is Dictionary else {}


## Solo importa lo último que hizo el alumno en cada episodio.
func _guardar_pendiente(episode_id: String, cuerpo: Dictionary) -> void:
	var pendientes := _leer_pendientes()
	pendientes[episode_id] = cuerpo
	var f := FileAccess.open(ARCHIVO_PENDIENTE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(pendientes))
		f.close()


func _reenviar_pendientes() -> void:
	var pendientes := _leer_pendientes()
	if pendientes.is_empty():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ARCHIVO_PENDIENTE))
	for id in pendientes:
		var c: Dictionary = pendientes[id]
		_progreso[id] = {"last_page": int(c.get("last_page", 0)), "finished": bool(c.get("finished", false))}
		_encolar("PUT", "/comics/progress/%s" % id, c, {"episode_id": id})
