extends Node2D

func _ready():
	$Area2D.body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.name == "Player":
		LobbyReturnHandler.request_return()
