extends Node2D

#@export var target_scene: PackedScene
var player_in_range = false
#@export var target_scene: PackedScene
# Usamos export_file para que Godot nos dé un selector de archivos en el inspector
@export_file("*.tscn") var target_scene_path: String

		
func change_scene():
	SceneManager.transition_to(target_scene_path)

func _ready():
	$Book/Area2D/message.visible = false
	# Conectamos desde el nodo que tiene la señal ($Area2D)
	$Book/Area2D.body_entered.connect(_on_body_entered)
	$Book/Area2D.body_exited.connect(_on_body_exited)
	$Book/Area2D/confirm.confirmed.connect(_on_dialog_confirmed)

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		$Book/Area2D/message.visible = true
		$"Speech bubble".visible = true

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		$Book/Area2D/message.visible = false
		$"Speech bubble".visible = false

func _process(delta):
	if player_in_range and Input.is_action_just_pressed("ui_accept"):
		show_dialogue()
			

func show_dialogue():
	$Book/Area2D/confirm.visible = true
	print("¡Hola! Este es un diálogo.")




func _on_dialog_confirmed():
		change_scene()
	
		

		
		
		
		
		
