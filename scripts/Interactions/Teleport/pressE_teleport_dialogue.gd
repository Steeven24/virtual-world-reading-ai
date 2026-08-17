extends Node2D

## Señal emitida cuando el jugador interactúa con un punto marcado como
## tutorial (is_tutorial_trigger = true). El listener decide qué mostrar.
signal tutorial_triggered

var player_in_range = false
@export_file("*.tscn") var target_scene_path: String

## Tipología textual (ej: "Narrativo", "Expositivo"). Si tiene valor,
## configura GameSession antes de transicionar para el flujo dinámico.
@export var typology: String = ""

## Si es true, al presionar E no se muestra el ConfirmationDialog ni se
## cambia de escena: en su lugar se emite "tutorial_triggered" para que
## el lobby muestre el overlay del tutorial guiado.
@export var is_tutorial_trigger: bool = false

## Referencia al sprite del candado (hijo de esta escena).
var _padlock: Sprite2D = null

## Referencia al diálogo de nivel bloqueado.
var _locked_dialog: AcceptDialog = null

func _ready():
	$Area2D/message.visible = false
	# Conectamos desde el nodo que tiene la señal ($Area2D)
	$Area2D.body_entered.connect(_on_body_entered)
	$Area2D.body_exited.connect(_on_body_exited)
	$Area2D/confirm.confirmed.connect(_on_dialog_confirmed)
	$Area2D/confirm.canceled.connect(_on_dialog_closed)
	# Por si se cierra con la X o de otra forma
	$Area2D/confirm.visibility_changed.connect(
		func(): if not $Area2D/confirm.visible: _on_dialog_closed()
	)

	# ─── Configurar candado y diálogo de bloqueo ───────────────────────────
	_padlock = get_node_or_null("Padlock")
	_locked_dialog = get_node_or_null("LockedDialog")

	if _locked_dialog:
		_locked_dialog.visibility_changed.connect(
			func(): if not _locked_dialog.visible: _on_dialog_closed()
		)

	# Actualizar visibilidad del candado según estado de progresión
	if not typology.is_empty():
		_update_padlock_visibility()
		# Escuchar desbloqueos dinámicos
		ProgressionManager.level_unlocked.connect(_on_level_unlocked)

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		$Area2D/message.visible = true
		$"Speech bubble".visible = true
	
func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		$Area2D/message.visible = false
		$"Speech bubble".visible = false

func _process(delta):
	if player_in_range and Input.is_action_just_pressed("ui_accept"):
		# Modo tutorial: notificamos al listener (lobby) y no abrimos el confirm.
		if is_tutorial_trigger:
			if not SceneManager.is_ui_open:
				tutorial_triggered.emit()
			return
		# Verificar si el nivel está bloqueado
		if not typology.is_empty() and not ProgressionManager.is_unlocked(typology):
			_show_locked_dialog()
			return
		show_dialogue()
			

func show_dialogue():
	if SceneManager.is_ui_open:
		return
		
	SceneManager.is_ui_open = true
	var dialog = $Area2D/confirm
	
	# 1. Forzamos posicionamiento absoluto
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	
	# 2. Configuración de texto
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.min_size = Vector2i(500, 150)
	
	# 3. Hacemos la ventana completamente transparente y la posicionamos 
	# fuera de pantalla ANTES de mostrarla, para evitar el destello visual.
	dialog.transparent = true
	dialog.position = Vector2i(-10000, -10000)
	
	# 4. Mostramos el diálogo (invisible para el usuario)
	dialog.show()
	
	# 5. Esperamos a que Godot calcule el tamaño real
	await get_tree().process_frame
	dialog.reset_size()
	
	# 6. Cálculos de posición final
	var screen_size = get_viewport().get_visible_rect().size
	var final_x = (screen_size.x - dialog.size.x) / 2
	var final_y = screen_size.y - dialog.size.y - 40
	
	# 7. Animación de aparición: slide-up + fade-in
	var offset_y = 30 # pixeles que sube durante la animación
	dialog.position = Vector2i(final_x, final_y + offset_y)
	dialog.transparent = true
	
	# Ocultamos los hijos para hacer fade-in del contenido
	for child in dialog.get_children():
		if child is Control:
			child.modulate.a = 0.0
	
	# Tween para deslizar hacia arriba
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_method(func(y): dialog.position = Vector2i(final_x, y), final_y + offset_y, final_y, 0.3)
	
	# Fade-in del contenido interno
	for child in dialog.get_children():
		if child is Control:
			tween.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(0.05)
	

#func change_scene():
	#get_tree().change_scene_to_file(next_scene_path)
#
#func _on_dialog_confirmed():
	#if next_scene_path != "":
		#get_tree().change_scene_to_file(next_scene_path)
	#else:
		#print("Error: No has asignado una ruta de escena en el inspector.")

