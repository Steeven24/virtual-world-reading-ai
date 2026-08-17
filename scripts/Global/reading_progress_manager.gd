## Gestor de lectura activa (progreso en curso).
## Encapsula la lógica de persistencia de lecturas interrumpidas:
## - Guardar estado al abandonar un escenario.
## - Consultar si hay lectura pendiente antes de entrar a otro.
## - Restaurar lectura pendiente al regresar al mismo escenario.
## - Limpiar lectura activa al completar todos los niveles.
##
## Comunica con la API REST (Virtual-World) a través de HTTP.
## Registrar como Autoload: Project Settings → Autoload → "ReadingProgressManager"
extends Node

# ─── Señales ─────────────────────────────────────────────────────────────────

## Emitida al cargar la lectura activa desde la API.
signal active_reading_loaded(data: Dictionary)

## Emitida al guardar la lectura activa exitosamente.
signal active_reading_saved

## Emitida al limpiar la lectura activa exitosamente.
signal active_reading_cleared

## Emitida al completar la verificación de lectura pendiente.
## has_pending: true si hay lectura en otra tipología.
## pending_typology: la tipología de la lectura pendiente.
signal active_reading_check_completed(has_pending: bool, pending_typology: String)

## Emitida ante cualquier error de red o respuesta inesperada.
signal request_failed(error: String)

# ─── Estado local ────────────────────────────────────────────────────────────

## Datos de la lectura activa (cacheados localmente tras GET).
var _active_data: Dictionary = {}

## True si hay una lectura activa conocida.
var _has_active: bool = false

## True mientras se espera una respuesta de la API.
var _is_busy: bool = false

# ─── Nodo HTTP ───────────────────────────────────────────────────────────────

var _http: HTTPRequest
var _pending_action: String = ""  # "check", "save", "clear", "load"
var _pending_body: String = ""

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = ApiConfig.TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	# Escuchar evento de sesión invalidada para limpiar cache local
	if AuthManager.has_signal("session_invalidated"):
		AuthManager.session_invalidated.connect(_on_session_invalidated)

	# Escuchar sesión completada para limpiar lectura activa
	if GameSession.has_signal("session_completed_with_data"):
		GameSession.session_completed_with_data.connect(_on_session_completed)

	# Auto-restaurar lectura activa cuando se carga el progreso tras login
	AuthManager.progress_loaded.connect(_on_progress_loaded)

	# Si ya está autenticado al iniciar (sesión restaurada desde disco),
	# consultar lectura activa inmediatamente
	if AuthManager.is_authenticated:
		call_deferred("check_pending_reading")


func _on_session_invalidated() -> void:
	_active_data.clear()
	_has_active = false
	print("[ReadingProgressManager] Cache local limpiado por sesión invalidada")


func _on_progress_loaded(_progress_data: Dictionary) -> void:
	# Tras cargar el progreso del jugador, consultar lectura activa
	print("[ReadingProgressManager] Progreso cargado, consultando lectura activa...")
	check_pending_reading()


func _on_session_completed(_typology: String, _score: int, _tools: Dictionary) -> void:
	clear_active_reading()


# ─── API Pública ─────────────────────────────────────────────────────────────

## ¿Hay una lectura activa en cache local?
func has_active_reading() -> bool:
	return _has_active


## Retorna la tipología de la lectura activa (o "" si no hay).
func get_active_typology() -> String:
	return str(_active_data.get("typology", ""))


## Retorna el reading_id de la lectura activa (o -1 si no hay).
func get_active_reading_id() -> int:
	return int(_active_data.get("reading_id", -1))


## Retorna los datos completos de la lectura activa.
func get_active_data() -> Dictionary:
	return _active_data


## Consulta la API para verificar si hay lectura pendiente.
## Emite active_reading_check_completed cuando completa.
func check_pending_reading() -> void:
	if not AuthManager.is_authenticated:
		active_reading_check_completed.emit(false, "")
		return
	if _is_busy:
		return
	_pending_action = "check"
	_do_request(
		"%s/progress/active-reading" % ApiConfig.BASE_URL,
		HTTPClient.METHOD_GET,
	)


## Guarda el estado actual de GameSession como lectura activa en la API.
## Emite active_reading_saved cuando completa.
func save_active_reading() -> void:
	if not AuthManager.is_authenticated:
		print("[ReadingProgressManager] No autenticado, guardado omitido")
		return
	if not GameSession.is_active:
		print("[ReadingProgressManager] No hay sesión activa para guardar")
		return
	if _is_busy:
		return

	var state := GameSession.serialize_state()
	var reading_id: int = state.get("reading_id", 0)
	if reading_id <= 0:
		print("[ReadingProgressManager] Reading ID inválido, guardado omitido")
		return

	var body := JSON.stringify({
		"reading_id": reading_id,
		"typology": state.get("typology", ""),
		"current_level_index": state.get("current_level_index", 0),
		"current_question_index": state.get("current_question_index", 0),
		"reading_completed": state.get("reading_completed", false),
		"session_score": state.get("session_score", 0),
		"results_json": JSON.stringify(state.get("results", [])),
		"tools_used_json": JSON.stringify(state.get("tools_used", {})),
		"reading_start_time": str(state.get("reading_start_time", 0)),
	})

	_pending_action = "save"
	_pending_body = body
	_do_request(
		"%s/progress/active-reading" % ApiConfig.BASE_URL,
		HTTPClient.METHOD_PUT,
		body,
	)


