## achievements_medals_panel.gd
## Panel de control para visualizar Logros y Medallas del jugador de forma separada.
extends CanvasLayer

@onready var _logros_tab_btn: Button = %LogrosTabBtn
@onready var _medallas_tab_btn: Button = %MedallasTabBtn
@onready var _close_button: Button = %CloseButton

@onready var _logros_scroll: ScrollContainer = %LogrosScroll
@onready var _medallas_scroll: ScrollContainer = %MedalsScroll # En el tscn se llama MedalsScroll

@onready var _achievements_container: VBoxContainer = %AchievementsContainer
@onready var _medals_grid: GridContainer = %MedalsGrid
@onready var _total_label: Label = %TotalLabel

# Detalles de Medalla
@onready var _medal_detail_panel: PanelContainer = %MedalDetailPanel
@onready var _detail_medal_name: Label = %DetailMedalName
@onready var _detail_medal_desc: Label = %DetailMedalDesc
@onready var _detail_medal_tier: Label = %DetailMedalTier
@onready var _detail_medal_image: TextureRect = %DetailMedalImage
@onready var _detail_medal_emoji: Label = %DetailMedalEmoji
@onready var _detail_close_btn: Button = %DetailCloseBtn

var _http_request: HTTPRequest
var _achievements_data: Array = []

func _ready() -> void:
	# Asegurar prioridad visual alta
	layer = 100
	
	_logros_tab_btn.pressed.connect(_on_logros_tab_pressed)
	_medallas_tab_btn.pressed.connect(_on_medallas_tab_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	_detail_close_btn.pressed.connect(func(): _medal_detail_panel.hide())
	
	# Mostrar pestaña Logros por defecto
	_on_logros_tab_pressed()
	_medal_detail_panel.hide()
	
	# Inicializar HTTPRequest
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	# Cargar datos desde la API
	_fetch_achievements()


func _fetch_achievements() -> void:
	if not AuthManager.is_authenticated:
		_total_label.text = "Inicia sesión para ver tus logros"
		return
		
	var url := "%s/progress/achievements-full" % ApiConfig.BASE_URL
	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append("Authorization: Bearer %s" % AuthManager.auth_token)
	if AuthManager.current_slot_id > 0:
		headers.append("X-Slot-Id: %d" % AuthManager.current_slot_id)
		
	var err := _http_request.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_total_label.text = "Error al conectar con el servidor"


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_total_label.text = "Error cargando logros (HTTP %d)" % response_code
		return
		
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.data is Array:
		_achievements_data = json.data
		_populate_ui()
	else:
		_total_label.text = "Error parseando datos de logros"


func _populate_ui() -> void:
	# Limpiar contenedores
	for child in _achievements_container.get_children():
		child.queue_free()
	for child in _medals_grid.get_children():
		child.queue_free()
		
	var total_count := _achievements_data.size()
	var unlocked_count := 0
	
	for item in _achievements_data:
		var is_unlocked: bool = item.get("is_unlocked", false)
		if is_unlocked:
			unlocked_count += 1
			
		_create_achievement_item(item)
		_create_medal_item(item)
		
	_total_label.text = "Completado: %d / %d" % [unlocked_count, total_count]


func _create_achievement_item(item: Dictionary) -> void:
	var is_unlocked: bool = item.get("is_unlocked", false)
	var bg_color := Color(0.12, 0.14, 0.2, 0.8) if is_unlocked else Color(0.08, 0.09, 0.12, 0.6)
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 55)
	
	# Usar un estilo en caja simple
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = 4
	# Borde dorado si está desbloqueado, gris si no
	style.border_color = Color(0.85, 0.65, 0.13) if is_unlocked else Color(0.3, 0.3, 0.3)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)
	
	# Ícono / Estado
	var status_lbl := Label.new()
	status_lbl.text = "✅" if is_unlocked else "🔒"
	status_lbl.add_theme_font_size_override("font_size", 18)
	hbox.add_child(status_lbl)
	
	# Info de texto
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)
	
	var title_lbl := Label.new()
	title_lbl.text = str(item.get("name", ""))
	title_lbl.add_theme_color_override("font_color", Color(1, 1, 1) if is_unlocked else Color(0.6, 0.6, 0.6))
	title_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title_lbl)
	
	var desc_lbl := Label.new()
	desc_lbl.text = str(item.get("description", ""))
	desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8) if is_unlocked else Color(0.4, 0.4, 0.4))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)
	
	# Cómo desbloquear (solo si está bloqueado)
	if not is_unlocked:
		var lock_lbl := Label.new()
		lock_lbl.text = "Cómo: " + str(item.get("how_to_unlock", ""))
		lock_lbl.add_theme_color_override("font_color", Color(0.7, 0.5, 0.3))
		lock_lbl.add_theme_font_size_override("font_size", 10)
		lock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(lock_lbl)
	
	_achievements_container.add_child(panel)


