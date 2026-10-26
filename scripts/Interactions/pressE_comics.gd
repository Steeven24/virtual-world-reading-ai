## pressE_comics.gd
## Sillón del lobby: la puerta de la zona de cómics (recompensa). Se entra solo con
## las cuatro tipologías aprobadas; quien agotó los intentos sin aprobar no entra,
## y el aviso le dice que la zona quedó fuera de alcance (no le promete lo imposible).
##
## El catálogo se abre como capa encima del lobby, sin cambiar de escena: el jugador
## conserva su sitio junto al sillón. Mientras está abierto, SceneManager.is_ui_open
## inmoviliza al jugador y las demás interacciones del lobby lo respetan.
## A diferencia de las estaciones, no mira si hay una lectura de progresión a
## medias: los cómics no son sesión evaluada y se pueden abrir con una pendiente.
extends Node2D

const ESCENA_CATALOGO := preload("res://scenes/UI/comic_catalogo.tscn")
const ESCENA_ENCUESTA := preload("res://scenes/UI/technology_survey.tscn")

const MENSAJE_BLOQUEADO := "🔒 La zona de cómics está cerrada por ahora.\n\nAprueba las cuatro tipologías de lectura para entrar a leer los cómics de recompensa."

var player_in_range := false

## Lo que se llama al entrar para contar la visita; se puede sustituir en pruebas.
var registrar_visita: Callable = Callable()
## Sustitución síncrona para pruebas. En juego se consulta SurveyManager.
var estado_encuesta: Callable = Callable()

var _padlock: Sprite2D
var _locked_dialog: AcceptDialog
var _catalogo: Node
var _encuesta: Node
var _consultando_encuesta := false
## True mientras el aviso de bloqueo tiene tomada la interfaz (lo puso este sillón).
var _aviso_tomado := false


func _ready() -> void:
	if not registrar_visita.is_valid():
		registrar_visita = ComicLibrary.registrar_visita
	$Area2D/message.visible = false
	$"Speech bubble".visible = false
	_padlock = get_node_or_null("Padlock")
	_locked_dialog = get_node_or_null("LockedDialog")
	# Las señales se conectan por código: un [connection] del .tscn se pierde en
	# silencio si el nodo cambia de sitio.
	$Area2D.body_entered.connect(_on_body_entered)
	$Area2D.body_exited.connect(_on_body_exited)
	if _locked_dialog:
		_locked_dialog.visibility_changed.connect(_on_aviso_visibility_changed)
	ProgressionManager.progression_changed.connect(_actualizar_candado)
	_actualizar_candado()


func _exit_tree() -> void:
	# Si el lobby se descarga con el catálogo abierto, no se deja al jugador congelado.
	if is_instance_valid(_catalogo) or is_instance_valid(_encuesta) or _aviso_tomado or _consultando_encuesta:
		SceneManager.is_ui_open = false


func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		player_in_range = true
		$Area2D/message.visible = true
		$"Speech bubble".visible = true


func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		player_in_range = false
		$Area2D/message.visible = false
		$"Speech bubble".visible = false


func _process(_delta: float) -> void:
	if player_in_range and Input.is_action_just_pressed("ui_accept"):
		interactuar()


## E junto al sillón: entra si están las cuatro aprobadas; si no, avisa.
func interactuar() -> void:
	if SceneManager.is_ui_open:
		return
	if ProgressionManager.all_approved():
		_intentar_desbloquear()
	else:
		_mostrar_bloqueo()


func abrir_catalogo() -> void:
	if is_instance_valid(_catalogo):
		return
	SceneManager.is_ui_open = true
	registrar_visita.call()
	_catalogo = ESCENA_CATALOGO.instantiate()
	_catalogo.cerrado.connect(_cerrar_catalogo)
	add_child(_catalogo)


func _intentar_desbloquear() -> void:
	SceneManager.is_ui_open = true
	if estado_encuesta.is_valid():
		_al_resolver_estado(bool(estado_encuesta.call()), "")
		return
	if SurveyManager.is_completed_for_current_slot():
		_al_resolver_estado(true, "")
		return
	_consultando_encuesta = true
	SurveyManager.status_ready.connect(_al_resolver_estado, CONNECT_ONE_SHOT)
	SurveyManager.check_status()


