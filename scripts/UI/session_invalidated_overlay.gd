## session_invalidated_overlay.gd
## Controla el diálogo obligatorio que aparece al ser invalidada la sesión del jugador.
extends CanvasLayer

const LOGIN_SCENE := "res://scenes/UI/login_screen.tscn"

@onready var _close_button: Button = %LogoutButton

func _ready() -> void:
	# Asegurar que esté encima de todo
	layer = 128
	
	if _close_button:
		_close_button.pressed.connect(_on_logout_button_pressed)
	
	# Bloquear movimiento e interacciones de inmediato
	SceneManager.is_ui_open = true


func _on_logout_button_pressed() -> void:
	# Cerrar sesión en AuthManager
	AuthManager.logout()
	
	# Redirigir a login
	get_tree().change_scene_to_file(LOGIN_SCENE)
	
	# Eliminar overlay
	queue_free()
