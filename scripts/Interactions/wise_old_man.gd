## El Sabio: da consejos de comprensión lectora.
##
## Su papel es enseñar técnicas que sirven para cualquier texto. No resuelve
## dudas concretas de la lectura (eso es del robot asistente) ni plantea
## desafíos (eso es del profesor).
##
## Los textos son planos a propósito: AcceptDialog.dialog_text no interpreta
## BBCode.
extends Node2D

@export_enum("default", "front", "sit", "izquierda", "derecha") var character_pose: String = "sit"

var player_in_range = false

## Presentación de la primera visita, para que quede claro qué hace el sabio
## y qué no.
const INTRO_MESSAGE := "Soy el sabio de esta sala. Te doy consejos para entender mejor lo que lees: técnicas que sirven para cualquier texto.\n\nNo resuelvo dudas concretas de tu lectura, para eso está el robot asistente. Y quien te pondrá a prueba con los desafíos es el profesor.\n\nHabla conmigo siempre que quieras: cada vez te daré un consejo distinto."

## Cierre que acompaña a cada consejo, para reforzar el reparto de papeles.
const CONSEJO_FOOTER := "Si tienes una duda más específica sobre esta lectura, ¡pregúntale al robot asistente!"

var consejos = [
	# ─── Antes y durante la lectura ───
	"Lee el título antes de empezar: te dará una gran pista sobre lo que vas a encontrar.",
	"Si encuentras una palabra que no conoces, intenta deducir su significado por el contexto antes de darte por vencido.",
	"Haz una pausa breve al terminar cada párrafo: le da tiempo a tu cabeza a asentar lo que acabas de leer.",
	"Si te sientes perdido en un párrafo, no dudes en volver atrás y releerlo. No es perder el tiempo, es ganarlo.",
	"Visualiza lo que lees en tu mente, como si fuera una película. Lo que se ve, se recuerda.",
	"Relaciona lo que lees con algo que ya conozcas o hayas vivido: así se te quedará mucho mejor.",
	"Elimina las distracciones a tu alrededor antes de empezar. Leer a medias es leer dos veces.",
	"Si la lectura se te hace larga, léela por partes y resume cada una en una frase antes de seguir.",

	# ─── Sacar partido a las herramientas del libro ───
	"Las ideas principales son el esqueleto del texto. Activa Subrayar y arrastra el ratón sobre ellas para no perderlas de vista.",
	"Marca con Resaltar las frases que resumen el mensaje del autor: son las que te dirán de qué iba todo.",
	"Subraya los nombres, las fechas y los datos concretos: son justo lo que te preguntará el desafío literal.",
	"Abre la pestaña Notas para escribir tus dudas y tus ideas. Cada página guarda las suyas, y el Compilatorio te las reúne todas.",

	# ─── Preparar los tres desafíos ───
	"Pregúntate mientras lees: ¿qué me quiere enseñar este texto? Esa respuesta te vale para los tres desafíos.",
	"Cuando el texto insinúa algo sin llegar a decirlo, eso es una inferencia. El profesor te preguntará justo por eso.",
	"Pregúntate si estás de acuerdo con el autor y por qué. Eso es exactamente lo que pide el nivel crítico.",
	"Antes de responder, relee la pregunta entera: muchos fallos vienen de contestar demasiado rápido.",
	"Al terminar, intenta explicar la lectura con tus propias palabras. Si puedes, la has entendido.",
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
	dialog.dialog_text = _build_message()
	
	SceneManager.is_ui_open = true
	
	# Mostrar diálogo en el centro
	dialog.popup_centered()

	# Conectar señal de cerrado para restaurar el estado
	if not dialog.confirmed.is_connected(_on_dialog_closed):
		dialog.confirmed.connect(_on_dialog_closed)
	if not dialog.canceled.is_connected(_on_dialog_closed):
		dialog.canceled.connect(_on_dialog_closed)

## En la primera visita el sabio se presenta; a partir de ahí, un consejo al azar.
func _build_message() -> String:
	if not GameSession.is_hint_seen(GameSession.HINT_INTRO_SAGE):
		GameSession.mark_hint_seen(GameSession.HINT_INTRO_SAGE)
		return INTRO_MESSAGE

	return consejos.pick_random() + "\n\n" + CONSEJO_FOOTER

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
