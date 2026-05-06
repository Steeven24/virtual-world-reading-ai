## Controlador del Lobby.
## - Muestra el tutorial guiado la primera vez que el jugador entra
##   tras seleccionar personaje (persistido vía GameSession).
## - Permite re-abrir el tutorial al interactuar con el punto "Tutorial"
##   del centro del lobby.
extends Node2D

const TUTORIAL_OVERLAY_SCENE: String = "res://scenes/UI/tutorial_overlay.tscn"

## Pequeño retraso antes de abrir el tutorial automáticamente, para que
## la transición de cambio de escena termine y el HUD ya sea visible.
const AUTO_OPEN_DELAY: float = 0.4

var _tutorial_instance: CanvasLayer = null


func _ready() -> void:
	# 1) Conectar el punto "Tutorial" del lobby como trigger del overlay.
	var tutorial_node := get_node_or_null("Tutorial")
	if tutorial_node:
		# Activar el modo tutorial sobre la instancia ya colocada en la escena.
		if "is_tutorial_trigger" in tutorial_node:
			tutorial_node.is_tutorial_trigger = true
		if tutorial_node.has_signal("tutorial_triggered"):
			tutorial_node.tutorial_triggered.connect(_on_tutorial_requested)

	# 2) Si es la primera vez que entra al lobby, mostrar tutorial.
	if not GameSession.is_tutorial_completed():
		await get_tree().create_timer(AUTO_OPEN_DELAY).timeout
		_show_tutorial(true)


func _on_tutorial_requested() -> void:
	# Re-abrir manualmente desde el punto del lobby.
	_show_tutorial(false)


func _show_tutorial(mark_on_finish: bool) -> void:
	# Evitar duplicados si el overlay ya está visible.
	if _tutorial_instance and is_instance_valid(_tutorial_instance):
		return

	var packed: PackedScene = load(TUTORIAL_OVERLAY_SCENE)
	if packed == null:
		push_warning("[Lobby] No se pudo cargar el tutorial overlay.")
		return

	_tutorial_instance = packed.instantiate()
	add_child(_tutorial_instance)

	if _tutorial_instance.has_signal("finished"):
		_tutorial_instance.finished.connect(_on_tutorial_finished.bind(mark_on_finish))


func _on_tutorial_finished(mark_on_finish: bool) -> void:
	_tutorial_instance = null
	if mark_on_finish:
		GameSession.mark_tutorial_completed()
