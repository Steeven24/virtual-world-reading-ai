extends Node2D

@export var sprite_resource: Texture2D
@export var prompt_sprite_resource: Texture2D
@export var dialog_theme: Theme
@export_enum("default", "frente", "izquierda", "derecha") var character_pose: String = "frente"

signal request_challenge(context)

var player_in_range = false

@onready var anim_sprite = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
@onready var prompt_bubble = $"Speech bubble" if has_node("Speech bubble") else null
@onready var confirm_dialog = $ConfirmationDialog if has_node("ConfirmationDialog") else null
@onready var area_2d = $Area2D if has_node("Area2D") else null

func _ready():
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
	confirm_dialog.dialog_text = "¿Listo para el desafío? Al aceptar se iniciará el ejercicio."
	confirm_dialog.popup_centered()

func _on_dialog_confirmed():
	SceneManager.is_ui_open = false
	var context = {
		"typology": GameSession.current_typology,
		"teacher_texture": anim_sprite.sprite_frames if anim_sprite else null
	}
	request_challenge.emit(context)

func _on_dialog_canceled():
	SceneManager.is_ui_open = false
