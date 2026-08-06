## Pantalla de inicio de sesión mejorada.
## Permite al jugador ingresar con correo y contraseña.
## Al autenticarse, carga el progreso desde la API y transiciona:
##   - Si ya jugó antes → directo al Lobby (con personaje guardado).
##   - Si es primera vez → selección de personaje.
##
## Mejoras:
##   - Mensaje de bienvenida auto-generado según historial.
##   - Flujo "Bienvenido de vuelta" para jugadores recurrentes con sesión guardada.
##   - Animaciones de entrada (fade in).
extends CanvasLayer

# ─── Nodos de UI ─────────────────────────────────────────────────────────────

@onready var email_input: LineEdit = %EmailInput
@onready var password_input: LineEdit = %PasswordInput
@onready var login_button: Button = %LoginButton
@onready var error_label: Label = %ErrorLabel
@onready var loading_indicator: Label = %LoadingIndicator
@onready var welcome_label: Label = %WelcomeLabel
@onready var subtitle_label: Label = %Subtitle
@onready var login_panel: PanelContainer = %LoginPanel
@onready var return_panel: PanelContainer = %ReturnPanel
@onready var return_name_label: Label = %ReturnNameLabel
@onready var return_continue_button: Button = %ReturnContinueButton
@onready var return_switch_button: Button = %ReturnSwitchButton

# ─── Constantes ──────────────────────────────────────────────────────────────

const CHARACTER_SELECT_SCENE: String = "res://scenes/UI/character_select.tscn"
const LOBBY_SCENE: String = "res://scenes/Scenery/Lobby/lobby.tscn"
const CHANGE_PASSWORD_SCENE: String = "res://scenes/UI/change_password_screen.tscn"
const FONT_PATH := "res://fonts/PixelifySans-SemiBold.ttf"

## Mensajes de bienvenida basados en el número de sesiones del jugador.
const WELCOME_MESSAGES: Array[String] = [
	"¡Tu aventura comienza aquí!",
	"¡Bienvenido al Mundo Virtual de Lectura!",
	"¿Listo para una nueva aventura?",
	"¡Explora, lee y aprende!",
	"¡Tu mundo de lectura te espera!",
]

const RETURN_MESSAGES: Array[String] = [
	"¡Qué bueno verte de vuelta, %s!",
	"¡Hola de nuevo, %s!",
	"¡%s ha vuelto al mundo de lectura!",
	"¡Bienvenido otra vez, %s!",
	"¡%s, tu aventura continúa!",
]

# ─── Estado ──────────────────────────────────────────────────────────────────

var _is_returning_player: bool = false

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	error_label.text = ""
	loading_indicator.visible = false
	return_panel.visible = false
	login_panel.visible = true
	
	login_button.pressed.connect(_on_login_pressed)
	password_input.text_submitted.connect(func(_t): _on_login_pressed())
	return_continue_button.pressed.connect(_on_continue_pressed)
	return_switch_button.pressed.connect(_on_switch_account_pressed)
	
	# Conectar señales del AuthManager
	AuthManager.login_success.connect(_on_login_success)
	AuthManager.login_failed.connect(_on_login_failed)
	AuthManager.progress_loaded.connect(_on_progress_loaded)
	AuthManager.progress_load_failed.connect(_on_progress_load_failed)
	
	# Estilizar UI
	_apply_styles()
	
	# Si ya hay sesión guardada → flujo "Bienvenido de vuelta"
	if AuthManager.is_authenticated:
		if AuthManager.current_user.get("must_change_password", false):
			get_tree().change_scene_to_file(CHANGE_PASSWORD_SCENE)
			return
		_show_return_flow()
	else:
		_show_new_player_flow()
	
	# Animación de entrada
	_animate_entry()


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


# ─── Flujos de UI ────────────────────────────────────────────────────────────

func _show_return_flow() -> void:
	"""Muestra el flujo para jugadores que ya tienen sesión guardada."""
	_is_returning_player = true
	login_panel.visible = false
	return_panel.visible = true
	
	var display_name: String = AuthManager.get_display_name()
	var msg_idx: int = randi() % RETURN_MESSAGES.size()
	return_name_label.text = RETURN_MESSAGES[msg_idx] % display_name
	welcome_label.text = "¡Bienvenido de vuelta!"
	subtitle_label.text = "Tu progreso está guardado"


func _show_new_player_flow() -> void:
	"""Muestra el flujo estándar de login para nuevos jugadores o sin sesión."""
	_is_returning_player = false
	login_panel.visible = true
	return_panel.visible = false
	
	var msg_idx: int = randi() % WELCOME_MESSAGES.size()
	welcome_label.text = WELCOME_MESSAGES[msg_idx]
	subtitle_label.text = "Inicia sesión para continuar"


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


