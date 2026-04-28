## Servicio HTTP centralizado para consumir la API de lecturas.
## Registrar como Autoload en Project Settings → Autoload con nombre "ReadingAPI".
##
## Uso típico:
##   ReadingAPI.reading_loaded.connect(_on_lectura_cargada)
##   ReadingAPI.get_reading(42)
##
## Todas las operaciones son asíncronas y comunican resultados mediante señales.
extends Node

# ─── Señales ─────────────────────────────────────────────────────────────────

## Emitida cuando se recibe una respuesta paginada de lecturas.
signal readings_loaded(data: Dictionary)

## Emitida cuando se recibe una lectura individual.
signal reading_loaded(data: Dictionary)

## Emitida cuando se recibe una lectura aleatoria.
signal random_reading_loaded(data: Dictionary)

## Emitida cuando se recibe una lectura completa con preguntas y respuestas.
signal full_reading_loaded(data: Dictionary)

## Emitida cuando se recibe la lista de tipologías.
signal typologies_loaded(data: Array)

## Emitida cuando se marca una lectura como vista (futuro).
signal reading_marked(user_id: String, reading_id: int)

## Emitida ante cualquier error de red o respuesta inesperada.
signal request_failed(endpoint: String, error: String)

# ─── Estado interno ─────────────────────────────────────────────────────────

var _cache: ReadingCache
var _http: HTTPRequest
var _request_queue: Array[Dictionary] = []
var _is_requesting: bool = false

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	_cache = ReadingCache.new()
	_http = HTTPRequest.new()
	_http.timeout = ApiConfig.TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


# ─── API Pública ─────────────────────────────────────────────────────────────

## Lista lecturas con paginación, filtro por tipología y búsqueda.
func list_readings(
	page: int = 1,
	per_page: int = ApiConfig.DEFAULT_PER_PAGE,
	typology: String = "",
	q: String = "",
	sort: String = "created_at",
	order: String = "desc"
) -> void:
	var cache_key := ReadingCache.make_page_key(typology, page, per_page, q)
	var cached := _cache.get_cached_page(cache_key)
	if not cached.is_empty():
		readings_loaded.emit(cached)
		return

	var params: PackedStringArray = [
		"page=%d" % page,
		"per_page=%d" % per_page,
		"sort=%s" % sort,
		"order=%s" % order,
	]
	if not typology.is_empty():
		params.append("typology=%s" % typology.uri_encode())
	if not q.is_empty():
		params.append("q=%s" % q.uri_encode())

	var url := "%s/readings?%s" % [ApiConfig.BASE_URL, "&".join(params)]
	_enqueue_request(url, "list_readings", {"cache_key": cache_key})


## Obtiene una lectura individual por su ID.
func get_reading(reading_id: int) -> void:
	var cached := _cache.get_cached_reading(reading_id)
	if not cached.is_empty():
		reading_loaded.emit(cached)
		return

	var url := "%s/readings/%d" % [ApiConfig.BASE_URL, reading_id]
	_enqueue_request(url, "get_reading", {"reading_id": reading_id})


## Obtiene una lectura aleatoria, opcionalmente filtrada por tipología.
func get_random_reading(typology: String = "") -> void:
	var url := "%s/readings/random" % ApiConfig.BASE_URL
	if not typology.is_empty():
		url += "?typology=%s" % typology.uri_encode()
	_enqueue_request(url, "random_reading", {})


## Obtiene una lectura aleatoria COMPLETA con preguntas y respuestas.
## Ideal para poblar los desafíos dinámicos.
func get_random_reading_full(typology: String = "") -> void:
	var url := "%s/readings/random/full" % ApiConfig.BASE_URL
	if not typology.is_empty():
		url += "?typology=%s" % typology.uri_encode()
	_enqueue_request(url, "full_reading", {})


