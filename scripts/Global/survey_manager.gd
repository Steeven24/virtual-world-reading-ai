## Cliente de la encuesta SUS + TAM. El servidor es la autoridad: solo marca el
## slot como completado tras recibir una respuesta válida y persistida.
extends Node

signal status_ready(completed: bool, error: String)
signal submission_finished(success: bool, error: String)

var _http: HTTPRequest
var _operation := ""
var _busy := false
var _known_key := ""
var _completed := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = ApiConfig.TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	AuthManager.logged_out.connect(_reset)
	AuthManager.session_invalidated.connect(_reset)
	AuthManager.login_success.connect(func(_data): _reset())


func _current_key() -> String:
	return "%s:%s:%s" % [
		AuthManager.current_user.get("id", 0),
		AuthManager.current_slot_id,
		AuthManager.current_session_version,
	]


func is_completed_for_current_slot() -> bool:
	return _known_key == _current_key() and _completed


func has_known_status() -> bool:
	return _known_key == _current_key()


func check_status() -> void:
	if not AuthManager.is_authenticated:
		status_ready.emit(false, "No hay una sesión activa.")
		return
	if has_known_status():
		status_ready.emit.call_deferred(_completed, "")
		return
	_request("status", HTTPClient.METHOD_GET, "/evaluation/survey/status", {})


func submit(sus: Array, tam_usefulness: Array, tam_ease: Array) -> void:
	if not AuthManager.is_authenticated:
		submission_finished.emit(false, "No hay una sesión activa.")
		return
	if sus.size() != 10 or tam_usefulness.size() != 6 or tam_ease.size() != 6:
		submission_finished.emit(false, "Faltan respuestas por completar.")
		return
	_request("submit", HTTPClient.METHOD_POST, "/evaluation/survey", {
		"sus": sus,
		"tam_usefulness": tam_usefulness,
		"tam_ease": tam_ease,
	})


func _request(operation: String, method: int, path: String, data: Dictionary) -> void:
	if _busy:
		_emit_result(operation, false, "La encuesta ya está procesando una solicitud.")
		return
	_busy = true
	_operation = operation
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not AuthManager.auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % AuthManager.auth_token)
	if AuthManager.current_slot_id > 0:
		headers.append("X-Slot-Id: %d" % AuthManager.current_slot_id)
	if AuthManager.current_session_version > 0:
		headers.append("X-Session-Version: %d" % AuthManager.current_session_version)
	var body := "" if method == HTTPClient.METHOD_GET else JSON.stringify(data)
	var err := _http.request(ApiConfig.BASE_URL + path, headers, method, body)
	if err != OK:
		_busy = false
		_operation = ""
		_emit_result(operation, false, "No se pudo conectar con el servidor.")


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _busy:
		return
	var operation := _operation
	_busy = false
	_operation = ""
	var json := JSON.new()
	var data = json.data if json.parse(body.get_string_from_utf8()) == OK else null
	var detail := str(data.get("detail", "")) if data is Dictionary else ""
	if code == 409 and detail in ["SESSION_INVALIDATED", "WORKSPACE_INACTIVE"]:
		AuthManager._handle_session_invalidated(detail)
		_emit_result(operation, false, "La sesión dejó de estar activa.")
		return
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var message := "No se pudo guardar la encuesta. Inténtalo de nuevo."
		if detail == "SURVEY_NOT_AVAILABLE":
			message = "La encuesta se habilita al aprobar las cuatro tipologías."
		_emit_result(operation, false, message)
		return
	if not data is Dictionary:
		_emit_result(operation, false, "El servidor devolvió una respuesta inválida.")
		return
	_completed = bool(data.get("completed", false))
	_known_key = _current_key()
	_emit_result(operation, _completed if operation == "submit" else true, "")


func _emit_result(operation: String, success: bool, error: String) -> void:
	if operation == "status":
		status_ready.emit(_completed if success else false, error)
	else:
		submission_finished.emit(success, error)


func _reset() -> void:
	if _http:
		_http.cancel_request()
	_busy = false
	_operation = ""
	_known_key = ""
	_completed = false
