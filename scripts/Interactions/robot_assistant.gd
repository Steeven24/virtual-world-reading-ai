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

# ─── Estilo (alineado con score_hud / achievement_toast / tutorial_overlay) ─

const FONT_BOLD_PATH := "res://fonts/PixelifySans-SemiBold.ttf"
const FONT_REGULAR_PATH := "res://fonts/PixelifySans-VariableFont_wght.ttf"

const COLOR_BG := Color(0.06, 0.06, 0.12, 0.96)
const COLOR_CHAT_BG := Color(0.04, 0.04, 0.09, 1.0)
const COLOR_INPUT_BG := Color(0.10, 0.10, 0.18, 1.0)
const COLOR_BUTTON_BG := Color(0.12, 0.12, 0.20, 1.0)
const COLOR_BORDER := Color(0.85, 0.75, 0.3, 0.6)
const COLOR_BORDER_SOFT := Color(0.85, 0.75, 0.3, 0.35)
const COLOR_BORDER_FOCUS := Color(0.85, 0.75, 0.3, 1.0)
const COLOR_GOLD := Color(0.95, 0.85, 0.4, 1.0)
const COLOR_TEXT := Color(0.92, 0.94, 0.97, 1.0)
const COLOR_SUBTLE := Color(0.7, 0.72, 0.8, 1.0)
const COLOR_RED := Color(0.85, 0.55, 0.55, 1.0)

const PANEL_WIDTH: int = 720
const PANEL_HEIGHT: int = 520
const ANIM_DURATION: float = 0.32

# Colores BBCode para los mensajes del chat
const HEX_USER := "#aac4ff"
const HEX_ASSISTANT := "#f0c050"
const HEX_NOTICE := "#b3b8c8"

# ─── Nodos de la UI (creados por código) ────────────────────────────────────

var canvas_layer: CanvasLayer
var dim: ColorRect
var panel: PanelContainer
var chat_display: RichTextLabel
var line_edit: LineEdit
var btn_enviar: Button
var btn_cerrar: Button
var lbl_status: Label

var _font_bold: Font = null
var _font_regular: Font = null

# ─── Estado ──────────────────────────────────────────────────────────────────

## True mientras la UI del chat está abierta.
var _chat_open: bool = false


func _ready():
	visibility_changed.connect(_on_visibility_changed)

	if prompt_bubble:
		prompt_bubble.visible = false
		if prompt_sprite_resource:
			prompt_bubble.texture = prompt_sprite_resource

	if area_2d:
		area_2d.body_entered.connect(_on_body_entered)
		area_2d.body_exited.connect(_on_body_exited)

	_font_bold = load(FONT_BOLD_PATH) if ResourceLoader.exists(FONT_BOLD_PATH) else null
	_font_regular = load(FONT_REGULAR_PATH) if ResourceLoader.exists(FONT_REGULAR_PATH) else null
	if SceneManager:
		SceneManager.ensure_fallbacks(_font_bold)
		SceneManager.ensure_fallbacks(_font_regular)

	_create_ui()
	
	# Alinear colisiones al estado inicial
	_on_visibility_changed()

	# Conectar señales del NpcChatAPI
	NpcChatAPI.chat_response_received.connect(_on_chat_response)
	NpcChatAPI.chat_request_failed.connect(_on_chat_error)
	NpcChatAPI.history_loaded.connect(_on_history_loaded)
	NpcChatAPI.history_load_failed.connect(_on_history_load_failed)

	# Entrar a este escenario descarta la conversación del anterior.
	# El robot se instancia junto con el nivel, así que esto corre una vez
	# por escenario aunque el jugador nunca llegue a abrir el diálogo.
	NpcChatAPI.begin_scenario(_get_reading_id())


# ─── Creación de la UI ──────────────────────────────────────────────────────