func _al_resolver_estado(completada: bool, error: String) -> void:
	_consultando_encuesta = false
	if not error.is_empty():
		SceneManager.is_ui_open = false
		_mostrar_error_encuesta(error)
		return
	if completada:
		_actualizar_candado()
		abrir_catalogo()
	else:
		_abrir_encuesta()


func _abrir_encuesta() -> void:
	if is_instance_valid(_encuesta):
		return
	_encuesta = ESCENA_ENCUESTA.instantiate()
	_encuesta.cerrado.connect(_cerrar_encuesta)
	_encuesta.completada.connect(_encuesta_completada)
	add_child(_encuesta)


func _cerrar_encuesta() -> void:
	if is_instance_valid(_encuesta):
		_encuesta.queue_free()
	_encuesta = null
	SceneManager.is_ui_open = false


func _encuesta_completada() -> void:
	if is_instance_valid(_encuesta):
		_encuesta.queue_free()
	_encuesta = null
	_actualizar_candado()
	abrir_catalogo()


func encuesta_abierta() -> bool:
	return is_instance_valid(_encuesta)


func _cerrar_catalogo() -> void:
	if not is_instance_valid(_catalogo):
		return
	_catalogo.queue_free()
	_catalogo = null
	SceneManager.is_ui_open = false


func catalogo_abierto() -> bool:
	return is_instance_valid(_catalogo)


func candado_visible() -> bool:
	return _padlock != null and _padlock.visible


## Texto del aviso de bloqueo. Con el juego terminado la zona ya no se puede
## conseguir: se dice que quedó fuera de alcance en vez de pedir aprobarlas.
func texto_bloqueo() -> String:
	if ProgressionManager.juego_terminado():
		var agotada := ProgressionManager.tipologia_agotada()
		return "🏁 La zona de cómics quedó fuera de alcance: se acabaron tus intentos en %s y ya no podrás aprobar las cuatro tipologías.\n\nPuedes ver tus logros y el ranking en la barra de arriba." % ProgressionManager.NOMBRE_ESCENARIO.get(agotada, agotada)
	return MENSAJE_BLOQUEADO


func _actualizar_candado() -> void:
	if _padlock:
		var encuesta_lista := SurveyManager.is_completed_for_current_slot()
		if estado_encuesta.is_valid():
			encuesta_lista = bool(estado_encuesta.call())
		_padlock.visible = not ProgressionManager.all_approved() or not encuesta_lista


func _mostrar_error_encuesta(error: String) -> void:
	if _locked_dialog == null:
		return
	SceneManager.is_ui_open = true
	_aviso_tomado = true
	_locked_dialog.title = "Encuesta pendiente"
	_locked_dialog.dialog_text = "%s\n\nLos cómics se desbloquearán cuando puedas enviar la encuesta." % error
	_locked_dialog.popup_centered()
	DialogFocus.preparar(_locked_dialog, false)


## Aviso de zona cerrada, con el slide-up del resto de diálogos del proyecto.
func _mostrar_bloqueo() -> void:
	if _locked_dialog == null:
		return
	SceneManager.is_ui_open = true
	_aviso_tomado = true
	_locked_dialog.title = "Zona de cómics"
	_locked_dialog.dialog_text = texto_bloqueo()
	Sonido.efecto("no")

	var dialog := _locked_dialog
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	dialog.transparent = true
	dialog.position = Vector2i(-10000, -10000)
	dialog.show()

	await get_tree().process_frame
	dialog.reset_size()
	dialog.min_size = Vector2i(700, 200)

	var pantalla := get_viewport().get_visible_rect().size
	var final_x := int((pantalla.x - dialog.size.x) / 2)
	var final_y := int(pantalla.y - dialog.size.y - 40)
	var desfase := 30
	dialog.position = Vector2i(final_x, final_y + desfase)

	for hijo in dialog.get_children():
		if hijo is Control:
			hijo.modulate.a = 0.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_method(func(y): dialog.position = Vector2i(final_x, y), final_y + desfase, final_y, 0.3)
	for hijo in dialog.get_children():
		if hijo is Control:
			tween.tween_property(hijo, "modulate:a", 1.0, 0.25).set_delay(0.05)

	DialogFocus.preparar(dialog, false)


func _on_aviso_visibility_changed() -> void:
	if not _locked_dialog.visible and _aviso_tomado:
		_aviso_tomado = false
		if not is_instance_valid(_catalogo):
			SceneManager.is_ui_open = false