## Obtiene una lectura completa por ID con preguntas y respuestas.
func get_reading_full(reading_id: int) -> void:
	var cached := _cache.get_cached_full_reading(reading_id)
	if not cached.is_empty():
		full_reading_loaded.emit(cached)
		return
	var url := "%s/readings/%d/full" % [ApiConfig.BASE_URL, reading_id]
	_enqueue_request(url, "full_reading", {"reading_id": reading_id})


## Lista las tipologías disponibles con su conteo.
func list_typologies() -> void:
	var url := "%s/typologies" % ApiConfig.BASE_URL
	_enqueue_request(url, "typologies", {})


## Busca lecturas por texto, opcionalmente filtradas por tipología.
func search_readings(query: String, typology: String = "", page: int = 1) -> void:
	list_readings(page, ApiConfig.DEFAULT_PER_PAGE, typology, query)


## Marca una lectura como vista (futuro endpoint).
## Por ahora solo registra localmente en el caché.
func mark_seen(user_id: String, reading_id: int) -> void:
	# Registro local inmediato
	_cache.add_seen_id(reading_id)

	# Cuando el endpoint esté disponible, descomentar:
	# var url := "%s/users/%s/readings/%d/mark-read" % [
	#     ApiConfig.BASE_URL, user_id.uri_encode(), reading_id
	# ]
	# _enqueue_request(url, "mark_seen", {
	#     "user_id": user_id, "reading_id": reading_id
	# }, HTTPClient.METHOD_POST)

	reading_marked.emit(user_id, reading_id)


## Verifica si la API está disponible (health check).
func check_health(callback: Callable) -> void:
	var url := "%s/health" % ApiConfig.BASE_URL
	_enqueue_request(url, "health", {"callback": callback})


## Retorna la lista de IDs vistos localmente (para filtrar en cliente).
func get_seen_ids() -> Array:
	return _cache.get_seen_ids()


# ─── Cola de peticiones ─────────────────────────────────────────────────────

func _enqueue_request(
	url: String,
	endpoint: String,
	meta: Dictionary,
	method: int = HTTPClient.METHOD_GET
) -> void:
	_request_queue.append({
		"url": url,
		"endpoint": endpoint,
		"meta": meta,
		"method": method,
		"retries": 0,
	})
	_process_queue()


func _process_queue() -> void:
	if _is_requesting or _request_queue.is_empty():
		return

	_is_requesting = true
	var req: Dictionary = _request_queue[0]
	var headers: PackedStringArray = ["Content-Type: application/json"]

	# Agregar token de autenticación si existe
	if not ApiConfig.AUTH_TOKEN.is_empty():
		headers.append("Authorization: Bearer %s" % ApiConfig.AUTH_TOKEN)

	var err := _http.request(req["url"], headers, req["method"])
	if err != OK:
		push_error("[ReadingAPI] Error al iniciar petición: %s → %s" % [req["endpoint"], error_string(err)])
		_handle_retry_or_fail(req)


# ─── Manejo de respuestas ───────────────────────────────────────────────────

func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if _request_queue.is_empty():
		_is_requesting = false
		return

	var req: Dictionary = _request_queue[0]
	_request_queue.remove_at(0)
	_is_requesting = false

	# Error de red o timeout
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg := _result_to_string(result)
		push_warning("[ReadingAPI] Error de red en %s: %s" % [req["endpoint"], error_msg])
		_handle_retry_or_fail(req, error_msg)
		return

	# Respuesta HTTP con error
	if response_code < 200 or response_code >= 300:
		var error_msg := "HTTP %d" % response_code
		push_warning("[ReadingAPI] %s en %s" % [error_msg, req["endpoint"]])
		# No reintentar errores 4xx (son del cliente)
		if response_code >= 400 and response_code < 500:
			request_failed.emit(req["endpoint"], error_msg)
			_process_queue()
			return
		_handle_retry_or_fail(req, error_msg)
		return

	# Parsear JSON
	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_error("[ReadingAPI] Error parseando JSON de %s" % req["endpoint"])
		request_failed.emit(req["endpoint"], "Error de parseo JSON")
		_process_queue()
		return

	var data = json.data
	_dispatch_response(req, data)
	_process_queue()


