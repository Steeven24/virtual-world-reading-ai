## Aviso que bloquea el juego cuando ya está abierto en otra ventana.
##
## Lo levanta SessionGuard al detectar que otra pestaña del mismo navegador
## tiene el turno. Congela el juego (is_ui_open) y ofrece reintentar, por si el
## jugador acaba de cerrar la otra ventana.
extends CanvasLayer

@onready var _boton_reintentar: Button = %RetryButton
@onready var _aviso: Label = %HintLabel

## Estado de is_ui_open antes de bloquear, para devolverlo tal cual al soltar.
var _ui_abierta_antes: bool = false


func _ready() -> void:
	# Por encima de todo, incluidos los diálogos y el overlay de sesión
	# invalidada: mientras esto esté, no se puede jugar.
	layer = 200

	_ui_abierta_antes = SceneManager.is_ui_open
	SceneManager.is_ui_open = true

	_boton_reintentar.pressed.connect(_on_reintentar)
	DialogFocus.marcar(_boton_reintentar)
	DialogFocus.enfocar(_boton_reintentar)


func _exit_tree() -> void:
	SceneManager.is_ui_open = _ui_abierta_antes


func _on_reintentar() -> void:
	_boton_reintentar.disabled = true
	_aviso.text = "Comprobando..."

	# El cerrojo caduca a los 6 segundos sin latido: si la otra ventana acaba de
	# cerrarse, puede hacer falta esperar a que expire.
	if SessionGuard.reintentar():
		return

	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(self):
		return
	_boton_reintentar.disabled = false
	_aviso.text = "La otra ventana sigue abierta. Ciérrala y vuelve a intentarlo."
