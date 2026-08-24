## El Profesor: plantea los desafíos de comprensión.
##
## Su papel es evaluar. Antes de empezar anuncia qué nivel toca (Literal,
## Inferencial o Crítico) y sobre qué tipología, para que el alumno sepa qué
## tipo de pregunta le espera al aceptar.
##
## Los textos van sin BBCode a propósito: ConfirmationDialog.dialog_text no
## lo interpreta.
extends Node2D

## Presentación de la primera vez, para dejar claro el reparto de papeles
## entre el sabio, el robot y el profesor.
const INTRO_MESSAGE := """Soy el profesor: yo te pongo a prueba. Te plantearé tres desafíos sobre el texto que has leído, según su tipología: LITERAL (lo que el texto dice), INFERENCIAL (lo que deja entender) y CRÍTICO (lo que tú opinas y por qué).

Para consejos generales de lectura habla con el sabio; para dudas concretas del texto, con el robot asistente.

Empezamos por el literal. ¿Listo?"""

## Qué se le pide al alumno en cada nivel de comprensión.
const LEVEL_BRIEFINGS: Dictionary = {
	"Literal": "Te preguntaré por lo que el texto dice de forma explícita: datos, nombres y hechos que están escritos tal cual.",
	"Inferencial": "Aquí no basta con buscar: tendrás que deducir lo que el texto sugiere sin llegar a decirlo con todas las letras.",
	"Critico": "Este es el último. No hay datos que localizar: tendrás que valorar el texto y justificar tu opinión.",
}

## Nombre visible de cada nivel (en GameSession "Critico" va sin tilde).
const LEVEL_NAMES: Dictionary = {
	"Literal": "LITERAL",
	"Inferencial": "INFERENCIAL",
	"Critico": "CRÍTICO",
}

@export var sprite_resource: Texture2D
@export var prompt_sprite_resource: Texture2D
@export var dialog_theme: Theme
@export_enum("default", "frente", "izquierda", "derecha") var character_pose: String = "frente"
@export_file("*.tscn") var target_scene_path: String

signal request_challenge(context)

var player_in_range = false

@onready var anim_sprite = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
@onready var prompt_bubble = $"Speech bubble" if has_node("Speech bubble") else null
@onready var confirm_dialog = $ConfirmationDialog if has_node("ConfirmationDialog") else null
@onready var area_2d = $Area2D if has_node("Area2D") else null

func _ready():
	visibility_changed.connect(_on_visibility_changed)
	
	if anim_sprite:
		anim_sprite.play(character_pose)
			
	if prompt_bubble:
		prompt_bubble.visible = false
		if prompt_sprite_resource:
			prompt_bubble.texture = prompt_sprite_resource
			
	if confirm_dialog:
		if dialog_theme:
			confirm_dialog.theme = dialog_theme
		confirm_dialog.confirmed.connect(_on_dialog_confirmed)
		confirm_dialog.canceled.connect(_on_dialog_canceled)
		
	if area_2d:
		area_2d.body_entered.connect(_on_body_entered)
		area_2d.body_exited.connect(_on_body_exited)
		
	# Alinear colisiones al estado inicial
	_on_visibility_changed()

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		if prompt_bubble:
			prompt_bubble.visible = true

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		if prompt_bubble:
			prompt_bubble.visible = false

func _process(_delta):
	# Solo permitir interaccion si esta visible (es decir, en la fase correcta)
	if player_in_range and visible and Input.is_action_just_pressed("ui_accept"):
		if not SceneManager.is_ui_open:
			show_dialogue()

func show_dialogue():
	if not confirm_dialog:
		push_warning("Teacher: No ConfirmationDialog found.")
		return
		
	SceneManager.is_ui_open = true
	confirm_dialog.dialog_text = _build_dialog_text()
	confirm_dialog.popup_centered()


## La primera vez el profesor se presenta; después anuncia el nivel que toca
## y qué tipo de pregunta espera al alumno.
func _build_dialog_text() -> String:
	if not GameSession.is_hint_seen(GameSession.HINT_INTRO_TEACHER):
		GameSession.mark_hint_seen(GameSession.HINT_INTRO_TEACHER)
		return INTRO_MESSAGE

	var level: String = GameSession.get_current_level()
	var briefing: String = str(LEVEL_BRIEFINGS.get(level, ""))
	if briefing.is_empty():
		return "¿Listo para el desafío? Al aceptar se iniciará el ejercicio."

	var header := "Desafío %s" % str(LEVEL_NAMES.get(level, level.to_upper()))
	var typology: String = GameSession.current_typology
	if not typology.is_empty():
		header += " — texto %s" % typology

	return "%s\n\n%s\n\n¿Empezamos?" % [header, briefing]

func _on_dialog_confirmed():
	SceneManager.is_ui_open = false
	var context = {
		"typology": GameSession.current_typology,
		"teacher_texture": anim_sprite.sprite_frames if anim_sprite else null
	}
	request_challenge.emit(context)

func _on_dialog_canceled():
	SceneManager.is_ui_open = false

func _on_visibility_changed():
	if not visible:
		player_in_range = false
		if prompt_bubble:
			prompt_bubble.visible = false
	_set_collision_shapes_disabled(self, not visible)

func _set_collision_shapes_disabled(node: Node, should_disable: bool):
	if node is CollisionShape2D:
		node.set_deferred("disabled", should_disable)
	for child in node.get_children():
		_set_collision_shapes_disabled(child, should_disable)
