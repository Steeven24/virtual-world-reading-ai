extends Node2D

## Robot Asistente — Chat IA interactivo para los level1.
## Se conecta al endpoint /npc/chat de LecturaIA a través del autoload NpcChatAPI.
## El jugador puede hacer preguntas sobre la lectura activa y recibir
## orientación socrática (pistas, no respuestas directas).

@export var prompt_sprite_resource: Texture2D
@export var dialog_theme: Theme

var player_in_range = false

@onready var prompt_bubble = $"Speech bubble" if has_node("Speech bubble") else null
@onready var area_2d = $Area2D if has_node("Area2D") else null

# ─── Nodos de la UI (creados por código) ────────────────────────────────────

var canvas_layer: CanvasLayer
var chat_display: RichTextLabel
var line_edit: LineEdit
var btn_enviar: Button
var btn_cerrar: Button
var lbl_status: Label

# ─── Estado ──────────────────────────────────────────────────────────────────

## True mientras la UI del chat está abierta.
var _chat_open: bool = false


func _ready():
	if prompt_bubble:
		prompt_bubble.visible = false
		if prompt_sprite_resource:
			prompt_bubble.texture = prompt_sprite_resource

	if area_2d:
		area_2d.body_entered.connect(_on_body_entered)
		area_2d.body_exited.connect(_on_body_exited)

	_create_ui()

	# Conectar señales del NpcChatAPI
	NpcChatAPI.chat_response_received.connect(_on_chat_response)
	NpcChatAPI.chat_request_failed.connect(_on_chat_error)


# ─── Creación de la UI ──────────────────────────────────────────────────────

func _create_ui():
	canvas_layer = CanvasLayer.new()
	canvas_layer.visible = false
	add_child(canvas_layer)

	var panel = PanelContainer.new()
	if dialog_theme:
		panel.theme = dialog_theme
	panel.custom_minimum_size = Vector2(450, 280)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	canvas_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Título
	var title = Label.new()
	title.text = "🤖 Tutor IA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Área de chat con scroll
	chat_display = RichTextLabel.new()
	chat_display.bbcode_enabled = true
	chat_display.scroll_following = true
	chat_display.fit_content = false
	chat_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_display.custom_minimum_size = Vector2(0, 160)
	vbox.add_child(chat_display)

	# Indicador de estado
	lbl_status = Label.new()
	lbl_status.text = ""
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.add_theme_font_size_override("font_size", 11)
	vbox.add_child(lbl_status)

	# Campo de texto
	line_edit = LineEdit.new()
	line_edit.placeholder_text = "Escribe tu duda sobre la lectura..."
	line_edit.text_submitted.connect(_on_text_submitted)
	vbox.add_child(line_edit)

	# Botones
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	btn_enviar = Button.new()
	btn_enviar.text = "Enviar"
	btn_enviar.pressed.connect(_on_btn_enviar_pressed)
	hbox.add_child(btn_enviar)

	btn_cerrar = Button.new()
	btn_cerrar.text = "Cerrar"
	btn_cerrar.pressed.connect(_on_btn_cerrar_pressed)
	hbox.add_child(btn_cerrar)


# ─── Interacción del jugador ────────────────────────────────────────────────

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		if prompt_bubble:
			prompt_bubble.visible = true

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		if prompt_bubble:
			prompt_bubble.visible = false

func _process(_delta):
	if player_in_range and visible and Input.is_action_just_pressed("ui_accept"):
		if not SceneManager.is_ui_open:
			show_ui()


# ─── UI del Chat ────────────────────────────────────────────────────────────

func show_ui():
	if canvas_layer:
		SceneManager.is_ui_open = true
		_chat_open = true
		canvas_layer.visible = true
		lbl_status.text = ""
		_set_input_enabled(true)

		# Si no hay historial, mostrar saludo inicial
		if NpcChatAPI.chat_history.is_empty():
			_render_welcome()
		else:
			_render_full_history()

		line_edit.text = ""
		line_edit.grab_focus()


func hide_ui():
	if canvas_layer:
		canvas_layer.visible = false
	_chat_open = false
	SceneManager.is_ui_open = false


## Envía el mensaje al tutor IA.
func _send_message():
	var text := line_edit.text.strip_edges()
	if text.is_empty():
		return

	# Renderizar mensaje del usuario inmediatamente
	_append_user_message(text)
	line_edit.text = ""

	# Deshabilitar input y mostrar indicador
	_set_input_enabled(false)
	lbl_status.text = "💭 Pensando..."

	# Enviar al backend
	NpcChatAPI.send_message(text)


# ─── Callbacks de NpcChatAPI ────────────────────────────────────────────────

func _on_chat_response(_session_id: int, response_text: String):
	if not _chat_open:
		return

	_append_assistant_message(response_text)
	lbl_status.text = ""
	_set_input_enabled(true)
	line_edit.grab_focus()


func _on_chat_error(error: String):
	if not _chat_open:
		return

	lbl_status.text = "⚠️ " + error
	_set_input_enabled(true)
	line_edit.grab_focus()


# ─── Renderizado del chat ───────────────────────────────────────────────────

func _render_welcome():
	chat_display.clear()
	var reading_title: String = str(GameSession.current_reading.get("title", "la lectura"))
	chat_display.append_text(
		"[color=cyan]🤖 Tutor:[/color] ¡Hola! Soy tu tutor virtual. "
		+ "Estoy aquí para ayudarte a comprender [b]\"" + reading_title + "\"[/b]. "
		+ "Puedo darte pistas y orientarte, pero no te daré las respuestas directas. "
		+ "¡Pregúntame lo que necesites!\n"
	)


func _render_full_history():
	chat_display.clear()
	for msg in NpcChatAPI.chat_history:
		if msg["role"] == "user":
			_append_user_message(msg["content"], false)
		else:
			_append_assistant_message(msg["content"], false)


func _append_user_message(text: String, scroll: bool = true):
	chat_display.append_text("\n[color=yellow]Tú:[/color] " + text + "\n")
	if scroll:
		_scroll_to_bottom()


func _append_assistant_message(text: String, scroll: bool = true):
	chat_display.append_text("\n[color=cyan]🤖 Tutor:[/color] " + text + "\n")
	if scroll:
		_scroll_to_bottom()


func _scroll_to_bottom():
	# Esperar un frame para que el contenido se renderice antes de hacer scroll
	await get_tree().process_frame
	var scrollbar := chat_display.get_v_scroll_bar()
	if scrollbar:
		scrollbar.value = scrollbar.max_value


func _set_input_enabled(enabled: bool):
	line_edit.editable = enabled
	btn_enviar.disabled = not enabled


# ─── Eventos de UI ──────────────────────────────────────────────────────────

func _on_btn_enviar_pressed():
	_send_message()

func _on_text_submitted(_text: String):
	_send_message()

func _on_btn_cerrar_pressed():
	hide_ui()
