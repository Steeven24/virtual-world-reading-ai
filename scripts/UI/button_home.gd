extends Control

func _ready():
	$TextureButton.pressed.connect(_on_button_pressed)

func _on_button_pressed():
	LobbyReturnHandler.request_return()