## Carga la lectura activa desde la API y restaura GameSession.
## Emite active_reading_loaded cuando completa.
func load_active_reading() -> void:
	if not AuthManager.is_authenticated:
		request_failed.emit("No autenticado")
		return
	if _is_busy:
		return
	_pending_action = "load"
	_do_request(
		"%s/progress/active-reading" % ApiConfig.BASE_URL,
		HTTPClient.METHOD_GET,
	)


## Limpia la lectura activa (tras completar sesión o por expiración).
## Emite active_reading_cleared cuando completa.
func clear_active_reading() -> void:
	# Limpiar cache local inmediatamente
	_active_data.clear()
	_has_active = false

	if not AuthManager.is_authenticated:
		active_reading_cleared.emit()
		return
	if _is_busy:
		# Encolar limpieza para después
		return
	_pending_action = "clear"
	_do_request(
		"%s/progress/active-reading" % ApiConfig.BASE_URL,
		HTTPClient.METHOD_DELETE,
	)


# ─── HTTP interno ────────────────────────────────────────────────────────────

func _do_request(url: String, method: int, body: String = "") -> void:
	_is_busy = true
	var headers: PackedStringArray = ["Content-Type: application/json"]

	if not AuthManager.auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % AuthManager.auth_token)
	if AuthManager.current_slot_id > 0:
		headers.append("X-Slot-Id: %d" % AuthManager.current_slot_id)
	if AuthManager.current_session_version > 0:
		headers.append("X-Session-Version: %d" % AuthManager.current_session_version)

	var err: int
	if body.is_empty():
		err = _http.request(url, headers, method)
	else:
		err = _http.request(url, headers, method, body)

	if err != OK:
		_is_busy = false
		push_error("[ReadingProgressManager] Error al iniciar petición: %s" % error_string(err))
		request_failed.emit("Error de conexión")


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_is_busy = false
	var action := _pending_action
	_pending_action = ""
	_pending_body = ""

	# Error de red
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[ReadingProgressManager] Error de red en %s" % action)
		_dispatch_error(action, "Error de red")
		return

	# 204 No Content (GET sin lectura activa, DELETE exitoso)
	if response_code == 204:
		match action:
			"check":
				_active_data.clear()
				_has_active = false
				active_reading_check_completed.emit(false, "")
			"load":
				_active_data.clear()
				_has_active = false
				active_reading_loaded.emit({})
			"clear":
				active_reading_cleared.emit()
		return

	# Error HTTP
	if response_code < 200 or response_code >= 300:
		var error_msg := "HTTP %d" % response_code
		push_warning("[ReadingProgressManager] %s en %s" % [error_msg, action])
		_dispatch_error(action, error_msg)
		return

	# Parsear JSON
	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_error("[ReadingProgressManager] Error parseando JSON en %s" % action)
		_dispatch_error(action, "Error de parseo")
		return

	var data = json.data

	# Despachar según acción
	match action:
		"check":
			if data is Dictionary and data.has("reading_id"):
				_active_data = data
				_has_active = true
				active_reading_check_completed.emit(true, str(data.get("typology", "")))
			else:
				_active_data.clear()
				_has_active = false
				active_reading_check_completed.emit(false, "")

		"save":
			if data is Dictionary:
				_active_data = data
				_has_active = true
			active_reading_saved.emit()
			print("[ReadingProgressManager] Lectura activa guardada en la API")

		"load":
			if data is Dictionary and data.has("reading_id"):
				_active_data = data
				_has_active = true
				active_reading_loaded.emit(data)
				print("[ReadingProgressManager] Lectura activa cargada desde la API")
			else:
				_active_data.clear()
				_has_active = false
				active_reading_loaded.emit({})

		"clear":
			_active_data.clear()
			_has_active = false
			active_reading_cleared.emit()
			print("[ReadingProgressManager] Lectura activa limpiada")


func _dispatch_error(action: String, error: String) -> void:
	match action:
		"check":
			active_reading_check_completed.emit(false, "")
		"save":
			# Falló el guardado, pero no bloqueamos al jugador
			push_warning("[ReadingProgressManager] Falló guardado: %s" % error)
		"load":
			active_reading_loaded.emit({})
		"clear":
			active_reading_cleared.emit()
	request_failed.emit(error)
