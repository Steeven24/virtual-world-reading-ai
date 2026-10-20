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
@onready var toggle_password_button: Button = %TogglePasswordButton
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
const FONT_PATH := "res://fonts/fuente_juego.tres"

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

## Panel «Crear cuenta» y su enlace, creados por código bajo el login.
var _registro: PanelRegistro = null
var _crear_cuenta_button: Button = null

## Credenciales recién registradas, para entrar con ellas en cuanto la API
## confirme la cuenta.
var _correo_registro: String = ""
var _clave_registro: String = ""

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	error_label.text = ""
	loading_indicator.visible = false
	return_panel.visible = false
	login_panel.visible = true
	
	login_button.pressed.connect(_on_login_pressed)
	password_input.text_submitted.connect(func(_t): _on_login_pressed())
	toggle_password_button.toggled.connect(_on_toggle_password)
	return_continue_button.pressed.connect(_on_continue_pressed)
	return_switch_button.pressed.connect(_on_switch_account_pressed)
	
	# Conectar señales del AuthManager
	AuthManager.login_success.connect(_on_login_success)
	AuthManager.login_failed.connect(_on_login_failed)
	AuthManager.progress_loaded.connect(_on_progress_loaded)
	AuthManager.progress_load_failed.connect(_on_progress_load_failed)
	AuthManager.register_success.connect(_on_register_success)
	AuthManager.register_failed.connect(_on_register_failed)
	
	_construir_registro()

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
	if AuthManager.register_success.is_connected(_on_register_success):
		AuthManager.register_success.disconnect(_on_register_success)
	if AuthManager.register_failed.is_connected(_on_register_failed):
		AuthManager.register_failed.disconnect(_on_register_failed)


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
	if _registro:
		_registro.visible = false
	
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


## Muestra u oculta la contraseña escrita, para que el jugador pueda
## comprobar lo que ha tecleado antes de enviar.
func _on_toggle_password(mostrar: bool) -> void:
	password_input.secret = not mostrar
	toggle_password_button.text = "🙈" if mostrar else "👁"
	toggle_password_button.tooltip_text = "Ocultar contraseña" if mostrar else "Mostrar contraseña"


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
	if _registro and _registro.visible:
		_registro.set_cargando(false)
		_registro.mostrar_error(error)
		return
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
	if SceneManager:
		SceneManager.ensure_fallbacks(font)

	# Aplicar fuente a todos los Labels del LoginScreen
	for child in find_children("*", "Label", true, false):
		if child is Label:
			child.add_theme_font_override("font", font)

	# El encabezado del recuadro del proyecto, en negrita.
	var negrita = load("res://fonts/fuente_juego_negrita.tres")
	if negrita:
		$ProyectoPanel/ProyectoVBox/ProyectoTitulo.add_theme_font_override("font", negrita)

	for input in [email_input, password_input]:
		_estilo_campo(input)
	_estilo_boton_ojo(toggle_password_button)
	_estilo_boton_principal(login_button)
	if return_continue_button:
		_estilo_boton_principal(return_continue_button)
	if return_switch_button:
		_estilo_boton_secundario(return_switch_button)
	_estilo_boton_secundario(_crear_cuenta_button)

	# El registro usa las mismas piezas que el login.
	for campo in _registro.campos():
		_estilo_campo(campo)
	_estilo_boton_ojo(_registro.ojo_button)
	_estilo_boton_principal(_registro.crear_button)
	_estilo_boton_secundario(_registro.volver_button)
	_registro.add_theme_stylebox_override("panel", login_panel.get_theme_stylebox("panel"))


## Campo de texto: fondo oscuro, borde que se ilumina con el foco.
func _estilo_campo(input: LineEdit) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.18, 0.9)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
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
	var font = load(FONT_PATH)
	if font:
		input.add_theme_font_override("font", font)
	input.add_theme_font_size_override("font_size", 16)


## Botón del ojo: igual que los campos, para que se lea como parte del mismo
## control y no como un botón suelto.
func _estilo_boton_ojo(boton: Button) -> void:
	var eye_normal := StyleBoxFlat.new()
	eye_normal.bg_color = Color(0.12, 0.13, 0.18, 0.9)
	eye_normal.set_corner_radius_all(8)
	eye_normal.set_border_width_all(2)
	eye_normal.border_color = Color(0.25, 0.27, 0.35, 0.6)
	var eye_hover := eye_normal.duplicate()
	eye_hover.border_color = Color(0.39, 0.4, 0.95, 0.8)
	boton.add_theme_stylebox_override("normal", eye_normal)
	boton.add_theme_stylebox_override("hover", eye_hover)
	boton.add_theme_stylebox_override("pressed", eye_hover)
	boton.add_theme_color_override("font_color", Color(0.75, 0.77, 0.85))
	boton.add_theme_color_override("font_hover_color", Color.WHITE)
	boton.add_theme_color_override("font_pressed_color", Color.WHITE)
	var font = load(FONT_PATH)
	if font:
		boton.add_theme_font_override("font", font)
	boton.add_theme_font_size_override("font_size", 18)


