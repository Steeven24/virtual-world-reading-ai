## Gestor global de autenticación.
## Maneja login, logout, almacenamiento de token JWT y datos del usuario.
## Se conecta con la API para autenticar y sincronizar el progreso.
##
## Registrar como Autoload: Project Settings → Autoload → "AuthManager"
extends Node

# ─── Señales ─────────────────────────────────────────────────────────────────

## Emitida tras un login exitoso con los datos del usuario.
signal login_success(user_data: Dictionary)

## Emitida si el login falla.
signal login_failed(error: String)

## Emitida al registrar un usuario exitosamente.
signal register_success(user_data: Dictionary)

## Emitida si el registro falla.
signal register_failed(error: String)

## Emitida al cargar el progreso del jugador desde la API.
signal progress_loaded(progress_data: Dictionary)

## Emitida si falla la carga de progreso.
signal progress_load_failed(error: String)

## Emitida al cerrar sesión.
signal logged_out

## Emitida tras cambiar la contraseña exitosamente.
signal password_changed

## Emitida si falla el cambio de contraseña.
signal password_change_failed(error: String)

## Emitida cuando el administrador invalida o cambia la sesión/slot del jugador.
signal session_invalidated

# ─── Estado ──────────────────────────────────────────────────────────────────

## Token JWT activo (vacío = no autenticado).
var auth_token: String = ""

## Slot de sesión activo actual del jugador.
var current_slot_id: int = 0

## Datos del usuario autenticado.
var current_user: Dictionary = {}

## True si hay una sesión activa.
var is_authenticated: bool = false

## Ruta del archivo local para persistir la sesión.
const _SESSION_FILE: String = "user://session.cfg"

# ─── Nodo HTTP ───────────────────────────────────────────────────────────────

var _http: HTTPRequest
var _request_queue: Array[Dictionary] = []
var _is_requesting: bool = false

var _polling_timer: Timer
var _overlay_instance: Node = null

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = ApiConfig.TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	
	# Configurar timer de polling de validación de slot
	_polling_timer = Timer.new()
	_polling_timer.wait_time = 60.0
	_polling_timer.one_shot = false
	_polling_timer.timeout.connect(_on_polling_timeout)
	add_child(_polling_timer)
	
	# Intentar restaurar sesión guardada
	_load_saved_session()
	if is_authenticated:
		_start_polling()


# ─── API Pública ─────────────────────────────────────────────────────────────

## Inicia sesión con correo y contraseña.
func login(email: String, password: String) -> void:
	var body := JSON.stringify({"email": email, "password": password})
	_enqueue_request(
		"%s/auth/login" % ApiConfig.BASE_URL,
		"login",
		{"email": email},
		HTTPClient.METHOD_POST,
		body
	)


## Registra un nuevo usuario.
func register(email: String, password: String, display_name: String, character: String = "male") -> void:
	var body := JSON.stringify({
		"email": email,
		"password": password,
		"display_name": display_name,
		"character": character,
	})
	_enqueue_request(
		"%s/auth/register" % ApiConfig.BASE_URL,
		"register",
		{},
		HTTPClient.METHOD_POST,
		body
	)


## Carga el progreso completo del jugador desde la API.
func load_progress() -> void:
	if not is_authenticated:
		progress_load_failed.emit("No hay sesión activa")
		return
	_enqueue_request(
		"%s/progress/me" % ApiConfig.BASE_URL,
		"load_progress",
		{},
	)


## Registra una sesión completada en la API.
func save_session(session_data: Dictionary) -> void:
	if not is_authenticated:
		push_warning("[AuthManager] No autenticado, guardando sesión localmente")
		_save_pending_sync(session_data)
		return
	var body := JSON.stringify(session_data)
	_enqueue_request(
		"%s/progress/sessions" % ApiConfig.BASE_URL,
		"save_session",
		{},
		HTTPClient.METHOD_POST,
		body
	)


## Registra un logro desbloqueado en la API.
func save_achievement(achievement_id: String, achievement_name: String) -> void:
	if not is_authenticated:
		return
	var body := JSON.stringify({
		"achievement_id": achievement_id,
		"achievement_name": achievement_name,
	})
	_enqueue_request(
		"%s/progress/achievements" % ApiConfig.BASE_URL,
		"save_achievement",
		{},
		HTTPClient.METHOD_POST,
		body
	)


## Guarda una nota del jugador en la API.
func save_note(reading_id: int, note_content: String, session_id: int = -1, note_type: String = "free_text") -> void:
	if not is_authenticated:
		return
	var data := {
		"reading_id": reading_id,
		"note_content": note_content,
		"note_type": note_type,
	}
	if session_id > 0:
		data["session_id"] = session_id
	var body := JSON.stringify(data)
	_enqueue_request(
		"%s/progress/notes" % ApiConfig.BASE_URL,
		"save_note",
		{},
		HTTPClient.METHOD_POST,
		body
	)