func _create_ui():
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 50
	canvas_layer.follow_viewport_enabled = false
	canvas_layer.visible = false
	add_child(canvas_layer)

	# Fondo oscurecido a pantalla completa.
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(dim)

	# Panel principal centrado.
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	canvas_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# ─── Header: título + botón cerrar ─────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "🤖  Tutor IA"
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_font_size_override("font_size", 22)
	if _font_bold:
		title.add_theme_font_override("font", _font_bold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	btn_cerrar = Button.new()
	btn_cerrar.text = "✖"
	btn_cerrar.tooltip_text = "Cerrar chat"
	btn_cerrar.add_theme_color_override("font_color", COLOR_RED)
	btn_cerrar.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.7, 1.0))
	btn_cerrar.add_theme_font_size_override("font_size", 18)
	if _font_bold:
		btn_cerrar.add_theme_font_override("font", _font_bold)
	_apply_button_styles(btn_cerrar, COLOR_RED, 0.45)
	btn_cerrar.custom_minimum_size = Vector2(40, 32)
	btn_cerrar.focus_mode = Control.FOCUS_NONE
	btn_cerrar.pressed.connect(_on_btn_cerrar_pressed)
	header.add_child(btn_cerrar)

	# Separador sutil
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 1)
	vbox.add_child(sep)

	# ─── Área de chat ──────────────────────────────────────────────────────
	var chat_panel := PanelContainer.new()
	chat_panel.add_theme_stylebox_override("panel", _make_chat_style())
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(chat_panel)

	var chat_margin := MarginContainer.new()
	chat_margin.add_theme_constant_override("margin_left", 14)
	chat_margin.add_theme_constant_override("margin_top", 12)
	chat_margin.add_theme_constant_override("margin_right", 14)
	chat_margin.add_theme_constant_override("margin_bottom", 12)
	chat_panel.add_child(chat_margin)

	chat_display = RichTextLabel.new()
	chat_display.bbcode_enabled = true
	chat_display.scroll_active = true
	chat_display.scroll_following = true
	chat_display.fit_content = false
	chat_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_display.custom_minimum_size = Vector2(0, 280)
	chat_display.add_theme_color_override("default_color", COLOR_TEXT)
	chat_display.add_theme_font_size_override("normal_font_size", 16)
	chat_display.add_theme_font_size_override("bold_font_size", 16)
	chat_display.add_theme_font_size_override("italics_font_size", 16)
	if _font_regular:
		chat_display.add_theme_font_override("normal_font", _font_regular)
	if _font_bold:
		chat_display.add_theme_font_override("bold_font", _font_bold)
	chat_margin.add_child(chat_display)

	# ─── Estado / typing indicator ────────────────────────────────────────
	lbl_status = Label.new()
	lbl_status.text = ""
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl_status.add_theme_color_override("font_color", COLOR_SUBTLE)
	lbl_status.add_theme_font_size_override("font_size", 13)
	if _font_regular:
		lbl_status.add_theme_font_override("font", _font_regular)
	vbox.add_child(lbl_status)

	# ─── Fila de input ────────────────────────────────────────────────────
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	vbox.add_child(input_row)

	line_edit = LineEdit.new()
	line_edit.placeholder_text = "Escribe tu duda sobre la lectura..."
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.add_theme_color_override("font_color", COLOR_TEXT)
	line_edit.add_theme_color_override("font_placeholder_color", COLOR_SUBTLE)
	line_edit.add_theme_color_override("caret_color", COLOR_GOLD)
	line_edit.add_theme_color_override("selection_color", Color(0.85, 0.75, 0.3, 0.35))
	line_edit.add_theme_font_size_override("font_size", 16)
	if _font_regular:
		line_edit.add_theme_font_override("font", _font_regular)
	line_edit.add_theme_stylebox_override("normal", _make_input_style(COLOR_BORDER))
	line_edit.add_theme_stylebox_override("focus", _make_input_style(COLOR_BORDER_FOCUS))
	line_edit.add_theme_stylebox_override("read_only", _make_input_style(COLOR_BORDER_SOFT))
	line_edit.text_submitted.connect(_on_text_submitted)
	input_row.add_child(line_edit)

	btn_enviar = Button.new()
	btn_enviar.text = "Enviar  ➤"
	btn_enviar.add_theme_color_override("font_color", COLOR_GOLD)
	btn_enviar.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.6, 1.0))
	btn_enviar.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.35, 1.0))
	btn_enviar.add_theme_font_size_override("font_size", 15)
	if _font_bold:
		btn_enviar.add_theme_font_override("font", _font_bold)
	_apply_button_styles(btn_enviar, COLOR_GOLD, 0.6)
	btn_enviar.custom_minimum_size = Vector2(120, 0)
	btn_enviar.pressed.connect(_on_btn_enviar_pressed)
	input_row.add_child(btn_enviar)

	# Layout responsive
	get_window().size_changed.connect(_layout_ui)
	_layout_ui()


