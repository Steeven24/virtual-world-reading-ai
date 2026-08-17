# SceneManager.gd (Configurado en Project Settings -> Autoload)
extends Node

var is_ui_open: bool = false
var emoji_font: Font = null

func _enter_tree() -> void:
	_setup_emoji_fallbacks()

func _ready() -> void:
	_setup_emoji_fallbacks()

func get_emoji_font() -> Font:
	if emoji_font:
		return emoji_font
	if ResourceLoader.exists("res://fonts/NotoColorEmoji.ttf"):
		emoji_font = load("res://fonts/NotoColorEmoji.ttf")
	elif ResourceLoader.exists("res://fonts/NotoEmoji.ttf"):
		emoji_font = load("res://fonts/NotoEmoji.ttf")
	return emoji_font

func ensure_fallbacks(font: Font) -> void:
	if not font or not (font is FontFile):
		return
	var notof := get_emoji_font()
	if notof and not notof in font.fallbacks:
		font.fallbacks.append(notof)

func _setup_emoji_fallbacks() -> void:
	var notof := get_emoji_font()
	if not notof:
		return

	# 1. Asegurar fallback en la fuente por defecto del tema global
	var sample_lbl := Label.new()
	var default_theme_font := sample_lbl.get_theme_font("font")
	if default_theme_font and default_theme_font is FontFile:
		ensure_fallbacks(default_theme_font)
	sample_lbl.free()

	# 2. Asegurar fallback en ThemeDB
	if ThemeDB.fallback_font and ThemeDB.fallback_font is FontFile:
		ensure_fallbacks(ThemeDB.fallback_font)

	# 3. Asegurar fallback en todas las fuentes cargadas del proyecto
	var target_font_paths = [
		"res://fonts/PixelifySans-SemiBold.ttf",
		"res://fonts/PixelifySans-VariableFont_wght.ttf"
	]
	for fp in target_font_paths:
		if ResourceLoader.exists(fp):
			var f = load(fp)
			if f is FontFile:
				ensure_fallbacks(f)
				if fp == "res://fonts/PixelifySans-SemiBold.ttf":
					ThemeDB.fallback_font = f

func transition_to(scene_path: String):
	# Aquí podrías añadir una animación de fade out más adelante
	get_tree().change_scene_to_file(scene_path)
