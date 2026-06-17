extends CharacterBody2D

#@export var speed: float = 800.0
@export var speed: float = 200.0
@onready var anim = $AnimatedSprite2D
@onready var camera = $Camera2D

var last_direction = "down"

func _ready():
	setup_camera_limits()

func setup_camera_limits():
	# Esperar un frame para asegurar que la escena esté lista
	await get_tree().process_frame
	
	var background = null
	# Buscar un nodo que contenga "Background" en su nombre en la escena actual
	var current_scene = get_tree().current_scene
	if not current_scene:
		return
		
	background = current_scene.find_child("*Background*", true, false)
	
	# Si no se encuentra, buscar un nodo llamado "Scenery" que podría contener el fondo (como en el Lobby)
	if not background:
		var scenery = current_scene.find_child("Scenery", true, false)
		if scenery:
			background = scenery.find_child("*Background*", true, false)

	if background:
		if background is Sprite2D:
			var rect = background.get_rect()
			var s = background.global_scale
			var pos = background.global_position
			
			# Ajustar si el sprite está centrado
			var offset = Vector2.ZERO
			if background.centered:
				offset = rect.position * s
			
			camera.limit_left = int(pos.x + offset.x)
			camera.limit_top = int(pos.y + offset.y)
			camera.limit_right = int(pos.x + offset.x + rect.size.x * s.x)
			camera.limit_bottom = int(pos.y + offset.y + rect.size.y * s.y)
		elif background is TileMap:
			var rect = background.get_used_rect()
			var cell_size = background.tile_set.tile_size
			var s = background.global_scale
			var pos = background.global_position
			
			camera.limit_left = int(pos.x + rect.position.x * cell_size.x * s.x)
			camera.limit_top = int(pos.y + rect.position.y * cell_size.y * s.y)
			camera.limit_right = int(pos.x + rect.end.x * cell_size.x * s.x)
			camera.limit_bottom = int(pos.y + rect.end.y * cell_size.y * s.y)
		elif background is TileMapLayer:
			var rect = background.get_used_rect()
			var cell_size = background.tile_set.tile_size
			var s = background.global_scale
			var pos = background.global_position
			
			camera.limit_left = int(pos.x + rect.position.x * cell_size.x * s.x)
			camera.limit_top = int(pos.y + rect.position.y * cell_size.y * s.y)
			camera.limit_right = int(pos.x + rect.end.x * cell_size.x * s.x)
			camera.limit_bottom = int(pos.y + rect.end.y * cell_size.y * s.y)

func _physics_process(delta):
	var direction = Vector2.ZERO
	
	if not SceneManager.is_ui_open:
		if Input.is_action_pressed("move_up"):
			direction.y -= 1
		if Input.is_action_pressed("move_down"):
			direction.y += 1
		if Input.is_action_pressed("move_left"):
			direction.x -= 1
		if Input.is_action_pressed("move_right"):
			direction.x += 1

	direction = direction.normalized()
	velocity = direction * speed
	move_and_slide()

	update_animation(direction)

func update_animation(direction):
	if direction == Vector2.ZERO:
		anim.play("idle_" + last_direction + GameSession.anim_suffix)
		return
	
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			last_direction = "right"
		else:
			last_direction = "left"
	else:
		if direction.y > 0:
			last_direction = "down"
		else:
			last_direction = "up"
	
	anim.play("walk_" + last_direction + GameSession.anim_suffix)