## Cierra la sesión actual.
func logout() -> void:
	auth_token = ""
	current_user = {}
	current_slot_id = 0
	is_authenticated = false
	ApiConfig.AUTH_TOKEN = ""
	_clear_saved_session()
	_stop_polling()
	logged_out.emit()
	print("[AuthManager] Sesión cerrada")


## Permite al usuario cambiar su contraseña (ej: tras un restablecimiento).
func change_password(new_password: String) -> void:
	if not is_authenticated:
		password_change_failed.emit("No hay sesión activa")
		return
	var body := JSON.stringify({"new_password": new_password})
	_enqueue_request(
		"%s/auth/change-password" % ApiConfig.BASE_URL,
		"change_password",
		{},
		HTTPClient.METHOD_POST,
		body
	)


## Actualiza el personaje seleccionado en la API y localmente.
func update_character(character: String) -> void:
	if not is_authenticated:
		return
	current_user["character"] = character
	_save_session_to_disk()
	# Enviar actualización a la API (PUT /auth/me?character=...)
	_enqueue_request(
		"%s/auth/me?character=%s" % [ApiConfig.BASE_URL, character],
		"update_character",
		{},
		HTTPClient.METHOD_PUT,
		"",
	)
	print("[AuthManager] Personaje actualizado a: %s" % character)


## Retorna el ID del usuario autenticado.
func get_user_id() -> int:
	return current_user.get("id", 0)


## Retorna el nombre del usuario.
func get_display_name() -> String:
	return current_user.get("display_name", "Jugador")


## Retorna el personaje del usuario.
func get_character() -> String:
	return current_user.get("character", "male")


# ─── Cola de peticiones HTTP ────────────────────────────────────────────────

func _enqueue_request(url: String, endpoint: String, meta: Dictionary, method: int = HTTPClient.METHOD_GET, body: String = "") -> void:
	_request_queue.append({
		"url": url,
		"endpoint": endpoint,
		"meta": meta,
		"method": method,
		"body": body,
	})
	_process_queue()


func _process_queue() -> void:
	if _is_requesting or _request_queue.is_empty():
		return
	
	_is_requesting = true
	var req: Dictionary = _request_queue[0]
	var headers: PackedStringArray = ["Content-Type: application/json"]
	
	# Agregar token si existe
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)
		
	# Agregar slot actual si existe
	if current_slot_id > 0:
		headers.append("X-Slot-Id: %d" % current_slot_id)
	
	var err: int
	if req["body"].is_empty():
		err = _http.request(req["url"], headers, req["method"])
	else:
		err = _http.request(req["url"], headers, req["method"], req["body"])
	
	if err != OK:
		push_error("[AuthManager] Error al iniciar petición: %s" % error_string(err))
		_request_queue.remove_at(0)
		_is_requesting = false
		_process_queue()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _request_queue.is_empty():
		_is_requesting = false
		return
	
	var req: Dictionary = _request_queue[0]
	_request_queue.remove_at(0)
	_is_requesting = false
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_error(req, "Error de red")
		_process_queue()
		return
	
	# Capturar sesión invalidada en tiempo real (409)
	if response_code == 409:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
			var error_detail = str(json.data.get("detail", ""))
			if error_detail == "SESSION_INVALIDATED":
				_handle_session_invalidated()
				_request_queue.clear()
				_is_requesting = false
				return
	
	if response_code < 200 or response_code >= 300:
		var error_detail := "HTTP %d" % response_code
		# Intentar extraer detalle del error
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
			error_detail = str(json.data.get("detail", error_detail))
		_handle_error(req, error_detail)
		_process_queue()
		return
	
	# Parsear respuesta
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_handle_error(req, "Error parseando respuesta JSON")
		_process_queue()
		return
	
	_dispatch_response(req, json.data)
	_process_queue()


func _dispatch_response(req: Dictionary, data) -> void:
	match req["endpoint"]:
		"login":
			if data is Dictionary and data.has("access_token"):
				auth_token = str(data["access_token"])
				current_user = data.get("user", {})
				if data.has("must_change_password"):
					current_user["must_change_password"] = data["must_change_password"]
				is_authenticated = true
				ApiConfig.AUTH_TOKEN = auth_token
				_save_session_to_disk()
				_start_polling()
				login_success.emit(current_user)
				print("[AuthManager] Login exitoso: %s" % current_user.get("email", ""))
			else:
				login_failed.emit("Respuesta inesperada del servidor")
		
		"register":
			if data is Dictionary and data.has("id"):
				register_success.emit(data)
				print("[AuthManager] Registro exitoso: %s" % data.get("email", ""))
			else:
				register_failed.emit("Respuesta inesperada")
		
		"load_progress":
			if data is Dictionary:
				current_slot_id = int(data.get("active_slot_id", 0))
				_save_session_to_disk()
				progress_loaded.emit(data)
				print("[AuthManager] Progreso cargado, slot activo: %d" % current_slot_id)
			else:
				progress_load_failed.emit("Datos de progreso inválidos")
		
		"save_session":
			print("[AuthManager] Sesión guardada en la API")
		
		"save_achievement":
			print("[AuthManager] Logro guardado en la API")
		
		"save_note":
			print("[AuthManager] Nota guardada en la API")

		"update_character":
			print("[AuthManager] Personaje actualizado en la API")

		"change_password":
			current_user["must_change_password"] = false
			_save_session_to_disk()
			password_changed.emit()
			print("[AuthManager] Contraseña cambiada exitosamente")
		
		"validate_session":
			# Validación exitosa periódica
			pass


