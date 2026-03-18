extends Area2D

@export var next_scene_path: String
var player_in_range = false

func _ready():
	$message.visible = false
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))
	$confirm.confirmed.connect(_on_dialog_confirmed)

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		$message.visible = true
		$"../../Speech bubble".visible = true

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		$message.visible = false
		$"../../Speech bubble".visible = false

func _process(delta):
	if player_in_range and Input.is_action_just_pressed("ui_accept"):
		show_dialogue()
			

func show_dialogue():
	$confirm.visible = true
	print("¡Hola! Este es un diálogo.")

func change_scene():
	get_tree().change_scene_to_file(next_scene_path)

func _on_dialog_confirmed():
	if next_scene_path != "":
		get_tree().change_scene_to_file(next_scene_path)
	else:
		print("Error: No has asignado una ruta de escena en el inspector.")
		
		
		
		
		
