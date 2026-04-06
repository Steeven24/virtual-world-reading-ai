# SceneManager.gd (Configurado en Project Settings -> Autoload)
extends Node

func transition_to(scene_path: String):
	# Aquí podrías añadir una animación de fade out más adelante
	get_tree().change_scene_to_file(scene_path)
