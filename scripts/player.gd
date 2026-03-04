extends CharacterBody2D

@export var speed: float = 200.0
@onready var anim = $AnimatedSprite2D
@onready var interaction_area = $InteractionArea

var last_direction = "down"
var current_interactable = null

func _physics_process(delta):
	var direction = Vector2.ZERO
	
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if Input.is_action_just_pressed("interact") and current_interactable:
		current_interactable.interact()
	
	direction = direction.normalized()
	velocity = direction * speed
	move_and_slide()

	update_animation(direction)

func update_animation(direction):
	if direction == Vector2.ZERO:
		anim.play("idle_" + last_direction)
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
	
	anim.play("walk_" + last_direction)
	update_interaction_position()

func update_interaction_position():
	match last_direction:
		"up":
			interaction_area.position = Vector2(0, -20)
		"down":
			interaction_area.position = Vector2(0, 20)
		"left":
			interaction_area.position = Vector2(-20, 0)
		"right":
			interaction_area.position = Vector2(20, 0)


func _on_interaction_area_area_entered(area: Area2D) -> void:
	if area.has_method("interact"):
		current_interactable = area

func _on_interaction_area_area_exited(area):
	if area == current_interactable:
		current_interactable = null
