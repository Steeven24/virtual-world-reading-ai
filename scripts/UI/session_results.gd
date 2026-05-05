## Pantalla de resultados al completar los 3 niveles de una sesión.
## Muestra un resumen de aciertos/errores por nivel, puntaje total,
## indicador de nuevo récord, y opciones para mejorar o volver al lobby.
extends Control

# ─── Constantes ──────────────────────────────────────────────────────────────

const FONT_PATH := "res://fonts/PixelifySans-SemiBold.ttf"

const COLOR_CORRECT := Color(0.1, 0.6, 0.25, 1.0)
const COLOR_INCORRECT := Color(0.7, 0.15, 0.15, 1.0)
const COLOR_GOLD := Color(0.85, 0.75, 0.3, 1.0)
const COLOR_WHITE := Color(0.9, 0.92, 0.95, 1.0)
const COLOR_DIM := Color(0.6, 0.6, 0.7, 1.0)

const LEVELS: Array[String] = ["Literal", "Inferencial", "Critico"]

# ─── Nodos referenciados ─────────────────────────────────────────────────────

@onready var main_panel: PanelContainer = %MainPanel
@onready var title_label: Label = %TitleLabel
@onready var info_label: Label = %InfoLabel
@onready var results_grid: GridContainer = %ResultsGrid
@onready var session_score_label: Label = %SessionScoreLabel
@onready var record_label: Label = %RecordLabel
@onready var best_score_label: Label = %BestScoreLabel
@onready var stats_label: Label = %StatsLabel
@onready var global_score_label: Label = %GlobalScoreLabel
@onready var retry_button: Button = %RetryButton
@onready var lobby_button: Button = %LobbyButton
@onready var assistant_tip_dialog: AcceptDialog = %AssistantTipDialog
@onready var tip_label: Label = %TipLabel
@onready var assistant_sprite: Sprite2D = %AssistantSprite

var _font_bold: Font = null

# ─── Ciclo de vida ───────────────────────────────────────────────────────────

func _ready() -> void:
	_font_bold = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_apply_panel_style()
	_apply_button_styles()
	_populate_data()
	_animate_entry()


# ─── Estilo del panel principal ──────────────────────────────────────────────

func _apply_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.85, 0.75, 0.3, 0.5)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	main_panel.add_theme_stylebox_override("panel", style)


func _apply_button_styles() -> void:
	_style_button(retry_button, Color(0.15, 0.45, 0.2, 1.0))
	_style_button(lobby_button, Color(0.2, 0.2, 0.35, 1.0))


