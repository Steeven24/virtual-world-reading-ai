extends Area2D

var player_in_range = false

func _ready():
	$message.visible = false
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		$message.visible = true
		$"../../Speech bubble".visible = true

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		$message.visible = false
		$"../../Speech bubble".visible = false

func _process(delta):
	if player_in_range and Input.is_action_just_pressed("ui_accept"):
		mostrar_dialogo()

func mostrar_dialogo():
	$confirm.visible = true
	print("¡Hola! Este es un diálogo.")
