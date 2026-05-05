extends Node2D

@onready var book_interaction = $Book if has_node("Book") else null
@onready var canvas_layer = $CanvasLayer if has_node("CanvasLayer") else null
@onready var lectura_y_libro = canvas_layer.get_node("LecturaYLibro") if canvas_layer and canvas_layer.has_node("LecturaYLibro") else null
@onready var wise_old_man = $WiseOldMan if has_node("WiseOldMan") else null
@onready var teacher = $Teacher if has_node("Teacher") else null
@onready var robot_assistant = $RobotAssistant if has_node("RobotAssistant") else null

func _ready():
	# El Teacher inicia oculto y sin colisiones
	if teacher:
		teacher.visible = false
		var teacher_area = teacher.get_node_or_null("Area2D/CollisionShape2D")
		if teacher_area:
			teacher_area.set_deferred("disabled", true)
		
		# Conectar señal del teacher para cargar el desafío
		if not teacher.request_challenge.is_connected(_on_teacher_request_challenge):
			teacher.request_challenge.connect(_on_teacher_request_challenge)
	
	# Conectar señal del libro
	if lectura_y_libro:
		if not lectura_y_libro.warning_accepted.is_connected(_on_book_warning_accepted):
			lectura_y_libro.warning_accepted.connect(_on_book_warning_accepted)

func _on_book_warning_accepted():
	# Ocultar NPCs de lectura
	if wise_old_man:
		wise_old_man.visible = false
		var wom_area = wise_old_man.get_node_or_null("Area2D/CollisionShape2D")
		if wom_area:
			wom_area.set_deferred("disabled", true)
			
	if robot_assistant:
		robot_assistant.visible = false
		var robot_area = robot_assistant.get_node_or_null("Area2D/CollisionShape2D")
		if robot_area:
			robot_area.set_deferred("disabled", true)
	
	# Si existe el Book Interaction (el sprite del libro en el suelo), ocultarlo también
	if book_interaction:
		book_interaction.visible = false
		var book_area = book_interaction.get_node_or_null("Area2D/CollisionShape2D")
		if book_area:
			book_area.set_deferred("disabled", true)
			
	# Activar el Teacher
	if teacher:
		teacher.visible = true
		var teacher_area = teacher.get_node_or_null("Area2D/CollisionShape2D")
		if teacher_area:
			teacher_area.set_deferred("disabled", false)

func _on_teacher_request_challenge(context):
	# En el futuro, inyectar el texture_teacher al GameSession o pasarlo al SceneManager
	# context["teacher_texture"] puede usarse para la pantalla de feedback
	
	# Desconectar señales de la API si es necesario, aunque bookAndTools ya lo hace
	# al salir de la escena
	
	if GameSession.is_active:
		# Si hay una sesión activa de la API
		SceneManager.transition_to(GameSession.QUIZ_SCENE)
	else:
		# Modo legacy
		if lectura_y_libro and not lectura_y_libro.target_scene_path.is_empty():
			SceneManager.transition_to(lectura_y_libro.target_scene_path)
		elif book_interaction and not book_interaction.target_scene_path.is_empty():
			# Book_interaction.target_scene_path suele apuntar a quiz si legacy
			SceneManager.transition_to(book_interaction.target_scene_path)
		else:
			push_error("LevelController: No se encontró escena destino para el desafío.")