## Rutas de escenas genéricas para el flujo dinámico.
const GENERIC_LEVEL1 := "res://scenes/Scenery/Section/Generic Level/generic_level1.tscn"
const GENERIC_LEVEL23 := "res://scenes/Scenery/Section/Generic Level/generic_level2-3.tscn"
const LOBBY := "res://scenes/Scenery/Lobby/lobby.tscn"

func change_scene():
	SceneManager.transition_to(target_scene_path)


func _on_dialog_closed():
	SceneManager.is_ui_open = false


func _on_dialog_confirmed():
	_on_dialog_closed()
	# Si tiene tipología, configurar GameSession para el flujo dinámico
	if not typology.is_empty():
		var level1: String = GENERIC_LEVEL1
		var level23: String = GENERIC_LEVEL23
		
		# Buscar si la tipología tiene escenas mapeadas, sino usa las genéricas (fallback)
		if GameSession.TYPOLOGY_SCENES.has(typology):
			var scenes: Dictionary = GameSession.TYPOLOGY_SCENES[typology]
			level1 = scenes.get("level1", GENERIC_LEVEL1)
			level23 = scenes.get("level23", GENERIC_LEVEL23)
		
		# ─── Verificar lectura pendiente ─────────────────────────────────
		
		# Caso 1: GameSession activa con la MISMA tipología → restaurar en memoria
		if GameSession.is_active and GameSession.current_typology == typology:
			_resume_existing_session(level1, level23)
			return
		
		# Caso 2: GameSession activa con OTRA tipología → bloqueo inmediato
		# (No requiere API, es la detección más rápida y confiable)
		if GameSession.is_active and not GameSession.current_typology.is_empty() and GameSession.current_typology != typology:
			print("[Teleport] BLOQUEO: GameSession activa en '%s', intentando acceder a '%s'" % [GameSession.current_typology, typology])
			_show_pending_reading_warning(GameSession.current_typology)
			return
		
		# Caso 3: ReadingProgressManager tiene lectura pendiente (cacheada de la API)
		if ReadingProgressManager.has_active_reading():
			var pending_typology := ReadingProgressManager.get_active_typology()
			
			if pending_typology == typology:
				# Misma tipología → restaurar desde la API
				_restore_and_navigate(level1, level23)
				return
			else:
				# Otra tipología → mostrar advertencia
				print("[Teleport] BLOQUEO: Lectura pendiente en RPM '%s', intentando '%s'" % [pending_typology, typology])
				_show_pending_reading_warning(pending_typology)
				return
		
		# Caso 4: Sin lectura pendiente en memoria local, consultar API como última verificación
		if AuthManager.is_authenticated:
			# Guardar datos para usar después del check
			_pending_level1 = level1
			_pending_level23 = level23
			ReadingProgressManager.active_reading_check_completed.connect(
				_on_pending_check_result, CONNECT_ONE_SHOT
			)
			ReadingProgressManager.check_pending_reading()
			return
		
		# Caso 5: Sin autenticación o sin lectura pendiente → nueva sesión
		_start_new_session(level1, level23)
		return
		
	change_scene()


# ─── Variables temporales para el flujo async de verificación ──────────────

var _pending_level1: String = ""
var _pending_level23: String = ""


## Callback tras consultar la API por lectura pendiente.
func _on_pending_check_result(has_pending: bool, pending_typology: String) -> void:
	if has_pending:
		if pending_typology == typology:
			# Misma tipología → restaurar
			_restore_and_navigate(_pending_level1, _pending_level23)
		else:
			# Otra tipología → advertencia
			_show_pending_reading_warning(pending_typology)
	else:
		# Sin pendiente → nueva sesión
		_start_new_session(_pending_level1, _pending_level23)


## Reanuda una sesión que ya está activa en GameSession (misma tipología).
func _resume_existing_session(level1: String, level23: String) -> void:
	GameSession.configure_scenes(level23, level23, LOBBY)
	GameSession.level_scenes["Literal"] = level1
	
	# Determinar a qué escena ir según el estado actual
	if GameSession.current_reading.is_empty():
		# Lectura no cargada aún, ir a level1 para cargarla
		target_scene_path = level1
	elif GameSession.reading_end_time > 0:
		# Ya terminó la lectura, ir al escenario del nivel actual
		var current_level := GameSession.get_current_level()
		var scene: String = GameSession.level_scenes.get(current_level, "")
		target_scene_path = scene if not scene.is_empty() else level1
	else:
		# Aún leyendo, ir a level1 (que tiene el libro)
		target_scene_path = level1
	
	print("[Teleport] Reanudando sesión activa: nivel=%s → %s" % [
		GameSession.get_current_level(), target_scene_path
	])
	change_scene()


