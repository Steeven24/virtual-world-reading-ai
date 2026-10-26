## Prueba del sillón de la zona de cómics. Se lanza en headless:
##   Godot --headless --path <copia aislada> --quit-after 4000 res://scenes/Testing/test_sillon_comics.tscn
## IMPORTANTE: ejecutar sobre una copia con config/use_custom_user_dir, nunca sobre el
## user:// real: AuthManager restaura el token guardado y se harían peticiones
## reales con la cuenta del alumno. La guarda de abajo es post-hoc (ComicLibrary ya lanzó su petición en su
## _ready, antes que este): la protección real es la copia aislada.
extends Node

const ESCENA_SILLON := "res://scenes/Interactuable/pressE_comics.tscn"
const ESCENA_ESTACION := "res://scenes/Interactuable/pressE_Confirmation.tscn"
const ESCENA_JUGADOR := "res://scenes/Player/player.tscn"
const TIPOLOGIAS := ["Narrativo", "Descriptivo", "Argumentativo", "Expositivo"]

var _fallos := 0
var _visitas := 0


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK    - %s" % descripcion)
	else:
		_fallos += 1
		print("FALLO - %s" % descripcion)


func _ready() -> void:
	for ruta in [ESCENA_SILLON, ESCENA_ESTACION, ESCENA_JUGADOR]:
		if load(ruta) == null:
			print("FALLO - no carga %s" % ruta)
			print("RESULTADO: ROJO (no carga)")
			get_tree().quit(1)
			return
	print("USERDIR: %s" % OS.get_user_data_dir())
	if not (OS.get_user_data_dir().contains("vw_prueba_t10") or OS.get_user_data_dir().contains("vw_prueba_encuesta")):
		push_error("ABORTADO: el user:// no es el aislado de la prueba.")
		get_tree().quit(2)
		return
	if AuthManager.is_authenticated or not AuthManager.auth_token.is_empty():
		push_error("ABORTADO: hay una sesión real restaurada; ejecuta la prueba en una copia con user:// aislado.")
		get_tree().quit(2)
		return
	await _probar()
	print("RESULTADO: %s (%d fallos)" % ["VERDE" if _fallos == 0 else "ROJO", _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)


func _contar_visita() -> void:
	_visitas += 1


func _reiniciar() -> void:
	ProgressionManager.reset_all()
	GameSession.is_active = false
	GameSession.current_typology = ""
	SceneManager.is_ui_open = false
	_visitas = 0


func _aprobar(tipologia: String) -> void:
	ProgressionManager.best_scores[tipologia] = 1000


func _nuevo_sillon() -> Node:
	var sillon: Node = load(ESCENA_SILLON).instantiate()
	sillon.registrar_visita = _contar_visita
	# Las pruebas del sillón no dependen de red: por defecto simulan una encuesta
	# ya respondida; el caso obligatorio se prueba explícitamente abajo.
	sillon.estado_encuesta = func(): return true
	add_child(sillon)
	return sillon


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func _probar() -> void:
	# 1. Sin las cuatro aprobadas: candado y mensaje que pide aprobarlas
	_reiniciar()
	for t in ["Narrativo", "Descriptivo", "Argumentativo"]:
		_aprobar(t)
	var sillon := _nuevo_sillon()
	_comprobar(not ProgressionManager.all_approved(), "preparado: faltan tipologías por aprobar")
	_comprobar(sillon.candado_visible(), "con tres aprobadas el candado se ve")
	_comprobar(sillon.texto_bloqueo().contains("Aprueba las cuatro tipologías"), "el mensaje pide aprobarlas (%s)" % sillon.texto_bloqueo().left(60))
	_comprobar(not sillon.texto_bloqueo().contains("fuera de alcance"), "el mensaje normal no habla de fuera de alcance")
	sillon.interactuar()
	await _frames()
	var aviso: AcceptDialog = sillon.get_node("LockedDialog")
	_comprobar(aviso.visible and aviso.dialog_text == sillon.texto_bloqueo(), "E muestra el aviso de bloqueo")
	_comprobar(not sillon.catalogo_abierto() and _visitas == 0, "E no abre el catálogo ni cuenta visita")
	aviso.hide()
	await _frames()
	_comprobar(not SceneManager.is_ui_open, "al cerrar el aviso se libera al jugador")

	# 2. Aprobar la última en vivo quita el candado sin recargar la escena
	_aprobar("Expositivo")
	ProgressionManager.progression_changed.emit()
	_comprobar(not sillon.candado_visible(), "con la encuesta simulada como respondida, aprobar la última quita el candado")
	ProgressionManager.reset_all()
	_comprobar(sillon.candado_visible(), "reiniciar la progresión vuelve a poner el candado")
	sillon.queue_free()
	await _frames()

	# 3. Con progreso completo pero sin encuesta: abre el formulario, no los cómics.
	_reiniciar()
	for t in TIPOLOGIAS:
		_aprobar(t)
	sillon = _nuevo_sillon()
	sillon.estado_encuesta = func(): return false
	sillon.interactuar()
	await _frames()
	_comprobar(sillon.encuesta_abierta(), "sin respuesta abre la encuesta obligatoria")
	_comprobar(not sillon.catalogo_abierto() and _visitas == 0, "sin encuesta no abre ni cuenta visita")
	_comprobar(SceneManager.is_ui_open, "la encuesta inmoviliza al jugador")
	var encuesta: Node = sillon.get_child(sillon.get_child_count() - 1)
	encuesta.cerrado.emit()
	await _frames()
	_comprobar(not sillon.encuesta_abierta() and not SceneManager.is_ui_open, "responder después cierra sin desbloquear")
	sillon.queue_free()
	await _frames()

	# 4. Juego terminado sin aprobar todas: fuera de alcance, no «apruébalas»
	_reiniciar()
	_aprobar("Narrativo")
	ProgressionManager.intentos["Descriptivo"] = ProgressionManager.MAX_INTENTOS
	ProgressionManager.unlocked = ["Narrativo", "Descriptivo"]
	sillon = _nuevo_sillon()
	_comprobar(ProgressionManager.juego_terminado(), "preparado: el juego terminó")
	_comprobar(sillon.candado_visible(), "con el juego terminado el candado se ve")
	var texto: String = sillon.texto_bloqueo()
	_comprobar(texto.contains("fuera de alcance"), "el mensaje dice que la zona quedó fuera de alcance")
	_comprobar(texto.contains("Textos Descriptivos"), "el mensaje nombra el escenario sin intentos")
	_comprobar(not texto.contains("Aprueba"), "el mensaje no pide aprobarlas")
	sillon.interactuar()
	await _frames()
	aviso = sillon.get_node("LockedDialog")
	_comprobar(aviso.visible and aviso.dialog_text == texto, "E muestra el aviso de fuera de alcance")
	_comprobar(not sillon.catalogo_abierto() and _visitas == 0, "el alumno sin intentos no entra")
	aviso.hide()
	await _frames()
	sillon.queue_free()
	await _frames()

	# 5. Con encuesta respondida y una lectura de progresión a medias: entra igual
	_reiniciar()
	for t in TIPOLOGIAS:
		_aprobar(t)
	GameSession.is_active = true
	GameSession.current_typology = "Narrativo"
	sillon = _nuevo_sillon()
	_comprobar(GameSession.current_progression_typology() == "Narrativo", "preparado: hay una lectura a medias")
	_comprobar(not sillon.candado_visible(), "con las cuatro aprobadas no hay candado")
	var jugador: CharacterBody2D = load(ESCENA_JUGADOR).instantiate()
	jugador.name = "Player"
	add_child(jugador)
	sillon._on_body_entered(jugador)
	_comprobar(sillon.get_node("Speech bubble").visible, "junto al sillón aparece el globo de E")
	sillon.interactuar()
	await _frames()
	_comprobar(sillon.catalogo_abierto(), "E abre el catálogo aunque haya una lectura a medias")
	_comprobar(_visitas == 1, "E llama a registrar_visita una vez (%d)" % _visitas)
	_comprobar(sillon.get_node("LockedDialog").visible == false, "sin aviso de bloqueo ni de lectura pendiente")
	sillon.interactuar()
	await _frames()
	_comprobar(_visitas == 1, "E con el catálogo abierto no cuenta otra visita")

	# 6. Con el catálogo abierto: ni movimiento ni otras interacciones
	_comprobar(SceneManager.is_ui_open, "con el catálogo abierto la interfaz está tomada")
	var antes := jugador.global_position
	Input.action_press("move_right")
	await _frames(10)
	Input.action_release("move_right")
	_comprobar(jugador.global_position.is_equal_approx(antes), "el jugador no se mueve con el catálogo abierto (%s)" % jugador.global_position)

	var estacion: Node = load(ESCENA_ESTACION).instantiate()
	estacion.typology = "Narrativo"
	add_child(estacion)
	estacion._on_body_entered(jugador)
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	_comprobar(not estacion.get_node("Area2D/confirm").visible, "una estación del lobby no responde a E con el catálogo abierto")
	ev.pressed = false
	Input.parse_input_event(ev)
	await _frames()
	estacion.queue_free()

	# 7. Cerrar el catálogo devuelve el control
	var catalogo: Node = sillon.get_child(sillon.get_child_count() - 1)
	_comprobar(catalogo is CanvasLayer and catalogo.has_signal("cerrado"), "el último hijo del sillón es el catálogo")
	catalogo.cerrado.emit()
	await _frames()
	_comprobar(not sillon.catalogo_abierto() and not is_instance_valid(catalogo), "al cerrar se libera el catálogo")
	_comprobar(not SceneManager.is_ui_open, "al cerrar el jugador vuelve a poder moverse")
	Input.action_press("move_right")
	await _frames(10)
	Input.action_release("move_right")
	_comprobar(jugador.global_position.x > antes.x, "tras cerrar el jugador se mueve (%s)" % jugador.global_position)
	sillon.interactuar()
	await _frames()
	_comprobar(sillon.catalogo_abierto() and _visitas == 2, "se puede volver a entrar y cuenta otra visita (%d)" % _visitas)
	sillon.queue_free()
	jugador.queue_free()
	await _frames()
	_comprobar(not SceneManager.is_ui_open, "descargar el sillón con el catálogo abierto libera al jugador")

	# 8. Descargar el sillón con el aviso de bloqueo abierto también libera
	_reiniciar()
	sillon = _nuevo_sillon()
	sillon.interactuar()
	await _frames()
	_comprobar(sillon.get_node("LockedDialog").visible and SceneManager.is_ui_open, "preparado: aviso abierto y jugador inmovilizado")
	sillon.free()
	_comprobar(not SceneManager.is_ui_open, "descargar el sillón con el aviso abierto libera al jugador")
