extends Area2D

@export var nombre_opcion = ""


func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			get_parent().verificar_respuesta(nombre_opcion)
			
			
			
			