## Restaura la lectura desde la API y navega al punto correcto.
func _restore_and_navigate(level1: String, level23: String) -> void:
	GameSession.configure_scenes(level23, level23, LOBBY)
	GameSession.level_scenes["Literal"] = level1
	
	# Restaurar estado de GameSession desde los datos de ReadingProgressManager
	var active_data := ReadingProgressManager.get_active_data()
	var reading_id: int = int(active_data.get("reading_id", -1))
	
	if reading_id > 0:
		# Necesitamos cargar la lectura completa desde la API/cache
		GameSession.current_typology = typology
		
		# Parsear el estado guardado
		var state_data := {}
		state_data["current_level_index"] = int(active_data.get("current_level_index", 0))
		state_data["current_question_index"] = int(active_data.get("current_question_index", 0))
		state_data["session_score"] = int(active_data.get("session_score", 0))
		state_data["reading_completed"] = active_data.get("reading_completed", false)
		state_data["reading_start_time"] = active_data.get("reading_start_time", "0")
		
		# Parsear JSON de resultados y herramientas
		var json := JSON.new()
		var results_str: String = str(active_data.get("results_json", "[]"))
		if json.parse(results_str) == OK and json.data is Array:
			state_data["results"] = json.data
		else:
			state_data["results"] = []
		
		var tools_str: String = str(active_data.get("tools_used_json", "{}"))
		if json.parse(tools_str) == OK and json.data is Dictionary:
			state_data["tools_used"] = json.data
		else:
			state_data["tools_used"] = {"highlight": false, "underline": false, "notes": false}
		
		# Cargar la lectura completa desde la API para restaurar current_reading
		# Conectamos a la señal de lectura cargada
		_pending_restore_state = state_data
		_pending_restore_level1 = level1
		ReadingAPI.full_reading_loaded.connect(_on_restore_reading_loaded, CONNECT_ONE_SHOT)
		ReadingAPI.request_failed.connect(_on_restore_reading_failed, CONNECT_ONE_SHOT)
		ReadingAPI.get_reading_full(reading_id)
	else:
		# No hay reading_id válido, iniciar nueva sesión
		_start_new_session(level1, level23)


var _pending_restore_state: Dictionary = {}
var _pending_restore_level1: String = ""


func _on_restore_reading_loaded(data: Dictionary) -> void:
	if ReadingAPI.request_failed.is_connected(_on_restore_reading_failed):
		ReadingAPI.request_failed.disconnect(_on_restore_reading_failed)
	
	if data.is_empty():
		# La lectura ya no existe, limpiar y empezar nueva
		ReadingProgressManager.clear_active_reading()
		push_warning("[Teleport] Lectura restaurada vacía, limpiando lectura activa")
		return
	
	# Alimentar GameSession con la lectura completa
	GameSession.start_session_with_data(data)
	# Restaurar el estado guardado (nivel, pregunta, score, etc.)
	GameSession.restore_state(_pending_restore_state)
	
	# Navegar al punto correcto
	if _pending_restore_state.get("reading_completed", false):
		# Ya terminó la lectura, ir al escenario del nivel actual
		var current_level := GameSession.get_current_level()
		var scene: String = GameSession.level_scenes.get(current_level, "")
		target_scene_path = scene if not scene.is_empty() else _pending_restore_level1
	else:
		# Aún leyendo, ir a level1
		target_scene_path = _pending_restore_level1
	
	print("[Teleport] Lectura restaurada desde API, navegando a: %s" % target_scene_path)
	change_scene()


func _on_restore_reading_failed(_endpoint: String, _error: String) -> void:
	if ReadingAPI.full_reading_loaded.is_connected(_on_restore_reading_loaded):
		ReadingAPI.full_reading_loaded.disconnect(_on_restore_reading_loaded)
	# La lectura falló al cargar (probablemente eliminada), limpiar
	ReadingProgressManager.clear_active_reading()
	push_warning("[Teleport] Falló restauración de lectura, limpiando lectura activa")


## Inicia una nueva sesión de lectura (flujo normal sin lectura pendiente).
func _start_new_session(level1: String, level23: String) -> void:
	# IMPORTANTE: Resetear completamente el estado anterior de GameSession
	# para evitar que bookAndTools reutilice una lectura de otro escenario.
	GameSession.is_active = false
	GameSession.current_reading = {}
	GameSession.current_level_index = 0
	GameSession.current_question_index = 0
	GameSession.results.clear()
	GameSession.reading_end_time = 0.0
	GameSession.tools_used = {"highlight": false, "underline": false, "notes": false}
	
	GameSession.current_typology = typology
	GameSession.configure_scenes(level23, level23, LOBBY)
	GameSession.level_scenes["Literal"] = level1
	target_scene_path = level1
	change_scene()