## Botón principal (entrar, continuar, crear cuenta).
func _estilo_boton_principal(boton: Button) -> void:
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.39, 0.4, 0.95, 1.0)
	btn_normal.set_corner_radius_all(10)
	boton.add_theme_stylebox_override("normal", btn_normal)

	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = Color(0.45, 0.46, 1.0, 1.0)
	boton.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.30, 0.31, 0.80, 1.0)
	boton.add_theme_stylebox_override("pressed", btn_pressed)

	boton.add_theme_color_override("font_color", Color.WHITE)
	boton.add_theme_color_override("font_hover_color", Color.WHITE)
	boton.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 1.0))
	var font = load(FONT_PATH)
	if font:
		boton.add_theme_font_override("font", font)
	boton.add_theme_font_size_override("font_size", 18)


## Botón secundario y discreto (cambiar de cuenta, crear cuenta, volver).
func _estilo_boton_secundario(boton: Button) -> void:
	var ghost_style := StyleBoxFlat.new()
	ghost_style.bg_color = Color(0.15, 0.16, 0.22, 0.5)
	ghost_style.set_corner_radius_all(8)
	ghost_style.set_border_width_all(1)
	ghost_style.border_color = Color(0.3, 0.32, 0.4, 0.5)
	boton.add_theme_stylebox_override("normal", ghost_style)
	var ghost_hover := ghost_style.duplicate()
	ghost_hover.bg_color = Color(0.2, 0.21, 0.28, 0.7)
	boton.add_theme_stylebox_override("hover", ghost_hover)
	boton.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	boton.add_theme_color_override("font_hover_color", Color(0.8, 0.82, 0.9))
	var font = load(FONT_PATH)
	if font:
		boton.add_theme_font_override("font", font)
	boton.add_theme_font_size_override("font_size", 14)


func _animate_entry() -> void:
	"""Anima la entrada del panel central con un fade-in suave."""
	var panel: Control = login_panel if login_panel.visible else return_panel
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


# ─── Crear cuenta ────────────────────────────────────────────────────────────

## Enlace «Crear cuenta» bajo el botón de entrar y el panel de registro, al
## lado del de login. Se crean aquí y no en la escena para que el panel viva
## en un solo script (panel_registro.gd).
func _construir_registro() -> void:
	_crear_cuenta_button = Button.new()
	_crear_cuenta_button.name = "CrearCuentaButton"
	_crear_cuenta_button.text = "¿No tienes cuenta? Crear cuenta"
	_crear_cuenta_button.pressed.connect(_on_crear_cuenta_pressed)
	var caja := login_button.get_parent()
	caja.add_child(_crear_cuenta_button)
	caja.move_child(_crear_cuenta_button, login_button.get_index() + 1)

	_registro = PanelRegistro.new()
	login_panel.get_parent().add_child(_registro)
	login_panel.get_parent().move_child(_registro, login_panel.get_index() + 1)
	_registro.registro_pedido.connect(_on_registro_pedido)
	_registro.volver_pedido.connect(_on_volver_al_login)


func _on_crear_cuenta_pressed() -> void:
	error_label.text = ""
	_registro.vaciar()
	login_panel.visible = false
	_registro.visible = true
	welcome_label.text = "¡Únete al mundo de lectura!"
	subtitle_label.text = "Crea tu cuenta para empezar"
	_registro.nombre_input.grab_focus()


func _on_volver_al_login() -> void:
	_registro.visible = false
	login_panel.visible = true
	_show_new_player_flow()


func _on_registro_pedido(nombre: String, correo: String, clave: String) -> void:
	_correo_registro = correo
	_clave_registro = clave
	_registro.set_cargando(true)
	AuthManager.register(correo, clave, nombre)


## La cuenta existe: se entra con ella y sigue el flujo de un jugador nuevo
## (elegir personaje y lobby con tutorial).
func _on_register_success(_datos: Dictionary) -> void:
	AuthManager.login(_correo_registro, _clave_registro)
	_clave_registro = ""


func _on_register_failed(error: String) -> void:
	_registro.set_cargando(false)
	_registro.mostrar_error(mensaje_error_registro(error))


## Texto para el alumno a partir del error que devuelve AuthManager (el
## "detail" de la API o un error de red).
static func mensaje_error_registro(detalle: String) -> String:
	if detalle.contains("Ya existe"):
		return "Ya existe una cuenta con ese correo."
	if detalle.begins_with("["):
		# 422: la API devuelve la lista de errores de validación del correo.
		return "Revisa el correo: no parece válido."
	if detalle == "Error de red" or detalle.begins_with("HTTP "):
		return "No se pudo conectar con el servidor. Inténtalo de nuevo."
	return detalle


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
