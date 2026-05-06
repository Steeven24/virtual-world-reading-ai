## Servicio HTTP para comunicarse con el endpoint /npc/chat de LecturaIA.
## Registrar como Autoload en Project Settings → Autoload con nombre "NpcChatAPI".
##
## Uso típico:
##   NpcChatAPI.chat_response_received.connect(_on_chat_response)
##   NpcChatAPI.send_message("¿De qué trata el texto?")
##
## El reading_id y typology se obtienen automáticamente de GameSession.
extends Node

# ─── Señales ─────────────────────────────────────────────────────────────────

## Emitida cuando se recibe una respuesta exitosa del tutor IA.
signal chat_response_received(session_id: int, response_text: String)

## Emitida ante cualquier error de red o respuesta inesperada.
signal chat_request_failed(error: String)

# ─── Estado interno ──────────────────────────────────────────────────────────

## Identificador temporal del estudiante. Se regenera cada vez que el juego inicia.
var student_identifier: String = ""

## ID de la sesión de chat activa en el backend (-1 = sin sesión).
var current_session_id: int = -1

## Historial local de mensajes para renderizar en la UI.
## Cada elemento: { "role": "user"|"assistant", "content": "..." }
var chat_history: Array[Dictionary] = []

## Máximo de mensajes en el historial local (para no sobrecargar la UI).
const MAX_LOCAL_HISTORY: int = 20

var _http: HTTPRequest
var _is_requesting: bool = false

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	# Generar UUID temporal (se reinicia cada ejecución del juego)
	student_identifier = _generate_uuid()
	print("[NpcChatAPI] Student ID temporal: %s" % student_identifier)

	_http = HTTPRequest.new()
	_http.timeout = ApiConfig.NPC_CHAT_TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


# ─── API Pública ─────────────────────────────────────────────────────────────

## Envía un mensaje al tutor NPC. Los datos de lectura se obtienen de GameSession.
## Si no hay lectura activa, emite chat_request_failed.
func send_message(message: String) -> void:
	if _is_requesting:
		push_warning("[NpcChatAPI] Ya hay una petición en curso, ignorando.")
		return

	if message.strip_edges().is_empty():
		chat_request_failed.emit("El mensaje está vacío.")
		return

	# Obtener datos de la lectura activa
	var reading_id: int = _get_reading_id()
	var typology: String = GameSession.current_typology

	if reading_id <= 0:
		chat_request_failed.emit("No hay una lectura activa para consultar.")
		return

	if typology.is_empty():
		chat_request_failed.emit("No se ha definido la tipología de la lectura.")
		return

	# Agregar mensaje del usuario al historial local
	_add_to_history("user", message)

	# Construir el body de la petición
	var body := {
		"student_identifier": student_identifier,
		"reading_id": reading_id,
		"typology": typology,
		"message": message,
	}

	# Enviar session_id si ya tenemos una sesión activa
	if current_session_id > 0:
		body["session_id"] = current_session_id

	var json_body := JSON.stringify(body)
	var url := "%s/npc/chat" % ApiConfig.NPC_CHAT_BASE_URL
	var headers: PackedStringArray = ["Content-Type: application/json"]

	_is_requesting = true
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_is_requesting = false
		var error_msg := "Error al iniciar petición: %s" % error_string(err)
		push_error("[NpcChatAPI] %s" % error_msg)
		chat_request_failed.emit(error_msg)


## Retorna true si hay una petición en curso.
func is_requesting() -> bool:
	return _is_requesting


## Reinicia la sesión de chat (nueva conversación).
func reset_session() -> void:
	current_session_id = -1
	chat_history.clear()
	print("[NpcChatAPI] Sesión de chat reiniciada.")


## Retorna el historial de mensajes local.
func get_history() -> Array[Dictionary]:
	return chat_history


# ─── Manejo de respuestas ───────────────────────────────────────────────────

func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_is_requesting = false

	# Error de red o timeout
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg := _result_to_string(result)
		push_warning("[NpcChatAPI] Error de red: %s" % error_msg)
		chat_request_failed.emit(error_msg)
		return

	# Parsear JSON
	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_error("[NpcChatAPI] Error parseando respuesta JSON")
		chat_request_failed.emit("Error al procesar la respuesta del servidor.")
		return

	var data = json.data

	# Error HTTP (4xx, 5xx)
	if response_code < 200 or response_code >= 300:
		var detail: String = "Error HTTP %d" % response_code
		if data is Dictionary and data.has("detail"):
			detail = str(data["detail"])
		push_warning("[NpcChatAPI] %s" % detail)
		chat_request_failed.emit(detail)
		return

	# Respuesta exitosa
	if data is Dictionary:
		var session_id: int = int(data.get("session_id", -1))
		var response_text: String = str(data.get("response", ""))

		current_session_id = session_id
		_add_to_history("assistant", response_text)
		chat_response_received.emit(session_id, response_text)
	else:
		chat_request_failed.emit("Respuesta inesperada del servidor.")


# ─── Utilidades internas ────────────────────────────────────────────────────

## Obtiene el reading_id de la lectura activa en GameSession.
func _get_reading_id() -> int:
	var reading: Dictionary = GameSession.current_reading
	if reading.is_empty():
		return -1
	return int(reading.get("id", -1))


## Agrega un mensaje al historial local, respetando el límite.
func _add_to_history(role: String, content: String) -> void:
	chat_history.append({"role": role, "content": content})
	# Recortar si excede el máximo
	while chat_history.size() > MAX_LOCAL_HISTORY:
		chat_history.remove_at(0)


## Genera un UUID v4 simplificado usando los recursos disponibles en GDScript.
func _generate_uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var parts: PackedStringArray = []
	for i in 5:
		parts.append("%08x" % rng.randi())
	return "%s-%s-%s-%s-%s" % [
		parts[0],
		parts[1].substr(0, 4),
		parts[2].substr(0, 4),
		parts[3].substr(0, 4),
		parts[4] + parts[1].substr(4, 4),
	]


## Traduce códigos de resultado HTTP a mensajes legibles.
func _result_to_string(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "No se pudo conectar al servidor de chat IA"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "No se pudo resolver el host del servidor"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Error de conexión con el servidor"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Error de TLS/SSL"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "Sin respuesta del servidor"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Petición fallida"
		HTTPRequest.RESULT_TIMEOUT:
			return "La IA tardó demasiado en responder. Intenta de nuevo."
		_:
			return "Error desconocido (%d)" % result