# ─── Diálogo de advertencia de lectura pendiente ─────────────────────────────

var _pending_dialog: AcceptDialog = null


func _create_pending_dialog() -> void:
	_pending_dialog = AcceptDialog.new()
	_pending_dialog.title = "Lectura pendiente"
	_pending_dialog.ok_button_text = "Aceptar"
	add_child(_pending_dialog)
	_pending_dialog.confirmed.connect(_on_pending_dialog_accepted)
	_pending_dialog.visibility_changed.connect(
		func(): if not _pending_dialog.visible: _on_dialog_closed()
	)


func _show_pending_reading_warning(pending_typology: String) -> void:
	if not _pending_dialog:
		_create_pending_dialog()
	
	_pending_dialog.dialog_text = "⚠️ Tienes una lectura pendiente en el escenario %s.\n\nDebes terminarla antes de iniciar una nueva.\n\nRegresa al lobby y busca el escenario %s para continuar." % [
		pending_typology, pending_typology
	]
	
	# Animación slide-up (misma estética del proyecto)
	var dialog := _pending_dialog
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	dialog.transparent = true
	dialog.position = Vector2i(-10000, -10000)
	dialog.min_size = Vector2i(800, 200)
	
	SceneManager.is_ui_open = true
	dialog.show()
	
	await get_tree().process_frame
	dialog.reset_size()
	
	var screen_size := get_viewport().get_visible_rect().size
	var final_x: int = int((screen_size.x - dialog.size.x) / 2)
	var final_y: int = int(screen_size.y - dialog.size.y - 40)
	
	var offset_y: int = 30
	dialog.position = Vector2i(final_x, final_y + offset_y)
	
	for child in dialog.get_children():
		if child is Control:
			child.modulate.a = 0.0
	
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_method(func(y): dialog.position = Vector2i(final_x, y), final_y + offset_y, final_y, 0.3)
	
	for child in dialog.get_children():
		if child is Control:
			tween.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(0.05)


func _on_pending_dialog_accepted() -> void:
	_on_dialog_closed()
	# No hacer nada más: el jugador se queda donde está.
	# Puede ir al lobby y buscar el escenario correcto.



# ─── Sistema de candado y bloqueo ───────────────────────────────────────────

## Actualiza la visibilidad del candado según el estado de progresión.
func _update_padlock_visibility() -> void:
	if _padlock and not typology.is_empty():
		_padlock.visible = not ProgressionManager.is_unlocked(typology)


## Muestra el diálogo de nivel bloqueado con animación slide-up.
func _show_locked_dialog() -> void:
	if SceneManager.is_ui_open:
		return

	if not _locked_dialog:
		return

	SceneManager.is_ui_open = true

	# Obtener información del bloqueo para personalizar el mensaje
	var lock_info: Dictionary = ProgressionManager.get_lock_info(typology)
	if lock_info.get("locked", false):
		var req_typology: String = lock_info.get("required_typology", "")
		var req_score: int = lock_info.get("required_score", 0)
		var current: int = lock_info.get("current_score", 0)
		var difficulty: String = lock_info.get("difficulty_label", "")

		_locked_dialog.dialog_text = "🔒 Este nivel (%s) está bloqueado.\n\nNecesitas obtener al menos %d puntos en %s para desbloquearlo.\nTu mejor puntaje actual en %s: %d pts.\n\n¡Usa todas las herramientas y responde correctamente para desbloquear!" % [
			difficulty, req_score, req_typology, req_typology, current
		]
	else:
		_locked_dialog.dialog_text = "🔒 Este nivel aún está bloqueado."

	var dialog := _locked_dialog

	# Animación slide-up (misma estética que los otros diálogos del proyecto)
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	dialog.transparent = true
	dialog.position = Vector2i(-10000, -10000)

	dialog.show()

	await get_tree().process_frame
	dialog.reset_size()
	dialog.min_size = Vector2i(700, 200)

	var screen_size := get_viewport().get_visible_rect().size
	var final_x: int = int((screen_size.x - dialog.size.x) / 2)
	var final_y: int = int(screen_size.y - dialog.size.y - 40)

	var offset_y: int = 30
	dialog.position = Vector2i(final_x, final_y + offset_y)

	for child in dialog.get_children():
		if child is Control:
			child.modulate.a = 0.0

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_method(func(y): dialog.position = Vector2i(final_x, y), final_y + offset_y, final_y, 0.3)

	for child in dialog.get_children():
		if child is Control:
			tween.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(0.05)


## Callback cuando ProgressionManager desbloquea una tipología.
func _on_level_unlocked(unlocked_typology: String) -> void:
	if unlocked_typology == typology:
		_update_padlock_visibility()
