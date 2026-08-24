## Controlador de los escenarios de nivel.
##
## Gestiona la coreografía de NPCs de la sala (quién está visible en cada fase)
## y muestra las guías de "qué hacer ahora" al terminar la lectura y al
## completar cada nivel de comprensión.
extends Node2D

const GUIDE_PANEL_SCENE: String = "res://scenes/UI/guide_panel.tscn"

## Retraso antes de mostrar una guía. Cumple dos funciones:
##  - deja que el jugador vea primero dónde ha aterrizado;
##  - evita pisarse con el cierre del libro, porque bookAndTools emite
##    warning_accepted y solo DESPUÉS cierra el libro poniendo is_ui_open a
##    false. Abrir el panel en ese mismo frame lo dejaría desincronizado y
##    el jugador acabaría congelado al cerrarlo.
const GUIDE_DELAY: float = 0.35

## Guía que se muestra al llegar a la sala, indexada por el nivel que el
## jugador está a punto de empezar.
const LEVEL_INTRO_MESSAGES: Dictionary = {
	"Inferencial": {
		"title": "✅ ¡Nivel Literal completado!",
		"body": "Has demostrado que localizas la información que el texto dice de forma explícita.\n\n[color=#f0c050][b]➜ Acércate al profesor y pulsa E[/b][/color] para empezar el desafío [b]Inferencial[/b]: ahora tendrás que deducir lo que el texto sugiere sin decirlo con todas las letras.",
		"button": "¡Vamos allá! ✓",
	},
	"Critico": {
		"title": "✅ ¡Nivel Inferencial completado!",
		"body": "Ya has demostrado que sabes leer entre líneas.\n\n[color=#f0c050][b]➜ Último paso: acércate al profesor y pulsa E[/b][/color] para el desafío [b]Crítico[/b]. Aquí no hay datos que buscar: tendrás que valorar el texto y justificar tu opinión.",
		"button": "¡Adelante! ✓",
	},
}

## Guía que se muestra al cerrar la lectura, cuando aparece el profesor.
const READING_DONE_MESSAGE: Dictionary = {
	"title": "📖 ¡Lectura completada!",
	"body": "Ya conoces el texto. Ahora toca demostrar que lo has entendido.\n\n[color=#f0c050][b]➜ Acércate al profesor y pulsa E[/b][/color] para empezar el desafío [b]Literal[/b]: preguntas sobre lo que el texto dice de forma explícita.",
	"button": "¡Entendido! ✓",
}

@onready var book_interaction = $Book if has_node("Book") else null
@onready var canvas_layer = $CanvasLayer if has_node("CanvasLayer") else null
@onready var lectura_y_libro = canvas_layer.get_node("LecturaYLibro") if canvas_layer and canvas_layer.has_node("LecturaYLibro") else null
@onready var wise_old_man = $WiseOldMan if has_node("WiseOldMan") else null
@onready var teacher = $Teacher if has_node("Teacher") else null
@onready var robot_assistant = $RobotAssistant if has_node("RobotAssistant") else null

func _ready():
	# El Teacher inicia oculto solo si hay una fase de lectura (Level 1)
	if teacher:
		if lectura_y_libro or book_interaction:
			teacher.visible = false
		else:
			teacher.visible = true
		
		# Conectar señal del teacher para cargar el desafío
		if not teacher.request_challenge.is_connected(_on_teacher_request_challenge):
			teacher.request_challenge.connect(_on_teacher_request_challenge)
	
	# Conectar señal del libro
	if lectura_y_libro:
		if not lectura_y_libro.warning_accepted.is_connected(_on_book_warning_accepted):
			lectura_y_libro.warning_accepted.connect(_on_book_warning_accepted)

	# Si se llega aquí tras completar un nivel, explicar qué toca ahora.
	_show_level_intro_if_needed()

func _on_book_warning_accepted():
	# Ocultar NPCs de lectura
	if wise_old_man:
		wise_old_man.visible = false
			
	if robot_assistant:
		robot_assistant.visible = false
	
	# Si existe el Book Interaction (el sprite del libro en el suelo), ocultarlo también
	if book_interaction:
		book_interaction.visible = false
			
	# Activar el Teacher
	if teacher:
		teacher.visible = true

	# El profesor acaba de aparecer: decir al jugador que vaya a hablar con él.
	_show_guide_delayed(READING_DONE_MESSAGE)

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
		elif teacher and "target_scene_path" in teacher and not teacher.target_scene_path.is_empty():
			SceneManager.transition_to(teacher.target_scene_path)
		else:
			push_error("LevelController: No se encontró escena destino para el desafío.")

# ─── Guías de siguiente paso ────────────────────────────────────────────────

## Muestra la guía de "nivel completado → esto es lo siguiente" al aterrizar en
## la sala del nivel Inferencial o Crítico.
##
## advance_to_next() incrementa current_level_index ANTES de devolver la ruta
## de esta sala, así que al llegar aquí el índice ya apunta al nivel que toca.
func _show_level_intro_if_needed() -> void:
	if not GameSession.is_active:
		return

	# En los escenarios con fase de lectura el nivel aún no ha empezado. Una
	# sesión reanudada en el nivel Literal también aterriza en uno de ellos.
	if lectura_y_libro or book_interaction:
		return

	var level: String = GameSession.get_current_level()
	if not LEVEL_INTRO_MESSAGES.has(level):
		return

	_show_guide_delayed(LEVEL_INTRO_MESSAGES[level])


## Espera GUIDE_DELAY y muestra el panel de guía con el mensaje dado.
func _show_guide_delayed(message: Dictionary) -> void:
	await get_tree().create_timer(GUIDE_DELAY).timeout

	var packed: PackedScene = load(GUIDE_PANEL_SCENE)
	if packed == null:
		push_warning("LevelController: No se pudo cargar el panel de guía.")
		return

	var panel := packed.instantiate()
	add_child(panel)
	panel.show_message(
		str(message.get("title", "")),
		str(message.get("body", "")),
		str(message.get("button", "¡Entendido! ✓"))
	)
