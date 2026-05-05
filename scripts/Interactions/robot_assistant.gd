extends Node2D

@export var prompt_sprite_resource: Texture2D
@export var dialog_theme: Theme

var player_in_range = false

@onready var prompt_bubble = $"Speech bubble" if has_node("Speech bubble") else null
@onready var area_2d = $Area2D if has_node("Area2D") else null

var canvas_layer: CanvasLayer
var line_edit: LineEdit
var btn_enviar: Button
var btn_cerrar: Button
var lbl_respuesta: Label

func _ready():
	if prompt_bubble:
		prompt_bubble.visible = false
		if prompt_sprite_resource:
			prompt_bubble.texture = prompt_sprite_resource
			
	if area_2d:
		area_2d.body_entered.connect(_on_body_entered)
		area_2d.body_exited.connect(_on_body_exited)
		
	_create_ui()

func _create_ui():
	canvas_layer = CanvasLayer.new()
	canvas_layer.visible = false
	add_child(canvas_layer)
	
	var panel = PanelContainer.new()
	if dialog_theme:
		panel.theme = dialog_theme
	panel.custom_minimum_size = Vector2(400, 200)
	# Centrar en pantalla
	panel.set_anchors_preset(Control.PRESET_CENTER)
	canvas_layer.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Márgenes internos (opcional)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "Robot Asistente (MCP)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	lbl_respuesta = Label.new()
	lbl_respuesta.text = ""
	lbl_respuesta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_respuesta.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(lbl_respuesta)
	
	line_edit = LineEdit.new()
	line_edit.placeholder_text = "Escribe tu duda aquí..."
	vbox.add_child(line_edit)
	
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

func show_ui():
	if canvas_layer:
		SceneManager.is_ui_open = true
		canvas_layer.visible = true
		lbl_respuesta.text = "¡Hola! Soy tu asistente conectado al MCP. ¿En qué puedo ayudarte?"
		line_edit.text = ""
		line_edit.grab_focus()

func _on_btn_enviar_pressed():
	if not line_edit.text.is_empty():
		var consulta = line_edit.text
		# Enviar a MCP Client Autoload
		var respuesta = ""
		if Engine.has_singleton("MCPClientNode") or get_node_or_null("/root/MCPClientNode"):
			var mcp = get_node("/root/MCPClientNode")
			respuesta = mcp.request_assistance(consulta)
		else:
			respuesta = "MCP Client no disponible. Mock: Puedo ayudarte a aclarar términos."
			
		lbl_respuesta.text = "Tú: " + consulta + "\n\nAsistente: " + respuesta
		line_edit.text = ""

func _on_btn_cerrar_pressed():
	if canvas_layer:
		canvas_layer.visible = false
	SceneManager.is_ui_open = false