func _dispatch_response(req: Dictionary, data) -> void:
	match req["endpoint"]:
		"list_readings":
			if data is Dictionary:
				var cache_key: String = req["meta"].get("cache_key", "")
				if not cache_key.is_empty():
					_cache.cache_page(cache_key, data)
				readings_loaded.emit(data)

		"get_reading":
			if data is Dictionary:
				var reading_id: int = req["meta"].get("reading_id", 0)
				if reading_id > 0:
					_cache.cache_reading(reading_id, data)
				reading_loaded.emit(data)

		"random_reading":
			if data is Dictionary:
				var rid = data.get("id", 0)
				if rid is int and rid > 0:
					_cache.cache_reading(rid, data)
				random_reading_loaded.emit(data)

		"full_reading":
			if data is Dictionary:
				var rid = data.get("id", 0)
				if rid is int and rid > 0:
					_cache.cache_full_reading(rid, data)
				full_reading_loaded.emit(data)

		"typologies":
			if data is Dictionary and data.has("typologies"):
				typologies_loaded.emit(data["typologies"])

		"health":
			var cb: Callable = req["meta"].get("callback", Callable())
			if cb.is_valid():
				cb.call(data)

		"mark_seen":
			var uid: String = req["meta"].get("user_id", "")
			var rid: int = req["meta"].get("reading_id", 0)
			reading_marked.emit(uid, rid)


# ─── Reintentos con backoff exponencial ─────────────────────────────────────

func _handle_retry_or_fail(req: Dictionary, error_msg: String = "Error desconocido") -> void:
	req["retries"] += 1
	if req["retries"] <= ApiConfig.MAX_RETRIES:
		var delay: float = ApiConfig.BACKOFF_BASE * pow(2.0, req["retries"] - 1)
		push_warning("[ReadingAPI] Reintento %d/%d para %s en %.1fs" % [
			req["retries"], ApiConfig.MAX_RETRIES, req["endpoint"], delay
		])
		# Reinsertar al inicio de la cola y esperar
		_request_queue.push_front(req)
		await get_tree().create_timer(delay).timeout
		_process_queue()
	else:
		push_error("[ReadingAPI] Falló tras %d reintentos: %s → %s" % [
			ApiConfig.MAX_RETRIES, req["endpoint"], error_msg
		])
		# Intentar servir del caché expirado como último recurso
		_try_fallback_cache(req, error_msg)


func _try_fallback_cache(req: Dictionary, error_msg: String) -> void:
	match req["endpoint"]:
		"get_reading":
			var rid: int = req["meta"].get("reading_id", 0)
			var cached := _cache.get_cached_reading(rid, true)  # allow_expired
			if not cached.is_empty():
				push_warning("[ReadingAPI] Sirviendo lectura %d desde caché expirado" % rid)
				reading_loaded.emit(cached)
				_process_queue()
				return
		"list_readings":
			var cache_key: String = req["meta"].get("cache_key", "")
			var cached := _cache.get_cached_page(cache_key, true)
			if not cached.is_empty():
				push_warning("[ReadingAPI] Sirviendo página desde caché expirado")
				readings_loaded.emit(cached)
				_process_queue()
				return

	request_failed.emit(req["endpoint"], error_msg)
	_process_queue()


# ─── Utilidades ─────────────────────────────────────────────────────────────

func _result_to_string(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "No se pudo conectar al servidor"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "No se pudo resolver el host"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Error de conexión"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Error de TLS/SSL"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "Sin respuesta del servidor"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Petición fallida"
		HTTPRequest.RESULT_TIMEOUT:
			return "Timeout de la petición"
		_:
			return "Error HTTP desconocido (%d)" % result
