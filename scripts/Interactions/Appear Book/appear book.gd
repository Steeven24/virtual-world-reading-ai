extends Node2D

@export var libro: CanvasLayer
var player_in_range = false
var esta_leyendo = false

#func cambiar_Escena():
	#if target_scene != null:
		#get_tree().change_scene_to_packed(target_scene)
	#else:
		#print("No hay una escena seleccionada")

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
		if esta_leyendo == false:
			show_dialogue()
			

func show_dialogue():
	$Book/Area2D/confirm.visible = true
	print("¡Hola! Este es un diálogo.")


#func change_scene():
	#get_tree().change_scene_to_packed(target_scene)

func _on_dialog_confirmed():
	if libro != null: #and not esta_leyendo:
		libro.visible = true
		#esta_leyendo = true
		
	else:
		print("Error: No has asignado una ruta de escena en el inspector.")
		

		
		
		
		
		
