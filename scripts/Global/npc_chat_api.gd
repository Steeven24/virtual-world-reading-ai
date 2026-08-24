## Servicio HTTP para comunicarse con los endpoints /npc/* de LecturaIA.
## Registrar como Autoload en Project Settings → Autoload con nombre "NpcChatAPI".
##
## Uso típico:
##   NpcChatAPI.chat_response_received.connect(_on_chat_response)
##   NpcChatAPI.send_message("¿De qué trata el texto?")
##
## El reading_id y typology se obtienen automáticamente de GameSession.
##
## IMPORTANTE — cómo indexa el backend las conversaciones:
## LecturaIA guarda la conversación bajo la clave (student_identifier, reading_id).
## De ahí salen las dos reglas que este autoload debe respetar:
##   1. El student_identifier tiene que ser ESTABLE entre ejecuciones del juego,
##      o el tutor tratará al mismo alumno como uno nuevo cada vez.
##   2. El historial local pertenece a UNA lectura. Al cambiar de escenario hay
##      que vaciarlo, o el panel arrastrará los mensajes del escenario anterior.
extends Node

# ─── Señales ─────────────────────────────────────────────────────────────────

## Emitida cuando se recibe una respuesta exitosa del tutor IA.
signal chat_response_received(conversation_id: String, response_text: String)

## Emitida ante cualquier error de red o respuesta inesperada.
signal chat_request_failed(error: String)

## Emitida cuando /npc/history devuelve la conversación de una lectura.
signal history_loaded(reading_id: int, messages: Array)

## Emitida si no se pudo recuperar el historial remoto.
signal history_load_failed(error: String)

## Emitida cuando el historial local se vacía (cambio de lectura, logout, reset).
signal history_cleared()

# ─── Estado interno ──────────────────────────────────────────────────────────

## Identificador estable del alumno, derivado del usuario autenticado.
## Formato "vw-<user_id>": el prefijo evita colisionar con los usuarios propios
## de LecturaIA, que comparte backend con el mundo virtual.
var student_identifier: String = ""

## ID de la conversación activa en el backend (UUID; "" = sin conversación).
## Ojo: el backend responde "conversation_id" (string), no "session_id" (int).
var current_conversation_id: String = ""

## Historial local de mensajes para renderizar en la UI.
## Cada elemento: { "role": "user"|"assistant", "content": "..." }
var chat_history: Array[Dictionary] = []

## Máximo de mensajes en el historial local (para no sobrecargar la UI).
const MAX_LOCAL_HISTORY: int = 20

## Tipo de NPC para rastreo de interacciones ("robot" o "sabio").
## Debe configurarse antes de enviar mensajes según el NPC activo.
var active_npc_type: String = "robot"

## Prefijo del identificador de alumno enviado a LecturaIA.
const ID_PREFIX: String = "vw-"

## Archivo donde se persiste el identificador de invitado (sin login).
const GUEST_ID_FILE: String = "user://npc_guest_id.cfg"

## Claves bajo las que el backend puede devolver el texto de la respuesta,
## en orden de preferencia. LecturaIA hoy las manda todas duplicadas, pero no
## damos por hecho que eso siga siendo así.
const RESPONSE_KEYS: Array[String] = ["reply", "response", "message", "text", "answer"]

## reading_id al que pertenece chat_history (-1 = ninguno todavía).
var _history_reading_id: int = -1

var _http: HTTPRequest
var _history_http: HTTPRequest
var _is_requesting: bool = false
var _is_loading_history: bool = false
var _pending_history_reading_id: int = -1

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	# El identificador sale del usuario autenticado, no de un UUID aleatorio.
	# AuthManager es un autoload anterior a este, así que su sesión restaurada
	# desde disco ya está disponible aquí.
	_refresh_student_identifier()
	AuthManager.login_success.connect(_on_login_success)
	AuthManager.logged_out.connect(_on_logged_out)

	_http = HTTPRequest.new()
	_http.timeout = ApiConfig.NPC_CHAT_TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	# HTTPRequest aparte: pedir el historial no debe pisar un chat en vuelo.
	_history_http = HTTPRequest.new()
	_history_http.timeout = ApiConfig.TIMEOUT_SECONDS
	add_child(_history_http)
	_history_http.request_completed.connect(_on_history_completed)


