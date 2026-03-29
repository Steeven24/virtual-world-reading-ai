extends Node2D

@export var target_scene: PackedScene
@export var respuesta_correcta: String

func verificar_respuesta(opcion):
	if opcion == respuesta_correcta:
		acierto()
	else:
		error()
		
func acierto():
	$LabelMensaje.text = "¡Correcto!"
	print("Bien hecho")

	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_packed(target_scene)
	
func error():
	$LabelMensaje.text = "Intenta de nuevo"
	print("Incorrecto")
