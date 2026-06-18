extends Node2D

@export_enum("default", "front", "sit", "izquierda", "derecha") var character_pose: String = "sit"

var player_in_range = false

var consejos = [
	"Siempre lee el título antes de empezar, te dará una gran pista sobre el texto.",
	"Si encuentras una palabra que no conoces, intenta deducir su significado por el contexto.",
	"Hacer pausas breves al terminar un párrafo te ayuda a procesar lo que acabas de leer.",
	"Subraya mentalmente las ideas principales, ¡son el esqueleto de la historia!",
	"Pregúntate constantemente: ¿Qué me quiere enseñar este texto?",
	"Visualiza la historia en tu mente como si fuera una película mientras avanzas.",
	"Al terminar, intenta explicar lo que leíste con tus propias palabras.",
	"Si te sientes perdido en un párrafo, no dudes en volver atrás y reelerlo.",
	"Relaciona lo que estás leyendo con algo que ya conozcas o hayas vivido.",
	"Elimina las distracciones a tu alrededor para que tu mente pueda enfocarse al 100%.",
	"Usa un resaltador para marcar las frases clave que resumen el mensaje del autor.",
	"Toma notas al margen del texto para anotar tus propias dudas o reflexiones.",
	"Subraya las palabras clave o datos importantes para localizarlos rápidamente después.",
]

func _ready():
	visibility_changed.connect(_on_visibility_changed)

	# Configurar pose inicial
	if has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.play(character_pose)
		
	# Ocultar globo de interacción al inicio
	if has_node("Speech bubble"):
		$"Speech bubble".visible = false
		
	# Conectar señales del Area2D
	if has_node("Area2D"):
		$Area2D.body_entered.connect(_on_body_entered)
		$Area2D.body_exited.connect(_on_body_exited)
		
	# Alinear colisiones al estado inicial
	_on_visibility_changed()

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		if has_node("Speech bubble"):
			$"Speech bubble".visible = true

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		if has_node("Speech bubble"):
			$"Speech bubble".visible = false

func _process(_delta):
	# Si está en rango y presiona E (ui_accept)
	if player_in_range and Input.is_action_just_pressed("ui_accept"):
		if not SceneManager.is_ui_open:
			show_dialogue()

func show_dialogue():
	if not has_node("AcceptDialog"):
		push_warning("WiseOldMan: El nodo AcceptDialog no se encuentra.")
		return
		
	var dialog = $AcceptDialog
	
	# Seleccionar consejo aleatorio
	var tip = consejos.pick_random()
	
	# Añadir recomendación del robot
	var full_message = tip + "\n\nSi tienes una duda más específica, ¡pregúntale al robot asistente!"
	
	dialog.dialog_text = full_message
	
	SceneManager.is_ui_open = true
	
	# Mostrar diálogo en el centro
	dialog.popup_centered()

	# Conectar señal de cerrado para restaurar el estado
	if not dialog.confirmed.is_connected(_on_dialog_closed):
		dialog.confirmed.connect(_on_dialog_closed)
	if not dialog.canceled.is_connected(_on_dialog_closed):
		dialog.canceled.connect(_on_dialog_closed)

func _on_dialog_closed():
	SceneManager.is_ui_open = false

func _on_visibility_changed():
	if not visible:
		player_in_range = false
		if has_node("Speech bubble"):
			$"Speech bubble".visible = false
	_set_collision_shapes_disabled(self, not visible)

func _set_collision_shapes_disabled(node: Node, should_disable: bool):
	if node is CollisionShape2D:
		node.set_deferred("disabled", should_disable)
	for child in node.get_children():
		_set_collision_shapes_disabled(child, should_disable)
