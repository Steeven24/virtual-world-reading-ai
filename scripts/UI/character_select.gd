extends Control

@onready var anim_male = %AnimMale
@onready var anim_female = %AnimFemale

const LOBBY_SCENE = "res://scenes/Scenery/Lobby/lobby.tscn"

func _ready():
	# Iniciar animaciones de preview
	anim_male.play("walk_down")
	anim_female.play("walk_down_women")
	
	# Asegurarnos de que el mouse sea visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_male_selected():
	GameSession.set_character("male")
	_start_game()

func _on_female_selected():
	GameSession.set_character("women")
	_start_game()

func _start_game():
	SceneManager.transition_to(LOBBY_SCENE)
