extends CanvasLayer

@onready var confirm_dialog = %ConfirmDialog
const LOBBY_SCENE = "res://scenes/Scenery/Lobby/lobby.tscn"

## Textos del diálogo de vuelta al lobby. En la práctica no hay nada que
## guardar: salir la descarta.
const TEXTO_PROGRESION := "¿Estás seguro de que deseas regresar al Lobby? Tu progreso no se perderá."
const TEXTO_PRACTICA := "¿Volver al Lobby? Esta práctica se descartará: la práctica no se guarda a medias ni cuenta para tu progreso."

func _ready():
	confirm_dialog.hide()
	# Conectar visibility_changed para manejar cierres desde la X
	confirm_dialog.visibility_changed.connect(
		func(): if not confirm_dialog.visible: _on_dialog_closed()
	)

func request_return():
	if SceneManager.is_ui_open:
		return
		
	SceneManager.is_ui_open = true
	confirm_dialog.dialog_text = TEXTO_PRACTICA if GameSession.is_practice else TEXTO_PROGRESION

	# Usar animación de aparición similar a otros diálogos
	confirm_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	confirm_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	confirm_dialog.transparent = true
	confirm_dialog.position = Vector2i(-10000, -10000)
	confirm_dialog.min_size = Vector2i(800, 200)
	confirm_dialog.show()
	
	await get_tree().process_frame
	confirm_dialog.reset_size()
	
	var screen_size = get_viewport().get_visible_rect().size
	var final_x = (screen_size.x - confirm_dialog.size.x) / 2
	var final_y = screen_size.y - confirm_dialog.size.y - 40
	
	var offset_y = 30
	confirm_dialog.position = Vector2i(final_x, final_y + offset_y)
	
	for child in confirm_dialog.get_children():
		if child is Control:
			child.modulate.a = 0.0
			
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_method(func(y): confirm_dialog.position = Vector2i(final_x, y), final_y + offset_y, final_y, 0.3)
	
	for child in confirm_dialog.get_children():
		if child is Control:
			tween.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(0.05)

	# Foco en "Si, regresar" para poder responder con flechas y Enter/E.
	DialogFocus.preparar(confirm_dialog)


func _on_dialog_closed():
	SceneManager.is_ui_open = false

func _on_dialog_confirmed():
	_on_dialog_closed()

	if GameSession.is_practice:
		# La práctica no deja lectura pendiente: se descarta.
		GameSession.end_practice()
	elif GameSession.is_active:
		# Persistir lectura activa antes de regresar al lobby
		ReadingProgressManager.save_active_reading()
	SceneManager.transition_to(LOBBY_SCENE)