# ─── Estilos (StyleBoxFlat helpers) ────────────────────────────────────────

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_BG
	s.border_color = Color(0.85, 0.75, 0.3, 0.7)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 14
	s.corner_radius_top_right = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right = 14
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 12
	return s


func _make_chat_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_CHAT_BG
	s.border_color = COLOR_BORDER_SOFT
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	return s


func _make_input_style(border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_INPUT_BG
	s.border_color = border
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _make_button_style(border: Color, alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_BUTTON_BG
	var b := border
	b.a = alpha
	s.border_color = b
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _apply_button_styles(btn: Button, accent: Color, base_alpha: float) -> void:
	btn.add_theme_stylebox_override("normal", _make_button_style(accent, base_alpha))
	btn.add_theme_stylebox_override("hover", _make_button_style(accent, min(1.0, base_alpha + 0.3)))
	btn.add_theme_stylebox_override("pressed", _make_button_style(accent, min(1.0, base_alpha + 0.15)))
	btn.add_theme_stylebox_override("focus", _make_button_style(accent, min(1.0, base_alpha + 0.4)))
	btn.add_theme_stylebox_override("disabled", _make_button_style(COLOR_BORDER_SOFT, 0.3))


# ─── Layout responsive ─────────────────────────────────────────────────────

func _layout_ui() -> void:
	var win := _get_window_size()
	if dim:
		dim.position = Vector2.ZERO
		dim.size = win
	if panel:
		panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
		panel.position = Vector2(
			(win.x - PANEL_WIDTH) / 2.0,
			(win.y - PANEL_HEIGHT) / 2.0
		)


func _get_window_size() -> Vector2:
	var window := get_window()
	if window:
		return Vector2(window.size)
	return Vector2(
		ProjectSettings.get_setting("display/window/size/window_width_override", 1280),
		ProjectSettings.get_setting("display/window/size/window_height_override", 720)
	)


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
	if not canvas_layer:
		return

	SceneManager.is_ui_open = true
	_chat_open = true
	canvas_layer.visible = true
	line_edit.text = ""

	# Este NPC es el activo para el registro de interacciones.
	NpcChatAPI.set_npc_type("robot")

	# El panel SIEMPRE arranca en blanco: nunca se ven aquí los mensajes
	# de un escenario anterior, aunque el autoload siga vivo.
	chat_display.clear()

	var reading_id: int = _get_reading_id()
	NpcChatAPI.begin_scenario(reading_id)

	if reading_id > 0:
		# El servidor manda: pedimos la conversación de ESTA lectura y la
		# pintamos cuando llegue (_on_history_loaded).
		_set_input_enabled(false)
		lbl_status.text = "⏳  Recuperando tu conversación..."
		NpcChatAPI.fetch_history(reading_id)
	else:
		# Sin lectura activa no hay conversación que recuperar.
		lbl_status.text = ""
		_set_input_enabled(true)
		_render_welcome()

	_animate_in()


func hide_ui():
	if not canvas_layer:
		return
	_chat_open = false
	SceneManager.is_ui_open = false
	_animate_out()


# ─── Animaciones ───────────────────────────────────────────────────────────

func _animate_in() -> void:
	_layout_ui()
	dim.modulate.a = 0.0
	panel.modulate.a = 0.0
	var final_y := panel.position.y
	panel.position.y = final_y + 30.0

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(dim, "modulate:a", 1.0, ANIM_DURATION)
	tween.tween_property(panel, "modulate:a", 1.0, ANIM_DURATION).set_delay(0.05)
	tween.tween_property(panel, "position:y", final_y, ANIM_DURATION).set_delay(0.05)
	tween.chain().tween_callback(_focus_input_after_animation)


func _focus_input_after_animation() -> void:
	if line_edit and line_edit.editable:
		line_edit.grab_focus()


func _animate_out() -> void:
	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(dim, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_property(panel, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_property(panel, "position:y", panel.position.y + 30.0, ANIM_DURATION)
	await tween.finished
	if canvas_layer:
		canvas_layer.visible = false


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
	lbl_status.text = "💭  Pensando..."

	# Enviar al backend
	NpcChatAPI.send_message(text)


# ─── Callbacks de NpcChatAPI ────────────────────────────────────────────────

func _on_chat_response(_conversation_id: String, response_text: String):
	if not _chat_open:
		return

	_append_assistant_message(response_text)
	lbl_status.text = ""
	_set_input_enabled(true)
	line_edit.grab_focus()


func _on_chat_error(error: String):
	if not _chat_open:
		return

	lbl_status.text = "⚠️  " + error
	_set_input_enabled(true)
	line_edit.grab_focus()


## Llega la conversación de esta lectura desde /npc/history.
func _on_history_loaded(_reading_id: int, messages: Array):
	if not _chat_open:
		return

	lbl_status.text = ""
	_set_input_enabled(true)

	# Repintar desde cero con lo que diga el servidor.
	chat_display.clear()
	if messages.is_empty():
		_render_welcome()
	else:
		_render_full_history()

	line_edit.grab_focus()


## No se pudo recuperar el historial: se puede chatear igual, en limpio.
func _on_history_load_failed(error: String):
	if not _chat_open:
		return

	chat_display.clear()
	_render_welcome()
	lbl_status.text = "⚠️  No se pudo recuperar la conversación anterior (%s)" % error
	_set_input_enabled(true)
	line_edit.grab_focus()


# ─── Renderizado del chat ───────────────────────────────────────────────────

## reading_id de la lectura activa (-1 si no hay ninguna).
func _get_reading_id() -> int:
	var reading: Dictionary = GameSession.current_reading
	if reading.is_empty():
		return -1
	return int(reading.get("id", -1))


func _render_welcome():
	chat_display.clear()
	var reading_title: String = str(GameSession.current_reading.get("title", "la lectura"))
	chat_display.append_text(
		"[color=%s][b]🤖 Tutor:[/b][/color]  ¡Hola! Soy tu tutor virtual. " % HEX_ASSISTANT
		+ "Resuelvo [b]tus dudas concretas[/b] sobre [b]\"" + reading_title + "\"[/b] y te oriento con el juego si te pierdes.\n"
		+ "[color=%s]Pregúntame cosas como «¿qué significa esta palabra?», «¿de qué trata el tercer párrafo?» o «¿cómo uso las herramientas del libro?».\n" % HEX_NOTICE
		+ "Te doy pistas para que llegues tú a la respuesta, nunca la respuesta directa. Para consejos generales de lectura habla con el sabio, y quien te evalúa es el profesor.\n[/color]"
	)


func _render_full_history():
	chat_display.clear()
	for msg in NpcChatAPI.chat_history:
		if msg["role"] == "user":
			_append_user_message(msg["content"], false)
		else:
			_append_assistant_message(msg["content"], false)


func _append_user_message(text: String, scroll: bool = true):
	chat_display.append_text(
		"\n[color=%s][b]Tú:[/b][/color]  " % HEX_USER + text + "\n"
	)
	if scroll:
		_scroll_to_bottom()


func _append_assistant_message(text: String, scroll: bool = true):
	chat_display.append_text(
		"\n[color=%s][b]🤖 Tutor:[/b][/color]  " % HEX_ASSISTANT + text + "\n"
	)
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

func _on_visibility_changed():
	if not visible:
		player_in_range = false
		if prompt_bubble:
			prompt_bubble.visible = false
	_set_collision_shapes_disabled(self, not visible)

func _set_collision_shapes_disabled(node: Node, should_disable: bool):
	if node is CollisionShape2D:
		node.set_deferred("disabled", should_disable)
	for child in node.get_children():
		_set_collision_shapes_disabled(child, should_disable)
