## Script genérico para el desafío de selección múltiple.
## Recibe los datos de la pregunta desde GameSession y puebla la UI dinámicamente.
##
## Se usa la MISMA escena para los 3 niveles (Literal, Inferencial, Crítico).
## La diferencia es solo el contenido de la pregunta y las opciones.
extends Control

# ─── Constantes ──────────────────────────────────────────────────────────────

## Colores para los botones de opciones.
const COLOR_NORMAL := Color(0.15, 0.15, 0.22, 1.0)
const COLOR_HOVER := Color(0.22, 0.22, 0.32, 1.0)
const COLOR_CORRECT := Color(0.1, 0.55, 0.2, 1.0)
const COLOR_INCORRECT := Color(0.65, 0.12, 0.12, 1.0)
const COLOR_DEBUG_HINT := Color(0.1, 0.45, 0.18, 0.3)
const COLOR_LETTER := Color(0.85, 0.75, 0.3, 1.0)

## Fuente del proyecto para aplicar a los botones generados dinámicamente.
const FONT_PATH := "res://fonts/PixelifySans-SemiBold.ttf"

# ─── Nodos referenciados ─────────────────────────────────────────────────────

@onready var level_badge: Label = %LevelBadge
@onready var debug_label: Label = %DebugLabel
@onready var question_label: RichTextLabel = %QuestionLabel
@onready var options_container: VBoxContainer = %OptionsContainer
@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var result_label: Label = %ResultLabel
@onready var justification_label: RichTextLabel = %JustificationLabel
@onready var assistant_sprite: AnimatedSprite2D = %AssistantSprite
@onready var continue_button: Button = %ContinueButton
@onready var restart_button: Button = %RestartButton
@onready var background: TextureRect = %Background

# ─── Estado interno ──────────────────────────────────────────────────────────

var _current_question: Dictionary = {}
var _answered: bool = false
var _was_correct: bool = false
var _font: Font = null

# ─── Ciclo de vida ───────────────────────────────────────────────────────────

func _ready() -> void:
	# Precargar la fuente del proyecto
	_font = load(FONT_PATH)

	feedback_panel.visible = false
	continue_button.visible = false
	restart_button.visible = false

	continue_button.pressed.connect(_on_continue_pressed)
	restart_button.pressed.connect(_on_restart_pressed)

	_load_question()


# ─── Carga de datos ──────────────────────────────────────────────────────────

func _load_question() -> void:
	_current_question = GameSession.get_current_question()

	if _current_question.is_empty():
		push_error("[ChallengeQuiz] No hay pregunta disponible")
		_show_error("No hay preguntas disponibles para este nivel.")
		return

	# Header
	var level_name: String = GameSession.get_current_level()
	var progress: String = GameSession.get_progress_text()
	level_badge.text = "Nivel %s • %s" % [level_name, progress]

	# Debug: mostrar respuesta correcta
	if GameSession.DEBUG_SHOW_ANSWER:
		var correct: String = str(_current_question.get("correct_answer", ""))
		debug_label.text = "🔑 DEBUG — Respuesta correcta: %s" % correct
		debug_label.visible = true
	else:
		debug_label.visible = false

	# Pregunta
	var q_text: String = str(_current_question.get("question_text", ""))
	question_label.text = "[color=white]%s[/color]" % q_text

	# Opciones
	_create_option_buttons()

	_answered = false


func _create_option_buttons() -> void:
	# Limpiar opciones anteriores
	for child in options_container.get_children():
		child.queue_free()

	var answers: Array = _current_question.get("answers", [])

	for answer in answers:
		var letter: String = str(answer.get("letter", ""))
		var text: String = str(answer.get("answer_text", ""))

		var button := Button.new()
		button.text = "  %s)  %s" % [letter, text]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 60)

		# Estilizar el botón
		var stylebox := StyleBoxFlat.new()
		stylebox.bg_color = COLOR_NORMAL
		stylebox.corner_radius_top_left = 8
		stylebox.corner_radius_top_right = 8
		stylebox.corner_radius_bottom_left = 8
		stylebox.corner_radius_bottom_right = 8
		stylebox.content_margin_left = 16
		stylebox.content_margin_right = 16
		stylebox.content_margin_top = 8
		stylebox.content_margin_bottom = 8

		button.add_theme_stylebox_override("normal", stylebox)

		var hover_style := stylebox.duplicate()
		hover_style.bg_color = COLOR_HOVER
		button.add_theme_stylebox_override("hover", hover_style)

		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_font_size_override("font_size", 18)
		if _font:
			button.add_theme_font_override("font", _font)

		# Debug: resaltar la respuesta correcta sutilmente
		if GameSession.DEBUG_SHOW_ANSWER:
			var correct_answer: String = str(_current_question.get("correct_answer", ""))
			if letter == correct_answer:
				var debug_style := stylebox.duplicate()
				debug_style.bg_color = COLOR_DEBUG_HINT
				debug_style.border_color = COLOR_CORRECT
				debug_style.border_width_left = 3
				debug_style.border_width_right = 3
				debug_style.border_width_top = 3
				debug_style.border_width_bottom = 3
				button.add_theme_stylebox_override("normal", debug_style)

		button.pressed.connect(_on_option_pressed.bind(letter))
		options_container.add_child(button)