func _handle_error(req: Dictionary, error: String) -> void:
	match req["endpoint"]:
		"login":
			login_failed.emit(error)
			print("[AuthManager] Login fallido: %s" % error)
		"register":
			register_failed.emit(error)
			print("[AuthManager] Registro fallido: %s" % error)
		"load_progress":
			progress_load_failed.emit(error)
			print("[AuthManager] Error cargando progreso: %s" % error)
		"change_password":
			password_change_failed.emit(error)
			print("[AuthManager] Error al cambiar contraseña: %s" % error)
		_:
			push_warning("[AuthManager] Error en %s: %s" % [req["endpoint"], error])


# ─── Persistencia local de sesión ───────────────────────────────────────────

func _save_session_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", auth_token)
	cfg.set_value("auth", "user_id", current_user.get("id", 0))
	cfg.set_value("auth", "email", current_user.get("email", ""))
	cfg.set_value("auth", "display_name", current_user.get("display_name", ""))
	cfg.set_value("auth", "character", current_user.get("character", "male"))
	cfg.set_value("auth", "must_change_password", current_user.get("must_change_password", false))
	cfg.set_value("auth", "current_slot_id", current_slot_id)
	cfg.save(_SESSION_FILE)


func _load_saved_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SESSION_FILE) != OK:
		return
	
	var saved_token: String = cfg.get_value("auth", "token", "")
	if saved_token.is_empty():
		return
	
	auth_token = saved_token
	current_slot_id = cfg.get_value("auth", "current_slot_id", 0)
	current_user = {
		"id": cfg.get_value("auth", "user_id", 0),
		"email": cfg.get_value("auth", "email", ""),
		"display_name": cfg.get_value("auth", "display_name", ""),
		"character": cfg.get_value("auth", "character", "male"),
		"must_change_password": cfg.get_value("auth", "must_change_password", false),
	}
	is_authenticated = true
	ApiConfig.AUTH_TOKEN = auth_token
	print("[AuthManager] Sesión restaurada: %s, slot: %d" % [current_user.get("email", ""), current_slot_id])


func _clear_saved_session() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists("session.cfg"):
		dir.remove("session.cfg")


# ─── Sincronización pendiente (offline) ─────────────────────────────────────

const _PENDING_FILE: String = "user://pending_sync.json"

func _save_pending_sync(data: Dictionary) -> void:
	var file := FileAccess.open(_PENDING_FILE, FileAccess.WRITE)
	if file:
		var pending: Array = _load_pending_sync()
		pending.append(data)
		file.store_string(JSON.stringify(pending))
		file.close()
		print("[AuthManager] Sesión guardada para sincronización pendiente")


func _load_pending_sync() -> Array:
	if not FileAccess.file_exists(_PENDING_FILE):
		return []
	var file := FileAccess.open(_PENDING_FILE, FileAccess.READ)
	if not file:
		return []
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) == OK and json.data is Array:
		return json.data
	return []


# ─── Heartbeat de Polling y Cierre Forzado ───────────────────────────────────

func _on_polling_timeout() -> void:
	if not is_authenticated or current_slot_id == 0:
		return
	
	_enqueue_request(
		"%s/progress/validate-session" % ApiConfig.BASE_URL,
		"validate_session",
		{},
		HTTPClient.METHOD_GET
	)


func _start_polling() -> void:
	if _polling_timer:
		_polling_timer.start()
		print("[AuthManager] Polling de validación iniciado (60s)")


func _stop_polling() -> void:
	if _polling_timer:
		_polling_timer.stop()
		print("[AuthManager] Polling de validación detenido")


func _handle_session_invalidated() -> void:
	session_invalidated.emit()
	print("[AuthManager] ¡Sesión invalidada por el administrador!")
	_stop_polling()
	
	# Si ya existe el overlay, no crear otro
	if _overlay_instance and is_instance_valid(_overlay_instance):
		return
		
	var overlay_scene = load("res://scenes/UI/session_invalidated_overlay.tscn")
	if overlay_scene:
		_overlay_instance = overlay_scene.instantiate()
		get_tree().root.add_child(_overlay_instance)