func _on_continue_pressed() -> void:
	"""El jugador quiere continuar con su sesión guardada."""
	_show_loading("Restaurando sesión...")
	AuthManager.load_progress()


func _on_switch_account_pressed() -> void:
	"""El jugador quiere usar otra cuenta."""
	AuthManager.logout()
	_show_new_player_flow()


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


# ─── Estilos y Animaciones ───────────────────────────────────────────────────

func _apply_styles() -> void:
	"""Aplica estilos mejorados a los nodos de UI programáticamente."""
	var font = load(FONT_PATH)
	if not font:
		return
	
	# Estilizar campos de entrada
	for input in [email_input, password_input]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.13, 0.18, 0.9)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.25, 0.27, 0.35, 0.6)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		input.add_theme_stylebox_override("normal", style)
		
		var focus_style := style.duplicate()
		focus_style.border_color = Color(0.39, 0.4, 0.95, 0.8)
		input.add_theme_stylebox_override("focus", focus_style)
		
		input.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
		input.add_theme_color_override("font_placeholder_color", Color(0.4, 0.42, 0.5))
		input.add_theme_font_override("font", font)
		input.add_theme_font_size_override("font_size", 16)
	
	# Estilizar botón de login
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.39, 0.4, 0.95, 1.0)
	btn_normal.corner_radius_top_left = 10
	btn_normal.corner_radius_top_right = 10
	btn_normal.corner_radius_bottom_left = 10
	btn_normal.corner_radius_bottom_right = 10
	login_button.add_theme_stylebox_override("normal", btn_normal)
	
	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = Color(0.45, 0.46, 1.0, 1.0)
	login_button.add_theme_stylebox_override("hover", btn_hover)
	
	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.30, 0.31, 0.80, 1.0)
	login_button.add_theme_stylebox_override("pressed", btn_pressed)
	
	login_button.add_theme_color_override("font_color", Color.WHITE)
	login_button.add_theme_color_override("font_hover_color", Color.WHITE)
	login_button.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 1.0))
	login_button.add_theme_font_override("font", font)
	login_button.add_theme_font_size_override("font_size", 18)
	
	# Estilizar botones del panel de retorno
	if return_continue_button:
		return_continue_button.add_theme_stylebox_override("normal", btn_normal.duplicate())
		return_continue_button.add_theme_stylebox_override("hover", btn_hover.duplicate())
		return_continue_button.add_theme_stylebox_override("pressed", btn_pressed.duplicate())
		return_continue_button.add_theme_color_override("font_color", Color.WHITE)
		return_continue_button.add_theme_font_override("font", font)
		return_continue_button.add_theme_font_size_override("font_size", 18)
	
	if return_switch_button:
		var ghost_style := StyleBoxFlat.new()
		ghost_style.bg_color = Color(0.15, 0.16, 0.22, 0.5)
		ghost_style.corner_radius_top_left = 8
		ghost_style.corner_radius_top_right = 8
		ghost_style.corner_radius_bottom_left = 8
		ghost_style.corner_radius_bottom_right = 8
		ghost_style.border_width_left = 1
		ghost_style.border_width_top = 1
		ghost_style.border_width_right = 1
		ghost_style.border_width_bottom = 1
		ghost_style.border_color = Color(0.3, 0.32, 0.4, 0.5)
		return_switch_button.add_theme_stylebox_override("normal", ghost_style)
		var ghost_hover := ghost_style.duplicate()
		ghost_hover.bg_color = Color(0.2, 0.21, 0.28, 0.7)
		return_switch_button.add_theme_stylebox_override("hover", ghost_hover)
		return_switch_button.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
		return_switch_button.add_theme_color_override("font_hover_color", Color(0.8, 0.82, 0.9))
		return_switch_button.add_theme_font_override("font", font)
		return_switch_button.add_theme_font_size_override("font_size", 14)


func _animate_entry() -> void:
	"""Anima la entrada del panel central con un fade-in suave."""
	var panel: Control = login_panel if login_panel.visible else return_panel
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


# ─── Utilidades de UI ────────────────────────────────────────────────────────

func _show_error(msg: String) -> void:
	error_label.text = msg
	error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


func _show_loading(msg: String) -> void:
	loading_indicator.text = msg
	loading_indicator.visible = true
	login_button.disabled = true
	if return_continue_button:
		return_continue_button.disabled = true
	error_label.text = ""


func _hide_loading() -> void:
	loading_indicator.visible = false
	login_button.disabled = false
	if return_continue_button:
		return_continue_button.disabled = false