# ─── Interacción ─────────────────────────────────────────────────────────────

func _on_option_pressed(letter: String) -> void:
	if _answered:
		return

	_answered = true

	# Validar respuesta
	var result: Dictionary = GameSession.submit_answer(letter)
	_was_correct = result.get("correct", false)
	var justification: String = str(result.get("justification", ""))
	var correct_letter: String = str(result.get("correct_answer", ""))
	var points: int = result.get("points_earned", 0)

	# Colorear los botones
	_highlight_answers(letter, correct_letter)

	# Mostrar feedback
	_show_feedback(_was_correct, justification, points)


func _highlight_answers(selected: String, correct: String) -> void:
	var idx := 0
	var answers: Array = _current_question.get("answers", [])

	for child in options_container.get_children():
		if child is Button and idx < answers.size():
			var letter: String = str(answers[idx].get("letter", ""))
			child.disabled = true

			var style := StyleBoxFlat.new()
			style.corner_radius_top_left = 8
			style.corner_radius_top_right = 8
			style.corner_radius_bottom_left = 8
			style.corner_radius_bottom_right = 8
			style.content_margin_left = 16
			style.content_margin_right = 16
			style.content_margin_top = 8
			style.content_margin_bottom = 8

			if letter == correct:
				style.bg_color = COLOR_CORRECT
				style.border_color = Color(0.2, 0.8, 0.3, 1.0)
				style.border_width_left = 2
				style.border_width_right = 2
				style.border_width_top = 2
				style.border_width_bottom = 2
			elif letter == selected and selected != correct:
				style.bg_color = COLOR_INCORRECT
				style.border_color = Color(0.9, 0.2, 0.2, 1.0)
				style.border_width_left = 2
				style.border_width_right = 2
				style.border_width_top = 2
				style.border_width_bottom = 2
			else:
				style.bg_color = Color(0.15, 0.15, 0.22, 0.5)

			child.add_theme_stylebox_override("normal", style)
			child.add_theme_stylebox_override("disabled", style)

		idx += 1


func _show_feedback(correct: bool, justification: String, points: int = 0) -> void:
	feedback_panel.visible = true

	if correct:
		result_label.text = "¡Correcto! +%d pts" % points
		result_label.add_theme_color_override("font_color", COLOR_CORRECT)
		continue_button.visible = true
		restart_button.visible = false
	else:
		result_label.text = "Incorrecto"
		result_label.add_theme_color_override("font_color", COLOR_INCORRECT)
		continue_button.visible = false
		restart_button.visible = true

	justification_label.bbcode_enabled = true
	justification_label.text = "[color=white]%s[/color]" % justification

	# Activar animación del asistente
	if assistant_sprite:
		assistant_sprite.play("default")

	# Animación de aparición
	feedback_panel.modulate.a = 0.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(feedback_panel, "modulate:a", 1.0, 0.4)


func _show_error(message: String) -> void:
	question_label.text = "[color=red][center]%s[/center][/color]" % message
	for child in options_container.get_children():
		child.queue_free()


# ─── Navegación ──────────────────────────────────────────────────────────────

func _on_continue_pressed() -> void:
	var next_scene: String = GameSession.advance_to_next()
	if next_scene.is_empty():
		# Fallback al lobby
		next_scene = GameSession.lobby_scene
	SceneManager.transition_to(next_scene)


func _on_restart_pressed() -> void:
	GameSession.restart_from_level1()
	var level1_scene: String = GameSession.get_level1_scene()
	if level1_scene.is_empty():
		# Fallback: recargar el quiz con las nuevas preguntas
		SceneManager.transition_to(GameSession.QUIZ_SCENE)
	else:
		SceneManager.transition_to(level1_scene)
