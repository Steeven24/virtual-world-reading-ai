extends Node2D

var respuesta_correcta = "riesgo"  # En este caso, casa del árbol implica riesgo

func verificar_respuesta(tipo):
	if tipo == respuesta_correcta:
		acierto()
	else:
		error()

func acierto():
	$LabelMensaje.text = "¡Buena decisión!"
	print("Correcto")

	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func error():
	$LabelMensaje.text = "Piénsalo mejor"
	print("Incorrecto")
