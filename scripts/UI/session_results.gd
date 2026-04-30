## Pantalla de resultados al completar los 3 niveles de una sesión.
## Muestra un resumen de aciertos/errores por nivel, puntaje total,
## indicador de nuevo récord, y opciones para mejorar o volver al lobby.
extends Control

# ─── Constantes ──────────────────────────────────────────────────────────────

const FONT_PATH := "res://fonts/PixelifySans-SemiBold.ttf"
const FONT_REGULAR_PATH := "res://fonts/PixelifySans-VariableFont_wght.ttf"

const COLOR_CORRECT := Color(0.1, 0.6, 0.25, 1.0)
const COLOR_INCORRECT := Color(0.7, 0.15, 0.15, 1.0)
const COLOR_GOLD := Color(0.85, 0.75, 0.3, 1.0)
const COLOR_WHITE := Color(0.9, 0.92, 0.95, 1.0)
const COLOR_DIM := Color(0.6, 0.6, 0.7, 1.0)

const LEVELS: Array[String] = ["Literal", "Inferencial", "Critico"]

# ─── Nodos ───────────────────────────────────────────────────────────────────

var _font_bold: Font = null
var _font_regular: Font = null

# ─── Ciclo de vida ───────────────────────────────────────────────────────────

func _ready() -> void:
	_font_bold = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_font_regular = load(FONT_REGULAR_PATH) if ResourceLoader.exists(FONT_REGULAR_PATH) else null
	_build_ui()


func _build_ui() -> void:
	# Fondo oscuro
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Contenedor central
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_panel := PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(700, 500)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.15, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.85, 0.75, 0.3, 0.5)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.content_margin_left = 40
	panel_style.content_margin_right = 40
	panel_style.content_margin_top = 30
	panel_style.content_margin_bottom = 30
	main_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(main_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	main_panel.add_child(vbox)

	# ── Título ──
	var title := _create_label("📋 Resultados de la sesión", 28, COLOR_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# ── Info lectura ──
	var reading_title: String = str(GameSession.current_reading.get("title", "Lectura"))
	var typology: String = GameSession.current_typology
	var info := _create_label("\"%s\" — %s" % [reading_title, typology], 16, COLOR_DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)

	# ── Separador ──
	vbox.add_child(HSeparator.new())

	# ── Tabla de resultados por nivel ──
	var summary := GameSession.get_results_summary()
	var details: Array = summary.get("details", [])

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 10)

	# Headers
	grid.add_child(_create_label("Nivel", 16, COLOR_DIM))
	grid.add_child(_create_label("✓ Correctas", 16, COLOR_DIM))
	grid.add_child(_create_label("✗ Incorrectas", 16, COLOR_DIM))
	grid.add_child(_create_label("Puntos", 16, COLOR_DIM))

	for level in LEVELS:
		var level_results: Array = details.filter(func(r): return r.get("level", "") == level)
		var correct_count: int = level_results.filter(func(r): return r.get("correct", false)).size()
		var incorrect_count: int = level_results.size() - correct_count

		# Calcular puntos de este nivel
		var pts_correct: int = correct_count * GameSession.POINTS_BY_LEVEL.get(level, 10)
		var pts_penalty: int = incorrect_count * GameSession.PENALTY_BY_LEVEL.get(level, 5)
		var level_bonus: int = GameSession.LEVEL_PERFECT_BONUS if incorrect_count == 0 else 0
		var level_pts: int = pts_correct - pts_penalty + level_bonus

		grid.add_child(_create_label(level, 18, COLOR_WHITE))
		grid.add_child(_create_label(str(correct_count), 18, COLOR_CORRECT))
		grid.add_child(_create_label(str(incorrect_count), 18, COLOR_INCORRECT if incorrect_count > 0 else COLOR_DIM))
		grid.add_child(_create_label("%d pts" % level_pts, 18, COLOR_GOLD))

	vbox.add_child(grid)

	# ── Separador ──
	vbox.add_child(HSeparator.new())

	# ── Puntaje de sesión ──
	var session_score: int = GameSession.get_session_score()
	var score_label := _create_label("⭐ Puntaje de sesión: %d pts" % session_score, 24, COLOR_GOLD)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(score_label)

	# ── Nuevo récord ──
	if GameSession.is_new_record():
		var record_label := _create_label("🎉 ¡Nuevo récord para %s!" % typology, 20, Color(1.0, 0.85, 0.3, 1.0))
		record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(record_label)

		# Animación de pulso
		var tween := create_tween().set_loops()
		tween.tween_property(record_label, "modulate:a", 0.5, 0.6)
		tween.tween_property(record_label, "modulate:a", 1.0, 0.6)
	else:
		var best: int = GameSession.get_best_score(typology)
		if best > 0:
			var best_label := _create_label("Mejor puntaje: %d pts" % best, 16, COLOR_DIM)
			best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(best_label)

	# ── Estadísticas resumen ──
	var total_correct: int = summary.get("correct", 0)
	var total_q: int = summary.get("total", 0)
	var percent: float = summary.get("score_percent", 0.0)
	var stats := _create_label("Respuestas: %d/%d correctas (%.0f%%)" % [total_correct, total_q, percent], 16, COLOR_DIM)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)

	# ── Puntaje total global ──
	var total_global: int = GameSession.get_total_score()
	var global_label := _create_label("Puntaje total acumulado: %d pts" % total_global, 16, COLOR_DIM)
	global_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(global_label)

	# ── Botones ──
	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_container)

	var retry_btn := _create_button("🔄 Intentar con otra lectura", Color(0.15, 0.45, 0.2, 1.0))
	retry_btn.pressed.connect(_on_retry_pressed)
	btn_container.add_child(retry_btn)

	var lobby_btn := _create_button("🏠 Volver al Lobby", Color(0.2, 0.2, 0.35, 1.0))
	lobby_btn.pressed.connect(_on_lobby_pressed)
	btn_container.add_child(lobby_btn)

	# ── Animación de entrada ──
	main_panel.modulate.a = 0.0
	main_panel.scale = Vector2(0.9, 0.9)
	main_panel.pivot_offset = main_panel.custom_minimum_size / 2.0
	var entry_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	entry_tween.set_parallel(true)
	entry_tween.tween_property(main_panel, "modulate:a", 1.0, 0.5)
	entry_tween.tween_property(main_panel, "scale", Vector2.ONE, 0.5)


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _create_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if _font_bold:
		label.add_theme_font_override("font", _font_bold)
	return label


func _create_button(text: String, bg_color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 50)

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

	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 18)
	if _font_bold:
		button.add_theme_font_override("font", _font_bold)

	return button


# ─── Navegación ──────────────────────────────────────────────────────────────

func _on_retry_pressed() -> void:
	# GameSession solicita una nueva lectura de la misma tipología
	GameSession.retry_with_new_reading()
	# Ir al level 1 (lectura) — usar la escena registrada
	var level1: String = GameSession.level_scenes.get("Literal", "")
	if level1.is_empty():
		# Fallback: ir directamente al quiz
		SceneManager.transition_to(GameSession.QUIZ_SCENE)
	else:
		SceneManager.transition_to(level1)


func _on_lobby_pressed() -> void:
	var lobby: String = GameSession.lobby_scene
	if lobby.is_empty():
		push_error("[SessionResults] No hay escena de lobby configurada")
		return
	SceneManager.transition_to(lobby)
