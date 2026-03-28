extends Node2D

var respuesta_correcta = "volcan"

func verificar_respuesta(opcion):
	if opcion == respuesta_correcta:
		acierto()
	else:
		error()
		
func acierto():
	$LabelMensaje.text = "¡Correcto!"
	print("Bien hecho")

	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/Section/Descriptivos/level 3.tscn")
	
func error():
	$LabelMensaje.text = "Intenta de nuevo"
	print("Incorrecto")