func _create_medal_item(item: Dictionary) -> void:
	var is_unlocked: bool = item.get("is_unlocked", false)
	var tier: String = str(item.get("medal_tier", "bronce"))
	var bg_color := _get_tier_color(tier)
	
	# Contenedor de la carta
	var card := Button.new()
	card.custom_minimum_size = Vector2(85, 95)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Estilo visual de la medalla
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.set_border_width_all(2)
	style_normal.border_color = Color(0.9, 0.8, 0.2) if is_unlocked else Color(0.15, 0.15, 0.15)
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.set_content_margin_all(4)
	
	card.add_theme_stylebox_override("normal", style_normal)
	card.add_theme_stylebox_override("hover", style_normal)
	card.add_theme_stylebox_override("pressed", style_normal)
	
	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)
	
	# Emoji o Imagen
	var img_container := CenterContainer.new()
	vbox.add_child(img_container)
	
	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(40, 40)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img_container.add_child(texture_rect)
	
	var emoji_lbl := Label.new()
	emoji_lbl.text = str(item.get("medal_placeholder_emoji", "🏅"))
	emoji_lbl.add_theme_font_size_override("font_size", 28)
	emoji_lbl.horizontal_alignment = 1
	img_container.add_child(emoji_lbl)
	
	# Cargar imagen real si existe y está desbloqueada
	var image_url: String = str(item.get("medal_image_path", ""))
	if is_unlocked and not image_url.is_empty():
		MedalImageLoader.load_medal_image(str(item["id"]), image_url, func(tex):
			if tex:
				texture_rect.texture = tex
				emoji_lbl.hide()
				texture_rect.show()
		)
		texture_rect.hide()
		emoji_lbl.show()
	else:
		texture_rect.hide()
		emoji_lbl.show()
		
	# Efecto grisáceo si está bloqueado
	if not is_unlocked:
		emoji_lbl.modulate = Color(0.2, 0.2, 0.2, 0.7)
		card.modulate = Color(0.6, 0.6, 0.6, 1)
	
	# Nombre de la medalla
	var name_lbl := Label.new()
	name_lbl.text = "???" if not is_unlocked else str(item.get("medal_name", ""))
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1) if is_unlocked else Color(0.4, 0.4, 0.4))
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.horizontal_alignment = 1
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_lbl)
	
	# Evento de clic
	card.pressed.connect(func(): _show_medal_detail(item))
	
	_medals_grid.add_child(card)


func _show_medal_detail(item: Dictionary) -> void:
	var is_unlocked: bool = item.get("is_unlocked", false)
	var tier: String = str(item.get("medal_tier", "bronce"))
	
	_detail_medal_name.text = str(item.get("medal_name", "???")) if is_unlocked else "Medalla Bloqueada"
	_detail_medal_desc.text = str(item.get("medal_description", "")) if is_unlocked else "Desbloquea el logro '%s' para conseguir esta medalla.\n\nRequisito: %s" % [item.get("name", ""), item.get("how_to_unlock", "")]
	_detail_medal_tier.text = "Rareza: %s" % tier.to_upper()
	_detail_medal_tier.add_theme_color_override("font_color", _get_tier_color(tier))
	
	_detail_medal_emoji.text = str(item.get("medal_placeholder_emoji", "🏅"))
	_detail_medal_emoji.show()
	_detail_medal_image.hide()
	
	var image_url: String = str(item.get("medal_image_path", ""))
	if is_unlocked and not image_url.is_empty():
		MedalImageLoader.load_medal_image(str(item["id"]), image_url, func(tex):
			if tex:
				_detail_medal_image.texture = tex
				_detail_medal_emoji.hide()
				_detail_medal_image.show()
		)
	
	# Ajustar color de fondo del detalle según el tier
	var style := StyleBoxFlat.new()
	style.bg_color = _get_tier_color(tier) * Color(0.2, 0.2, 0.2, 0.9)  # Más oscuro
	style.set_border_width_all(3)
	style.border_color = _get_tier_color(tier)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.set_content_margin_all(15)
	_medal_detail_panel.add_theme_stylebox_override("panel", style)
	
	_medal_detail_panel.show()


func _get_tier_color(tier: String) -> Color:
	match tier.to_lower():
		"bronce":
			return Color(0.65, 0.45, 0.25)
		"plata":
			return Color(0.6, 0.65, 0.7)
		"oro":
			return Color(0.85, 0.65, 0.1)
		"platino":
			return Color(0.8, 0.9, 0.95)
		_:
			return Color(0.4, 0.4, 0.4)


func _on_logros_tab_pressed() -> void:
	_logros_tab_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	_logros_tab_btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	_logros_scroll.show()
	
	_medallas_tab_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_medallas_scroll.hide()


func _on_medallas_tab_pressed() -> void:
	_medallas_tab_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	_medallas_scroll.show()
	
	_logros_tab_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_logros_scroll.hide()


func _on_close_pressed() -> void:
	queue_free()