# ─── API Pública ─────────────────────────────────────────────────────────────

## Configura el tipo de NPC activo para el rastreo de interacciones.
func set_npc_type(npc_type: String) -> void:
	if npc_type in ["robot", "sabio"]:
		active_npc_type = npc_type


## Prepara el chat para la lectura indicada.
## Si es distinta de la que tiene el historial local, lo vacía: cada escenario
## arranca mostrando solo su propia conversación.
## Retorna true si hubo que limpiar.
func begin_scenario(reading_id: int) -> bool:
	if reading_id == _history_reading_id:
		return false

	_history_reading_id = reading_id
	current_conversation_id = ""
	chat_history.clear()
	history_cleared.emit()
	print("[NpcChatAPI] Historial local vaciado al entrar a la lectura %d" % reading_id)
	return true


## Solicita al backend la conversación guardada de una lectura.
## Si reading_id <= 0 se usa la lectura activa de GameSession.
## El resultado llega por history_loaded / history_load_failed.
func fetch_history(reading_id: int = -1) -> void:
	if reading_id <= 0:
		reading_id = _get_reading_id()

	if reading_id <= 0:
		history_load_failed.emit("No hay una lectura activa.")
		return

	if _is_loading_history:
		return

	_pending_history_reading_id = reading_id
	var url := "%s/npc/history?student_identifier=%s&reading_id=%d" % [
		ApiConfig.NPC_CHAT_BASE_URL,
		student_identifier.uri_encode(),
		reading_id,
	]

	_is_loading_history = true
	var err := _history_http.request(url, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		_is_loading_history = false
		_pending_history_reading_id = -1
		var error_msg := "Error al pedir el historial: %s" % error_string(err)
		push_warning("[NpcChatAPI] %s" % error_msg)
		history_load_failed.emit(error_msg)


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

	# Si la lectura cambió desde la última vez, el historial anterior no aplica.
	begin_scenario(reading_id)

	# Agregar mensaje del usuario al historial local
	_add_to_history("user", message)

	# Construir el body de la petición
	var body := {
		"student_identifier": student_identifier,
		"reading_id": reading_id,
		"typology": typology,
		"message": message,
	}

	# Continuar la conversación existente si el backend ya nos dio una.
	if not current_conversation_id.is_empty():
		body["conversation_id"] = current_conversation_id

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


## Retorna true si hay una petición de chat en curso.
func is_requesting() -> bool:
	return _is_requesting


## Retorna true si se está recuperando el historial remoto.
func is_loading_history() -> bool:
	return _is_loading_history


## Reinicia la sesión de chat (nueva conversación, historial vacío).
func reset_session() -> void:
	current_conversation_id = ""
	chat_history.clear()
	_history_reading_id = -1
	history_cleared.emit()
	print("[NpcChatAPI] Sesión de chat reiniciada.")


## Retorna el historial de mensajes local.
func get_history() -> Array[Dictionary]:
	return chat_history


## Retorna el reading_id al que pertenece el historial local (-1 si ninguno).
func get_history_reading_id() -> int:
	return _history_reading_id


# ─── Identificador estable del alumno ───────────────────────────────────────

## Recalcula el student_identifier a partir del usuario autenticado.
## Si cambia el alumno, la conversación en memoria deja de ser suya y se limpia.
func _refresh_student_identifier() -> void:
	var previous := student_identifier
	var user_id: int = AuthManager.get_user_id() if AuthManager.is_authenticated else 0

	if user_id > 0:
		student_identifier = "%s%d" % [ID_PREFIX, user_id]
	else:
		student_identifier = _get_or_create_guest_identifier()

	if student_identifier == previous:
		return

	# Al arrancar no hay nada que limpiar; solo si el alumno cambió en caliente.
	if not previous.is_empty():
		reset_session()
	print("[NpcChatAPI] Student ID estable: %s" % student_identifier)


## Identificador de respaldo cuando no hay sesión iniciada.
## Se persiste en disco para que al menos sea estable en este dispositivo,
## en vez de regenerarse en cada arranque.
func _get_or_create_guest_identifier() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(GUEST_ID_FILE) == OK:
		var saved: String = cfg.get_value("npc", "guest_id", "")
		if not saved.is_empty():
			return saved

	var guest_id := "%sguest-%s" % [ID_PREFIX, _generate_uuid()]
	cfg.set_value("npc", "guest_id", guest_id)
	cfg.save(GUEST_ID_FILE)
	push_warning("[NpcChatAPI] Sin sesión iniciada: usando ID de invitado persistente.")
	return guest_id


func _on_login_success(_user_data: Dictionary) -> void:
	_refresh_student_identifier()


func _on_logged_out() -> void:
	_refresh_student_identifier()


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
	if not data is Dictionary:
		chat_request_failed.emit("Respuesta inesperada del servidor.")
		return

	var conversation = data.get("conversation_id")
	if conversation != null:
		current_conversation_id = str(conversation)

	var response_text := _extract_response_text(data)
	if response_text.is_empty():
		push_warning("[NpcChatAPI] La respuesta no traía texto reconocible.")
		chat_request_failed.emit("El tutor no devolvió ninguna respuesta.")
		return

	_add_to_history("assistant", response_text)
	chat_response_received.emit(current_conversation_id, response_text)

	# Registrar la interacción con el NPC para métricas del dashboard
	AuthManager.save_npc_interaction(active_npc_type, _get_reading_id())


func _on_history_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_is_loading_history = false
	var reading_id: int = _pending_history_reading_id
	_pending_history_reading_id = -1

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg := _result_to_string(result)
		push_warning("[NpcChatAPI] Error de red al pedir historial: %s" % error_msg)
		history_load_failed.emit(error_msg)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("[NpcChatAPI] Error parseando el historial")
		history_load_failed.emit("Error al procesar el historial del servidor.")
		return

	var data = json.data

	if response_code < 200 or response_code >= 300:
		var detail: String = "Error HTTP %d" % response_code
		if data is Dictionary and data.has("detail"):
			detail = str(data["detail"])
		push_warning("[NpcChatAPI] %s" % detail)
		history_load_failed.emit(detail)
		return

	if not data is Dictionary:
		history_load_failed.emit("Respuesta inesperada del servidor.")
		return

	# El servidor es la fuente de verdad: su conversación reemplaza la local.
	_history_reading_id = reading_id
	var conversation = data.get("conversation_id")
	current_conversation_id = str(conversation) if conversation != null else ""

	chat_history.clear()
	var messages = data.get("messages", [])
	if messages is Array:
		for msg in messages:
			if not msg is Dictionary:
				continue
			var role := str(msg.get("role", ""))
			if role != "user" and role != "assistant":
				continue
			chat_history.append({"role": role, "content": str(msg.get("content", ""))})

	while chat_history.size() > MAX_LOCAL_HISTORY:
		chat_history.remove_at(0)

	history_loaded.emit(reading_id, chat_history)
	print("[NpcChatAPI] Historial de la lectura %d: %d mensajes" % [reading_id, chat_history.size()])


# ─── Utilidades internas ────────────────────────────────────────────────────

## Obtiene el reading_id de la lectura activa en GameSession.
func _get_reading_id() -> int:
	var reading: Dictionary = GameSession.current_reading
	if reading.is_empty():
		return -1
	return int(reading.get("id", -1))


## Extrae el texto de la respuesta probando las claves conocidas del backend.
func _extract_response_text(data: Dictionary) -> String:
	for key in RESPONSE_KEYS:
		if not data.has(key) or data[key] == null:
			continue
		var value := str(data[key])
		if not value.strip_edges().is_empty():
			return value
	return ""


## Agrega un mensaje al historial local, respetando el límite.
func _add_to_history(role: String, content: String) -> void:
	chat_history.append({"role": role, "content": content})
	# Recortar si excede el máximo
	while chat_history.size() > MAX_LOCAL_HISTORY:
		chat_history.remove_at(0)


## Genera un UUID v4 simplificado usando los recursos disponibles en GDScript.
## Ya solo se usa para el identificador de invitado, que sí se persiste a disco.
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
