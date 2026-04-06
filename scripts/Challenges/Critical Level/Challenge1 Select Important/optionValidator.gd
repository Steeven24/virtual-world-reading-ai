extends Node2D

var respuesta_correcta = "riesgo"  # En este caso, casa del árbol implica riesgo
#@export var target_scene: PackedScene
#@export var next_scene : String
@export_file("*.tscn") var target_scene_path: String

func verificar_respuesta(tipo):
	if tipo == respuesta_correcta:
		acierto()
	else:
		error()

func acierto():
	$LabelMensaje.text = "¡Buena decisión!"
	print("Correcto")

	await get_tree().create_timer(2.0).timeout
	SceneManager.transition_to(target_scene_path)
	#get_tree().change_scene_to_packed(target_scene)

func error():
	$LabelMensaje.text = "Piénsalo mejor"
	print("Incorrecto")
