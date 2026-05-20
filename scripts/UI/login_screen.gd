## Pantalla de inicio de sesión.
## Permite al jugador ingresar con correo y contraseña.
## Al autenticarse, carga el progreso desde la API y transiciona
## a la selección de personaje.
extends CanvasLayer

# ─── Nodos de UI ─────────────────────────────────────────────────────────────

@onready var email_input: LineEdit = %EmailInput
@onready var password_input: LineEdit = %PasswordInput
@onready var login_button: Button = %LoginButton
@onready var error_label: Label = %ErrorLabel
@onready var loading_indicator: Label = %LoadingIndicator

# ─── Constantes ──────────────────────────────────────────────────────────────

const CHARACTER_SELECT_SCENE: String = "res://scenes/UI/character_select.tscn"

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
	
	# Si ya hay sesión guardada, intentar cargar progreso directamente
	if AuthManager.is_authenticated:
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
	
	print("[LoginScreen] Progreso cargado, transitando a selección de personaje")
	_hide_loading()
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_progress_load_failed(error: String) -> void:
	# Si falla la carga de progreso, igual permitir continuar
	push_warning("[LoginScreen] No se pudo cargar progreso: %s" % error)
	_hide_loading()
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


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
