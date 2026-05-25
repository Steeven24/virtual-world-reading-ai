## Pantalla de cambio de contraseña obligatorio.
## Se muestra cuando el administrador ha restablecido la contraseña del usuario.
extends CanvasLayer

# ─── Nodos de UI ─────────────────────────────────────────────────────────────

@onready var new_password_input: LineEdit = %NewPasswordInput
@onready var confirm_password_input: LineEdit = %ConfirmPasswordInput
@onready var submit_button: Button = %SubmitButton
@onready var error_label: Label = %ErrorLabel
@onready var loading_indicator: Label = %LoadingIndicator

# ─── Constantes ──────────────────────────────────────────────────────────────

const CHARACTER_SELECT_SCENE: String = "res://scenes/UI/character_select.tscn"
const LOBBY_SCENE: String = "res://scenes/Scenery/Lobby/lobby.tscn"

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	error_label.text = ""
	loading_indicator.visible = false
	
	submit_button.pressed.connect(_on_submit_pressed)
	new_password_input.text_submitted.connect(func(_t): confirm_password_input.grab_focus())
	confirm_password_input.text_submitted.connect(func(_t): _on_submit_pressed())
	
	# Conectar señales del AuthManager
	AuthManager.password_changed.connect(_on_password_changed)
	AuthManager.password_change_failed.connect(_on_password_change_failed)
	AuthManager.progress_loaded.connect(_on_progress_loaded)
	AuthManager.progress_load_failed.connect(_on_progress_load_failed)


func _exit_tree() -> void:
	# Desconectar señales para evitar fallos de memoria
	if AuthManager.password_changed.is_connected(_on_password_changed):
		AuthManager.password_changed.disconnect(_on_password_changed)
	if AuthManager.password_change_failed.is_connected(_on_password_change_failed):
		AuthManager.password_change_failed.disconnect(_on_password_change_failed)
	if AuthManager.progress_loaded.is_connected(_on_progress_loaded):
		AuthManager.progress_loaded.disconnect(_on_progress_loaded)
	if AuthManager.progress_load_failed.is_connected(_on_progress_load_failed):
		AuthManager.progress_load_failed.disconnect(_on_progress_load_failed)


# ─── Handlers ────────────────────────────────────────────────────────────────

func _on_submit_pressed() -> void:
	var new_pwd := new_password_input.text.strip_edges()
	var confirm_pwd := confirm_password_input.text.strip_edges()
	
	# Validación básica
	if new_pwd.is_empty() or confirm_pwd.is_empty():
		_show_error("Completa ambos campos de contraseña")
		return
		
	if new_pwd != confirm_pwd:
		_show_error("Las contraseñas no coinciden")
		return
		
	if new_pwd.length() < 8:
		_show_error("La contraseña debe tener al menos 8 caracteres")
		return
		
	# Validar que contenga mayúscula y número
	var has_upper := false
	var has_digit := false
	
	for i in range(new_pwd.length()):
		var char_code := new_pwd.unicode_at(i)
		# Rango ASCII 65-90 es A-Z
		if char_code >= 65 and char_code <= 90:
			has_upper = true
		# Rango ASCII 48-57 es 0-9
		elif char_code >= 48 and char_code <= 57:
			has_digit = true
			
	if not has_upper:
		_show_error("Debe contener al menos una letra mayúscula")
		return
		
	if not has_digit:
		_show_error("Debe contener al menos un número")
		return
		
	_show_loading("Guardando nueva contraseña...")
	AuthManager.change_password(new_pwd)


func _on_password_changed() -> void:
	_show_loading("¡Contraseña guardada! Cargando progreso...")
	AuthManager.load_progress()


func _on_password_change_failed(error: String) -> void:
	_hide_loading()
	_show_error(error)


func _on_progress_loaded(progress_data: Dictionary) -> void:
	var typology_progress: Array = progress_data.get("typology_progress", [])
	ProgressionManager.load_from_api(typology_progress)
	GameSession.load_from_api(progress_data)
	
	_hide_loading()
	
	# Determinar si redirigir al Lobby o a Selección de Personaje
	var has_played := false
	var total_score: int = progress_data.get("total_score", 0)
	if total_score > 0:
		has_played = true
	else:
		for tp in typology_progress:
			if tp.get("total_sessions", 0) > 0:
				has_played = true
				break
				
	if has_played:
		print("[ChangePassword] Jugador antiguo, yendo al Lobby")
		SceneManager.transition_to(LOBBY_SCENE)
	else:
		print("[ChangePassword] Jugador nuevo, yendo a selección de personaje")
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_progress_load_failed(_error: String) -> void:
	_hide_loading()
	# En caso de fallo de red, asumimos selección de personaje
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


# ─── Utilidades de UI ────────────────────────────────────────────────────────

func _show_error(msg: String) -> void:
	error_label.text = msg
	error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


func _show_loading(msg: String) -> void:
	loading_indicator.text = msg
	loading_indicator.visible = true
	submit_button.disabled = true
	error_label.text = ""


func _hide_loading() -> void:
	loading_indicator.visible = false
	submit_button.disabled = false
