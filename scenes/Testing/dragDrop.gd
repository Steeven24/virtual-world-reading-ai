extends Area2D



var dragging = false
var offset = Vector2.ZERO
var posicion_inicial
@export var slot_correcto: Area2D


func _ready():
	posicion_inicial = position

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				offset = position - get_global_mouse_position()
			else:
				dragging = false
				verificar_colision()

func _process(delta):
	if dragging:
		position = get_global_mouse_position() + offset
		
func verificar_colision():
	var areas = get_overlapping_areas()

	for area in areas:
		if area == slot_correcto:
			position = area.position
			print("Correcto!")
			return
	
	# Si no es correcto, regresa
	position = posicion_inicial
	print("Incorrecto")
