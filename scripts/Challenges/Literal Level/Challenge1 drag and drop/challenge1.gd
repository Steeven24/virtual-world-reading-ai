extends Node2D

var contador = 0
#@export var next_scene_path: String
#@export var target_scene: PackedScene
@export_file("*.tscn") var target_scene_path: String

func change_scene():
	SceneManager.transition_to(target_scene_path)


func objeto_correcto():
	contador += 1
	print("Correctos: ", contador)

	if contador == 3:
		ganaste()
		
func ganaste():
	print("GANASTE 🎉")

	# Mostrar mensaje en pantalla (opcional)
	var label = Label.new()
	label.text = "¡Correcto!"
	label.position = Vector2(300, 200)
	add_child(label)

	# Esperar 2 segundos y cambiar escena
	await get_tree().create_timer(2.0).timeout
	SceneManager.transition_to(target_scene_path)
	#get_tree().change_scene_to_packed(target_scene)
	#get_tree().change_scene_to_file(next_scene_path)
