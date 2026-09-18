extends CharacterBody2D


#@export var speed: float = 800.0
## Múltiplo de los 60 tics de física: 3 px por tic, sin resto fraccionario.
@export var speed: float = 180.0

## Velocidad al correr (Shift). El mundo es pequeño y andar de punta a punta se
## hacía lento, sobre todo al volver al lobby.
@export var run_speed: float = 360.0

@onready var anim = $AnimatedSprite2D
@onready var camera = $Camera2D

var last_direction = "down"

## True mientras el jugador mantiene Shift y se está moviendo.
var is_running = false

## Distancia de la cámara al jugador, leída de la escena al arrancar.
var _desfase_camara: Vector2 = Vector2.ZERO

func _ready():
	_anclar_camara()
	setup_camera_limits()


## La cámara deja de colgar del jugador y pasa a colocarse a mano en píxeles
## enteros. Con el suavizado de Godot la cámara se quedaba en posiciones
## fraccionarias, y al redondear cada elemento por separado el personaje
## bailaba dentro de la pantalla mientras la vista se desplazaba.
func _anclar_camara() -> void:
	_desfase_camara = camera.global_position - global_position
	camera.position_smoothing_enabled = false
	camera.top_level = true
	_colocar_camara()


func _colocar_camara() -> void:
	camera.global_position = (global_position + _desfase_camara).round()


## Se recoloca cada fotograma dibujado, no solo en cada paso de física, para
## que la vista acompañe al jugador en pantallas de más de 60 Hz.
func _process(_delta):
	_colocar_camara()

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
	# Correr solo cuenta si de verdad hay movimiento: con Shift quieto se sigue
	# usando la animación de reposo.
	is_running = direction != Vector2.ZERO and not SceneManager.is_ui_open and Input.is_action_pressed("run")
	velocity = direction * (run_speed if is_running else speed)
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
	
	if is_running:
		anim.play(_animacion_movimiento("run"))
	else:
		anim.play(_animacion_movimiento("walk"))


## Devuelve la animación del prefijo pedido para la dirección y el personaje
## actuales. Si el personaje todavía no tiene las de correr, se usan las de
## andar en vez de dejar al jugador congelado.
func _animacion_movimiento(prefijo: String) -> String:
	var nombre = prefijo + "_" + last_direction + GameSession.anim_suffix
	var frames = anim.sprite_frames
	if frames and frames.has_animation(nombre) and frames.get_frame_count(nombre) > 0:
		return nombre
	return "walk_" + last_direction + GameSession.anim_suffix
