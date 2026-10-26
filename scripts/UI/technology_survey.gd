## Formulario obligatorio SUS (10 × 1-5) + TAM (12 × 1-7).
## Evalúa el mundo virtual completo, no la zona de cómics.
extends CanvasLayer

signal cerrado
signal completada

const PAGINAS := [
	{
		"title": "Usabilidad (SUS) · 1 de 2",
		"help": "Indica cuánto estás de acuerdo. 1 = totalmente en desacuerdo · 5 = totalmente de acuerdo.",
		"scale": 5,
		"items": [
			["sus_1", "Creo que me gustaría usar este mundo virtual frecuentemente."],
			["sus_2", "Me ha parecido innecesariamente complejo este mundo virtual."],
			["sus_3", "El mundo virtual me ha parecido fácil de usar."],
			["sus_4", "Creo que necesitaría ayuda de una persona con conocimientos técnicos para usar este mundo virtual."],
			["sus_5", "Las distintas funciones de este mundo virtual me han parecido bien integradas."],
		],
	},
	{
		"title": "Usabilidad (SUS) · 2 de 2",
		"help": "Responde según tu experiencia completa en el mundo virtual.",
		"scale": 5,
		"items": [
			["sus_6", "Creo que el mundo virtual es demasiado inconsistente."],
			["sus_7", "Imagino que la mayoría de las personas aprendería a usar este mundo virtual muy rápidamente."],
			["sus_8", "El mundo virtual me ha parecido engorroso de usar."],
			["sus_9", "Me sentí con confianza al usar este mundo virtual."],
			["sus_10", "Tuve que aprender muchas cosas antes de poder usar este mundo virtual."],
		],
	},
	{
		"title": "Utilidad percibida (TAM)",
		"help": "1 = totalmente en desacuerdo · 7 = totalmente de acuerdo.",
		"scale": 7,
		"items": [
			["tam_pu_1", "El mundo virtual me permitió completar más rápidamente las actividades de comprensión lectora."],
			["tam_pu_2", "Usar el mundo virtual mejoró mi desempeño en comprensión lectora."],
			["tam_pu_3", "Usar el mundo virtual aumentó mi productividad en las actividades de lectura."],
			["tam_pu_4", "Usar el mundo virtual aumentó mi eficacia en las actividades de comprensión lectora."],
			["tam_pu_5", "El mundo virtual hizo más fáciles las actividades de comprensión lectora."],
			["tam_pu_6", "El mundo virtual me resultó útil para aprender y practicar comprensión lectora."],
		],
	},
	{
		"title": "Facilidad de uso percibida (TAM)",
		"help": "Última sección · 1 = totalmente en desacuerdo · 7 = totalmente de acuerdo.",
		"scale": 7,
		"items": [
			["tam_peou_1", "Aprender a utilizar el mundo virtual me resultó fácil."],
			["tam_peou_2", "Me resultó fácil hacer que el mundo virtual respondiera como yo quería."],
			["tam_peou_3", "Mi interacción con el mundo virtual fue clara y comprensible."],
			["tam_peou_4", "El mundo virtual me pareció flexible al interactuar con él."],
			["tam_peou_5", "Me resultó fácil adquirir habilidad para usar el mundo virtual."],
			["tam_peou_6", "El mundo virtual me pareció fácil de usar."],
		],
	},
]

var _page := 0
var _answers := {}
var _groups: Array[ButtonGroup] = []
var _submitting := false

@onready var _title: Label = %SectionTitle
@onready var _help: Label = %ScaleHelp
@onready var _questions: VBoxContainer = %Questions
@onready var _progress: Label = %Progress
@onready var _error: Label = %Error
@onready var _previous: Button = %Previous
@onready var _next: Button = %Next
@onready var _close: Button = %Close


func _ready() -> void:
	_previous.pressed.connect(_go_previous)
	_next.pressed.connect(_go_next)
	_close.pressed.connect(_try_close)
	SurveyManager.submission_finished.connect(_on_submission_finished)
	_render_page()


func _exit_tree() -> void:
	if SurveyManager.submission_finished.is_connected(_on_submission_finished):
		SurveyManager.submission_finished.disconnect(_on_submission_finished)


func _render_page() -> void:
	for child in _questions.get_children():
		child.queue_free()
	_groups.clear()
	var data: Dictionary = PAGINAS[_page]
	_title.text = data["title"]
	_help.text = data["help"]
	_progress.text = "Paso %d de %d" % [_page + 1, PAGINAS.size()]
	_previous.visible = _page > 0
	_next.text = "Enviar y desbloquear" if _page == PAGINAS.size() - 1 else "Siguiente"
	_error.text = ""
	for item in data["items"]:
		_questions.add_child(_build_question(str(item[0]), str(item[1]), int(data["scale"])))


func _build_question(key: String, text: String, scale: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	box.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	_groups.append(group)
	for value in range(1, scale + 1):
		var button := Button.new()
		button.text = str(value)
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(54, 38)
		button.focus_mode = Control.FOCUS_NONE
		button.set_meta("value", value)
		button.set_meta("key", key)
		button.button_pressed = int(_answers.get(key, 0)) == value
		button.pressed.connect(_select_answer.bind(key, value))
		row.add_child(button)
	box.add_child(row)
	var separator := HSeparator.new()
	box.add_child(separator)
	return box


func _select_answer(key: String, value: int) -> void:
	_answers[key] = value


func _current_page_complete() -> bool:
	for item in PAGINAS[_page]["items"]:
		if int(_answers.get(str(item[0]), 0)) == 0:
			return false
	return true


func _go_previous() -> void:
	if _submitting or _page == 0:
		return
	_page -= 1
	_render_page()


func _go_next() -> void:
	if _submitting:
		return
	if not _current_page_complete():
		_error.text = "Responde todas las afirmaciones de esta sección para continuar."
		return
	if _page < PAGINAS.size() - 1:
		_page += 1
		_render_page()
		return
	_submit()


func _submit() -> void:
	_submitting = true
	_set_buttons_disabled(true)
	_error.text = "Guardando tus respuestas…"
	SurveyManager.submit(
		_collect("sus", 10),
		_collect("tam_pu", 6),
		_collect("tam_peou", 6),
	)


func _collect(prefix: String, count: int) -> Array:
	var values := []
	for i in range(1, count + 1):
		values.append(int(_answers.get("%s_%d" % [prefix, i], 0)))
	return values


func _set_buttons_disabled(disabled: bool) -> void:
	_previous.disabled = disabled
	_next.disabled = disabled
	_close.disabled = disabled
	for group in _groups:
		for button in group.get_buttons():
			button.disabled = disabled


func _on_submission_finished(success: bool, error: String) -> void:
	_submitting = false
	if success:
		completada.emit()
		return
	_set_buttons_disabled(false)
	_error.text = error


func _try_close() -> void:
	if not _submitting:
		cerrado.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _submitting:
		cerrado.emit()
		get_viewport().set_input_as_handled()


func answer_count() -> int:
	return _answers.size()


func current_page() -> int:
	return _page
