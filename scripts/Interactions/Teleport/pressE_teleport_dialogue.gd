extends Node2D

var player_in_range = false
@export_file("*.tscn") var target_scene_path: String

## Tipología textual (ej: "Narrativo", "Expositivo"). Si tiene valor,
## configura GameSession antes de transicionar para el flujo dinámico.
@export var typology: String = ""

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
		GameSession.current_typology = typology
		
		var level1: String = GENERIC_LEVEL1
		var level23: String = GENERIC_LEVEL23
		
		# Buscar si la tipología tiene escenas mapeadas, sino usa las genéricas (fallback)
		if GameSession.TYPOLOGY_SCENES.has(typology):
			var scenes: Dictionary = GameSession.TYPOLOGY_SCENES[typology]
			level1 = scenes.get("level1", GENERIC_LEVEL1)
			level23 = scenes.get("level23", GENERIC_LEVEL23)
			
		GameSession.configure_scenes(level23, level23, LOBBY)
		GameSession.level_scenes["Literal"] = level1
		
		# Reemplazar la escena objetivo configurada en el inspector por la calculada dinámicamente
		target_scene_path = level1
		
	change_scene()
