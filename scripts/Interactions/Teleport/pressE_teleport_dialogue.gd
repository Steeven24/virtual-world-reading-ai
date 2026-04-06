extends Node2D

#@export var next_scene_path: String
var player_in_range = false
@export_file("*.tscn") var target_scene_path: String
#@export var target_scene: PackedScene

func _ready():
	$Area2D/message.visible = false
	# Conectamos desde el nodo que tiene la señal ($Area2D)
	$Area2D.body_entered.connect(_on_body_entered)
	$Area2D.body_exited.connect(_on_body_exited)
	$Area2D/confirm.confirmed.connect(_on_dialog_confirmed)

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
	$Area2D/confirm.visible = true
	print("¡Hola! Este es un diálogo.")

#func change_scene():
	#get_tree().change_scene_to_file(next_scene_path)
#
#func _on_dialog_confirmed():
	#if next_scene_path != "":
		#get_tree().change_scene_to_file(next_scene_path)
	#else:
		#print("Error: No has asignado una ruta de escena en el inspector.")

func change_scene():
	SceneManager.transition_to(target_scene_path)
	#get_tree().change_scene_to_packed(target_scene)

func _on_dialog_confirmed():
	#if target_scene != null:
		change_scene()
		#get_tree().change_scene_to_packed(target_scene)
	#else:
		#print("Error: No has asignado una ruta de escena en el inspector.")
		
#func cambiar_Escena():
	#if target_scene != null:
		#get_tree().change_scene_to_packed(target_scene)
	#else:
		#print("No hay una escena seleccionada")
		
		
		
		
