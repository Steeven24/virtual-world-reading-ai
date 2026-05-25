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
	
	# Pausar el juego si se desea para que el jugador no pueda mover su personaje
	get_tree().paused = false # No pausar el SceneTree, pero el popup es bloqueante


func _on_logout_button_pressed() -> void:
	# Cerrar sesión en AuthManager
	AuthManager.logout()
	
	# Redirigir a login
	get_tree().change_scene_to_file(LOGIN_SCENE)
	
	# Eliminar overlay
	queue_free()
