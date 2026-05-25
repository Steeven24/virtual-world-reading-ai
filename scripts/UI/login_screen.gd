## Pantalla de inicio de sesión.
## Permite al jugador ingresar con correo y contraseña.
## Al autenticarse, carga el progreso desde la API y transiciona:
##   - Si ya jugó antes → directo al Lobby (con personaje guardado).
##   - Si es primera vez → selección de personaje.
extends CanvasLayer

# ─── Nodos de UI ─────────────────────────────────────────────────────────────

@onready var email_input: LineEdit = %EmailInput
@onready var password_input: LineEdit = %PasswordInput
@onready var login_button: Button = %LoginButton
@onready var error_label: Label = %ErrorLabel
@onready var loading_indicator: Label = %LoadingIndicator

# ─── Constantes ──────────────────────────────────────────────────────────────

const CHARACTER_SELECT_SCENE: String = "res://scenes/UI/character_select.tscn"
const LOBBY_SCENE: String = "res://scenes/Scenery/Lobby/lobby.tscn"
const CHANGE_PASSWORD_SCENE: String = "res://scenes/UI/change_password_screen.tscn"

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	error_label.text = ""
	loading_indicator.visible = false
	
	login_button.pressed.connect(_on_login_pressed)
	password_input.text_submitted.connect(func(_t): _on_login_pressed())
	
	# Conectar señales del AuthManager
	AuthManager.login_success.connect(_on_login_success)
	AuthManager.login_failed.connect(_on_login_failed)
	AuthManager.progress_loaded.connect(_on_progress_loaded)
	AuthManager.progress_load_failed.connect(_on_progress_load_failed)
	
	# Si ya hay sesión guardada, verificar si debe cambiar contraseña
	if AuthManager.is_authenticated:
		if AuthManager.current_user.get("must_change_password", false):
			get_tree().change_scene_to_file(CHANGE_PASSWORD_SCENE)
			return
		_show_loading("Restaurando sesión...")
		AuthManager.load_progress()


func _exit_tree() -> void:
	# Desconectar señales para evitar errores
	if AuthManager.login_success.is_connected(_on_login_success):
		AuthManager.login_success.disconnect(_on_login_success)
	if AuthManager.login_failed.is_connected(_on_login_failed):
		AuthManager.login_failed.disconnect(_on_login_failed)
	if AuthManager.progress_loaded.is_connected(_on_progress_loaded):
		AuthManager.progress_loaded.disconnect(_on_progress_loaded)
	if AuthManager.progress_load_failed.is_connected(_on_progress_load_failed):
		AuthManager.progress_load_failed.disconnect(_on_progress_load_failed)


# ─── Handlers ────────────────────────────────────────────────────────────────

func _on_login_pressed() -> void:
	var email := email_input.text.strip_edges()
	var password := password_input.text.strip_edges()
	
	# Validación básica
	if email.is_empty() or password.is_empty():
		_show_error("Ingresa tu correo y contraseña")
		return
	
	if not "@" in email:
		_show_error("Ingresa un correo válido")
		return
	
	_show_loading("Iniciando sesión...")
	AuthManager.login(email, password)


func _on_login_success(user_data: Dictionary) -> void:
	print("[LoginScreen] Login exitoso: %s" % user_data.get("email", ""))
	if user_data.get("must_change_password", false):
		print("[LoginScreen] Cambio de contraseña obligatorio detectado. Redirigiendo...")
		_hide_loading()
		get_tree().change_scene_to_file(CHANGE_PASSWORD_SCENE)
		return
	_show_loading("Cargando progreso...")
	AuthManager.load_progress()


func _on_login_failed(error: String) -> void:
	_hide_loading()
	_show_error(error)


func _on_progress_loaded(progress_data: Dictionary) -> void:
	# Restaurar progreso en los managers locales
	var typology_progress: Array = progress_data.get("typology_progress", [])
	ProgressionManager.load_from_api(typology_progress)
	GameSession.load_from_api(progress_data)
	
	_hide_loading()
	
	# Determinar si el usuario ya ha jugado antes.
	# Si tiene sesiones completadas, ir directo al Lobby (ya tiene personaje).
	var has_played := _has_previous_sessions(progress_data)
	
	if has_played:
		print("[LoginScreen] Jugador con progreso previo, yendo al Lobby")
		SceneManager.transition_to(LOBBY_SCENE)
	else:
		print("[LoginScreen] Jugador nuevo, mostrando selección de personaje")
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_progress_load_failed(error: String) -> void:
	# Si falla la carga de progreso, verificar si ya tenemos datos locales
	push_warning("[LoginScreen] No se pudo cargar progreso: %s" % error)
	_hide_loading()
	
	# Si ya hay datos del personaje guardados localmente y ha jugado, ir al Lobby
	var character: String = AuthManager.get_character()
	if character != "male" or GameSession.score_data.get("sessions_completed", 0) > 0:
		GameSession.set_character(character)
		SceneManager.transition_to(LOBBY_SCENE)
	else:
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


## Determina si el usuario tiene sesiones previas basándose en los datos del progreso.
func _has_previous_sessions(progress_data: Dictionary) -> bool:
	# Verificar si tiene sesiones o si tiene una puntuación total > 0
	var total_score: int = progress_data.get("total_score", 0)
	if total_score > 0:
		return true
	
	# Verificar tipologías con sesiones
	var typologies: Array = progress_data.get("typology_progress", [])
	for tp in typologies:
		if tp.get("total_sessions", 0) > 0:
			return true
	
	# Verificar si tiene logros
	var achievements: Array = progress_data.get("achievements", [])
	if not achievements.is_empty():
		return true
	
	return false


# ─── Utilidades de UI ────────────────────────────────────────────────────────

func _show_error(msg: String) -> void:
	error_label.text = msg
	error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


func _show_loading(msg: String) -> void:
	loading_indicator.text = msg
	loading_indicator.visible = true
	login_button.disabled = true
	error_label.text = ""


func _hide_loading() -> void:
	loading_indicator.visible = false
	login_button.disabled = false