func _style_button(button: Button, bg_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = bg_color.lightened(0.15)
	button.add_theme_stylebox_override("hover", hover)


# ─── Poblar datos ────────────────────────────────────────────────────────────

func _populate_data() -> void:
	# Info de la lectura
	var reading_title: String = str(GameSession.current_reading.get("title", "Lectura"))
	var typology: String = GameSession.current_typology
	info_label.text = "\"%s\" — %s" % [reading_title, typology]

	# Tabla de resultados por nivel
	var summary := GameSession.get_results_summary()
	var details: Array = summary.get("details", [])
	_populate_grid(details)

	# Puntaje de sesión
	var session_score: int = GameSession.get_session_score()
	session_score_label.text = "⭐ Puntaje de sesión: %d pts" % session_score

	# Nuevo récord o mejor puntaje
	if GameSession.is_new_record():
		record_label.text = "🎉 ¡Nuevo récord para %s!" % typology
		record_label.visible = true
		best_score_label.visible = false
		# Animación de pulso
		var tween := create_tween().set_loops()
		tween.tween_property(record_label, "modulate:a", 0.5, 0.6)
		tween.tween_property(record_label, "modulate:a", 1.0, 0.6)
	else:
		record_label.visible = false
		var best: int = GameSession.get_best_score(typology)
		if best > 0:
			best_score_label.text = "Mejor puntaje: %d pts" % best
			best_score_label.visible = true
		else:
			best_score_label.visible = false

	# Estadísticas resumen
	var total_correct: int = summary.get("correct", 0)
	var total_q: int = summary.get("total", 0)
	var percent: float = summary.get("score_percent", 0.0)
	stats_label.text = "Respuestas: %d/%d correctas (%.0f%%)" % [total_correct, total_q, percent]

	# Puntaje total global
	var total_global: int = GameSession.get_total_score()
	global_score_label.text = "Puntaje total acumulado: %d pts" % total_global

	# Recomendación del asistente si no usó herramientas
	_check_tools_usage()


func _populate_grid(details: Array) -> void:
	for level in LEVELS:
		var level_results: Array = details.filter(func(r): return r.get("level", "") == level)
		var correct_count: int = level_results.filter(func(r): return r.get("correct", false)).size()
		var incorrect_count: int = level_results.size() - correct_count

		# Calcular puntos de este nivel
		var pts_correct: int = correct_count * GameSession.POINTS_BY_LEVEL.get(level, 10)
		var pts_penalty: int = incorrect_count * GameSession.PENALTY_BY_LEVEL.get(level, 5)
		var level_bonus: int = GameSession.LEVEL_PERFECT_BONUS if incorrect_count == 0 else 0
		var level_pts: int = pts_correct - pts_penalty + level_bonus

		results_grid.add_child(_create_label(level, 18, COLOR_WHITE))
		results_grid.add_child(_create_label(str(correct_count), 18, COLOR_CORRECT))
		results_grid.add_child(_create_label(str(incorrect_count), 18, COLOR_INCORRECT if incorrect_count > 0 else COLOR_DIM))
		results_grid.add_child(_create_label("%d pts" % level_pts, 18, COLOR_GOLD))


func _check_tools_usage() -> void:
	var tools := GameSession.tools_used
	var used_highlight: bool = tools.get("highlight", false)
	var used_underline: bool = tools.get("underline", false)
	var used_notes: bool = tools.get("notes", false)

	if not used_highlight or not used_underline or not used_notes:
		var missing_tools: Array[String] = []
		if not used_highlight:
			missing_tools.append("resaltar el texto")
		if not used_underline:
			missing_tools.append("subrayar el texto")
		if not used_notes:
			missing_tools.append("tomar notas")
		_show_assistant_tip(missing_tools)


# ─── Animación de entrada ────────────────────────────────────────────────────

func _animate_entry() -> void:
	main_panel.modulate.a = 0.0
	main_panel.scale = Vector2(0.9, 0.9)
	main_panel.pivot_offset = main_panel.custom_minimum_size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(main_panel, "modulate:a", 1.0, 0.5)
	tween.tween_property(main_panel, "scale", Vector2.ONE, 0.5)


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _create_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if _font_bold:
		label.add_theme_font_override("font", _font_bold)
	return label


# ─── Diálogo de recomendación del asistente ──────────────────────────────────

func _show_assistant_tip(missing_tools: Array[String]) -> void:
	# Esperar a que la animación de entrada termine
	await get_tree().create_timer(1.0).timeout

	# Construir la lista de herramientas gramaticalmente correcta (item1, item2 y item3)
	var tools_text := ""
	if missing_tools.size() == 1:
		tools_text = missing_tools[0]
	elif missing_tools.size() == 2:
		tools_text = missing_tools[0] + " y " + missing_tools[1]
	else:
		var last_item = missing_tools.pop_back()
		tools_text = ", ".join(missing_tools) + " y " + last_item

	tip_label.text = "¡Te recomiendo usar las herramientas del libro! Intenta %s en tu próxima lectura para mejorar tu comprensión y obtener mejores resultados." % tools_text

	# Iniciar animación del asistente (Removido porque ahora es un Sprite estático)
	# if assistant_sprite:
	# 	assistant_sprite.play("default")       

	var dialog := assistant_tip_dialog

	# Posicionar y animar como los otros diálogos
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	dialog.position = Vector2i(-10000, -10000)
	dialog.show()

	await get_tree().process_frame
	dialog.reset_size()
	dialog.min_size = Vector2i(800, 225)

	var screen_size := get_viewport().get_visible_rect().size
	var final_x: int = int((screen_size.x - dialog.size.x) / 2)
	var final_y: int = int(screen_size.y - dialog.size.y - 40)

	var offset_y: int = 30
	dialog.position = Vector2i(final_x, final_y + offset_y)

	for child in dialog.get_children():
		if child is Control:
			child.modulate.a = 0.0

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_method(func(y): dialog.position = Vector2i(final_x, y), final_y + offset_y, final_y, 0.3)

	for child in dialog.get_children():
		if child is Control:
			tween.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(0.05)


# ─── Navegación ──────────────────────────────────────────────────────────────

func _on_retry_pressed() -> void:
	GameSession.retry_with_new_reading()
	var level1: String = GameSession.level_scenes.get("Literal", "")
	if level1.is_empty():
		SceneManager.transition_to(GameSession.QUIZ_SCENE)
	else:
		SceneManager.transition_to(level1)


func _on_lobby_pressed() -> void:
	var lobby: String = GameSession.lobby_scene
	if lobby.is_empty():
		push_error("[SessionResults] No hay escena de lobby configurada")
		return
	SceneManager.transition_to(lobby)
