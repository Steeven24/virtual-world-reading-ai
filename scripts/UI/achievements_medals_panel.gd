## achievements_medals_panel.gd
## Panel premium para visualizar Logros y Medallas del jugador.
## Diseño visual mejorado con animaciones, efectos de brillo, y transiciones suaves.
extends CanvasLayer

# ─── Constantes de diseño ────────────────────────────────────────────────────

const COLOR_GOLD := Color(0.93, 0.79, 0.28)
const COLOR_GOLD_DIM := Color(0.93, 0.79, 0.28, 0.35)
const COLOR_BG_PANEL := Color(0.05, 0.06, 0.09, 0.97)
const COLOR_BG_ITEM := Color(0.09, 0.11, 0.17, 0.9)
const COLOR_BG_ITEM_LOCKED := Color(0.05, 0.06, 0.09, 0.7)
const COLOR_TEXT_PRIMARY := Color(0.93, 0.94, 0.96)
const COLOR_TEXT_SECONDARY := Color(0.6, 0.62, 0.68)
const COLOR_TEXT_DISABLED := Color(0.35, 0.36, 0.40)
const COLOR_HINT := Color(0.75, 0.55, 0.30)

const STAGGER_DELAY := 0.05
const OPEN_ANIM_DURATION := 0.35
const TAB_ANIM_DURATION := 0.2

# ─── Nodos ───────────────────────────────────────────────────────────────────

@onready var _bg_dim: ColorRect = %BackgroundDim
@onready var _main_panel: PanelContainer = %MainPanel


@onready var _logros_tab_btn: Button = %LogrosTabBtn
@onready var _medallas_tab_btn: Button = %MedallasTabBtn
@onready var _close_button: Button = %CloseButton

@onready var _logros_scroll: ScrollContainer = %LogrosScroll
@onready var _medallas_scroll: ScrollContainer = %MedalsScroll
@onready var _achievements_container: VBoxContainer = %AchievementsContainer
@onready var _medals_grid: GridContainer = %MedalsGrid
@onready var _total_label: Label = %TotalLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _loading_label: Label = %LoadingLabel

# Detalles de Medalla
@onready var _medal_detail_panel: PanelContainer = %MedalDetailPanel
@onready var _detail_medal_name: Label = %DetailMedalName
@onready var _detail_medal_desc: Label = %DetailMedalDesc
@onready var _detail_medal_tier: Label = %DetailMedalTier
@onready var _detail_medal_image: TextureRect = %DetailMedalImage
@onready var _detail_medal_emoji: Label = %DetailMedalEmoji
@onready var _detail_close_btn: Button = %DetailCloseBtn

# ─── Estado ──────────────────────────────────────────────────────────────────

var _http_request: HTTPRequest
var _achievements_data: Array = []
var _loading_tween: Tween
var _font_bold: Font
var _font_regular: Font

# ─── Ciclo de vida ───────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 100

	_font_bold = load("res://fonts/PixelifySans-SemiBold.ttf") if ResourceLoader.exists("res://fonts/PixelifySans-SemiBold.ttf") else null
	_font_regular = load("res://fonts/PixelifySans-VariableFont_wght.ttf") if ResourceLoader.exists("res://fonts/PixelifySans-VariableFont_wght.ttf") else null

	if SceneManager:
		SceneManager.ensure_fallbacks(_font_bold)
		SceneManager.ensure_fallbacks(_font_regular)

	# Conectar señales
	_logros_tab_btn.pressed.connect(_on_logros_tab_pressed)
	_medallas_tab_btn.pressed.connect(_on_medallas_tab_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	_detail_close_btn.pressed.connect(_hide_medal_detail)

	# Aplicar estilos visuales premium
	_style_main_panel()
	_style_tabs()
	_style_close_button()
	_style_progress_bar()
	_style_detail_close_btn()

	# Estado inicial
	_on_logros_tab_pressed()
	_medal_detail_panel.hide()
	_medal_detail_panel.modulate.a = 0.0
	_loading_label.show()

	# Animación de apertura
	_animate_open()

	# Animación de carga
	_animate_loading()

	# HTTP
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	_fetch_achievements()


# ─── Estilos Visuales ────────────────────────────────────────────────────────

func _style_main_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_PANEL
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = COLOR_GOLD_DIM
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	_main_panel.add_theme_stylebox_override("panel", style)


func _style_tabs() -> void:
	_apply_tab_style(_logros_tab_btn, true)
	_apply_tab_style(_medallas_tab_btn, false)


func _apply_tab_style(btn: Button, active: bool) -> void:
	var style := StyleBoxFlat.new()
	if active:
		style.bg_color = Color(0.10, 0.12, 0.18, 0.8)
		style.border_width_bottom = 3
		style.border_color = COLOR_GOLD
		btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
		btn.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	else:
		style.bg_color = Color(0.04, 0.04, 0.07, 0.4)
		style.border_width_bottom = 1
		style.border_color = Color(0.2, 0.2, 0.25, 0.5)
		btn.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
		btn.add_theme_color_override("font_hover_color", Color(0.8, 0.8, 0.85))

	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.set_content_margin_all(8)

	var hover_style := style.duplicate()
	if active:
		hover_style.bg_color = Color(0.12, 0.14, 0.22, 0.9)
	else:
		hover_style.bg_color = Color(0.06, 0.07, 0.10, 0.6)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _style_close_button() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.08, 0.08, 0.6)
	normal.set_corner_radius_all(16)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.6, 0.25, 0.25, 0.5)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.35, 0.12, 0.12, 0.8)
	hover.set_corner_radius_all(16)
	hover.set_border_width_all(1)
	hover.border_color = Color(0.9, 0.3, 0.3, 0.8)

	_close_button.add_theme_stylebox_override("normal", normal)
	_close_button.add_theme_stylebox_override("hover", hover)
	_close_button.add_theme_stylebox_override("pressed", hover)
	_close_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_close_button.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))
	_close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.5, 0.5))
	if _font_bold:
		_close_button.add_theme_font_override("font", _font_bold)
	_close_button.add_theme_font_size_override("font_size", 16)


func _style_progress_bar() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.13, 1.0)
	bg.set_corner_radius_all(3)

	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_GOLD
	fill.set_corner_radius_all(3)

	_progress_bar.add_theme_stylebox_override("background", bg)
	_progress_bar.add_theme_stylebox_override("fill", fill)


func _style_detail_close_btn() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.08, 0.08, 0.6)
	normal.set_corner_radius_all(14)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.6, 0.25, 0.25, 0.4)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.35, 0.12, 0.12, 0.8)
	hover.set_corner_radius_all(14)
	hover.set_border_width_all(1)
	hover.border_color = Color(0.9, 0.3, 0.3, 0.7)

	_detail_close_btn.add_theme_stylebox_override("normal", normal)
	_detail_close_btn.add_theme_stylebox_override("hover", hover)
	_detail_close_btn.add_theme_stylebox_override("pressed", hover)
	_detail_close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_detail_close_btn.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))
	_detail_close_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.5, 0.5))
	if _font_bold:
		_detail_close_btn.add_theme_font_override("font", _font_bold)
	_detail_close_btn.add_theme_font_size_override("font_size", 12)


# ─── Animaciones ─────────────────────────────────────────────────────────────

func _animate_open() -> void:
	# Fondo: fade in
	_bg_dim.color.a = 0.0
	var bg_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	bg_tween.tween_property(_bg_dim, "color:a", 0.8, OPEN_ANIM_DURATION)

	# Panel: escala + fade
	_main_panel.pivot_offset = _main_panel.custom_minimum_size / 2.0
	_main_panel.scale = Vector2(0.92, 0.92)
	_main_panel.modulate.a = 0.0
	var panel_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	panel_tween.tween_property(_main_panel, "scale", Vector2.ONE, OPEN_ANIM_DURATION)
	panel_tween.parallel().tween_property(_main_panel, "modulate:a", 1.0, OPEN_ANIM_DURATION * 0.7)


func _animate_loading() -> void:
	_loading_tween = create_tween().set_loops()
	_loading_tween.tween_callback(func(): _loading_label.text = "⏳ Cargando logros")
	_loading_tween.tween_interval(0.4)
	_loading_tween.tween_callback(func(): _loading_label.text = "⏳ Cargando logros.")
	_loading_tween.tween_interval(0.4)
	_loading_tween.tween_callback(func(): _loading_label.text = "⏳ Cargando logros..")
	_loading_tween.tween_interval(0.4)
	_loading_tween.tween_callback(func(): _loading_label.text = "⏳ Cargando logros...")
	_loading_tween.tween_interval(0.4)


# ─── Datos ───────────────────────────────────────────────────────────────────

func _fetch_achievements() -> void:
	if not AuthManager.is_authenticated:
		_total_label.text = "Inicia sesión para ver tus logros"
		if _loading_tween and _loading_tween.is_valid():
			_loading_tween.kill()
		_loading_label.text = "🔒 Inicia sesión para ver tus logros"
		return

	var url := "%s/progress/achievements-full" % ApiConfig.BASE_URL
	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append("Authorization: Bearer %s" % AuthManager.auth_token)
	if AuthManager.current_slot_id > 0:
		headers.append("X-Slot-Id: %d" % AuthManager.current_slot_id)

	var err := _http_request.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_total_label.text = "Error al conectar"
		if _loading_tween and _loading_tween.is_valid():
			_loading_tween.kill()
		_loading_label.text = "❌ Error al conectar con el servidor"


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# Detener animación de carga
	if _loading_tween and _loading_tween.is_valid():
		_loading_tween.kill()
	_loading_label.hide()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_total_label.text = "Error (HTTP %d)" % response_code
		_loading_label.text = "❌ Error cargando logros"
		_loading_label.show()
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.data is Array:
		_achievements_data = json.data
		_populate_ui()
	else:
		_total_label.text = "Error parseando datos"
		_loading_label.text = "❌ Error en los datos recibidos"
		_loading_label.show()


# ─── Poblar UI ───────────────────────────────────────────────────────────────

func _populate_ui() -> void:
	# Limpiar contenedores
	for child in _achievements_container.get_children():
		child.queue_free()
	for child in _medals_grid.get_children():
		child.queue_free()

	var total_count := _achievements_data.size()
	var unlocked_count := 0

	for i in range(total_count):
		var item: Dictionary = _achievements_data[i]
		var is_unlocked: bool = item.get("is_unlocked", false)
		if is_unlocked:
			unlocked_count += 1
		_create_achievement_item(item, i)
		_create_medal_item(item, i)

	# Actualizar contador
	_total_label.text = "Completado: %d / %d" % [unlocked_count, total_count]

	# Animar barra de progreso
	var percent: float = (float(unlocked_count) / maxf(total_count, 1)) * 100.0
	var pb_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	pb_tween.tween_property(_progress_bar, "value", percent, 0.8).set_delay(0.3)


# ─── Crear ítem de Logro (Premium) ──────────────────────────────────────────

func _create_achievement_item(item: Dictionary, index: int) -> void:
	var is_unlocked: bool = item.get("is_unlocked", false)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 72)

	# Estilo premium con glow
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_ITEM if is_unlocked else COLOR_BG_ITEM_LOCKED
	style.set_corner_radius_all(10)
	style.border_width_left = 4
	style.border_color = COLOR_GOLD if is_unlocked else Color(0.25, 0.25, 0.30)
	style.set_content_margin_all(12)
	style.content_margin_left = 16

	# Glow dorado para desbloqueados
	if is_unlocked:
		style.shadow_color = Color(0.93, 0.79, 0.28, 0.15)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 2)

	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	panel.add_child(hbox)

	# Ícono grande
	var icon_lbl := Label.new()
	icon_lbl.text = "✅" if is_unlocked else "🔒"
	icon_lbl.add_theme_font_size_override("font_size", 26)
	if _font_bold:
		icon_lbl.add_theme_font_override("font", _font_bold)
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon_lbl)

	# Contenedor de texto
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	# Título del logro
	var title_lbl := Label.new()
	title_lbl.text = str(item.get("name", ""))
	title_lbl.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY if is_unlocked else COLOR_TEXT_DISABLED)
	title_lbl.add_theme_font_size_override("font_size", 16)
	if _font_bold:
		title_lbl.add_theme_font_override("font", _font_bold)
	vbox.add_child(title_lbl)

	# Descripción
	var desc_lbl := Label.new()
	desc_lbl.text = str(item.get("description", ""))
	desc_lbl.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY if is_unlocked else Color(0.4, 0.4, 0.45))
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	if _font_regular:
		desc_lbl.add_theme_font_override("font", _font_regular)
	vbox.add_child(desc_lbl)

	# Pista de desbloqueo (solo si bloqueado)
	if not is_unlocked:
		var hint_lbl := Label.new()
		hint_lbl.text = "💡 " + str(item.get("how_to_unlock", ""))
		hint_lbl.add_theme_color_override("font_color", COLOR_HINT)
		hint_lbl.add_theme_font_size_override("font_size", 11)
		hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		if _font_regular:
			hint_lbl.add_theme_font_override("font", _font_regular)
		vbox.add_child(hint_lbl)

	_achievements_container.add_child(panel)

	# Animación stagger fade-in
	panel.modulate.a = 0.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel, "modulate:a", 1.0, 0.3).set_delay(index * STAGGER_DELAY)


# ─── Crear ítem de Medalla (Premium) ────────────────────────────────────────

func _create_medal_item(item: Dictionary, index: int) -> void:
	var is_unlocked: bool = item.get("is_unlocked", false)
	var tier: String = str(item.get("medal_tier", "bronce"))
	var tier_color := _get_tier_color(tier)
	var glow_color := _get_tier_glow_color(tier)

	var card := Button.new()
	card.custom_minimum_size = Vector2(160, 160)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Estilo de la carta con glow por tier
	var style_normal := StyleBoxFlat.new()
	if is_unlocked:
		# Fondo sutil basado en el color del tier
		style_normal.bg_color = tier_color * Color(0.3, 0.3, 0.3, 1.0) + Color(0.04, 0.04, 0.06, 0.0)
		style_normal.set_border_width_all(2)
		style_normal.border_color = tier_color * Color(1.0, 1.0, 1.0, 0.7)
		style_normal.shadow_color = glow_color
		style_normal.shadow_size = 5
	else:
		style_normal.bg_color = Color(0.04, 0.04, 0.07, 0.8)
		style_normal.set_border_width_all(1)
		style_normal.border_color = Color(0.15, 0.15, 0.20, 0.6)

	style_normal.set_corner_radius_all(12)
	style_normal.set_content_margin_all(10)

	# Estilo hover — más brillante
	var style_hover := style_normal.duplicate()
	if is_unlocked:
		style_hover.bg_color = style_normal.bg_color + Color(0.05, 0.05, 0.05, 0.0)
		style_hover.shadow_size = 8
		style_hover.border_color = tier_color
	else:
		style_hover.bg_color = Color(0.06, 0.06, 0.09, 0.9)

	card.add_theme_stylebox_override("normal", style_normal)
	card.add_theme_stylebox_override("hover", style_hover)
	card.add_theme_stylebox_override("pressed", style_normal)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# Layout interno
	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# Emoji / Imagen
	var img_container := CenterContainer.new()
	vbox.add_child(img_container)

	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(72, 72)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img_container.add_child(texture_rect)

	var emoji_lbl := Label.new()
	emoji_lbl.text = str(item.get("medal_placeholder_emoji", "🏅"))
	emoji_lbl.add_theme_font_size_override("font_size", 48)
	if _font_bold:
		emoji_lbl.add_theme_font_override("font", _font_bold)
	emoji_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	img_container.add_child(emoji_lbl)

	# Cargar imagen real si existe y está desbloqueada
	var image_url: String = str(item.get("medal_image_path", ""))
	if is_unlocked and not image_url.is_empty():
		# IMPORTANTE: ocultar textura y mostrar emoji ANTES de llamar al loader,
		# porque si la imagen ya está cacheada, el callback se ejecuta de forma
		# sincrónica y las líneas posteriores revertirían los cambios del callback.
		texture_rect.hide()
		emoji_lbl.show()
		MedalImageLoader.load_medal_image(str(item["id"]), image_url, func(tex):
			if tex:
				texture_rect.texture = tex
				emoji_lbl.hide()
				texture_rect.show()
		)
	else:
		texture_rect.hide()
		emoji_lbl.show()

	# Efecto gris si bloqueada
	if not is_unlocked:
		emoji_lbl.modulate = Color(0.2, 0.2, 0.2, 0.6)

	# Nombre de la medalla
	var name_lbl := Label.new()
	name_lbl.text = "???" if not is_unlocked else str(item.get("medal_name", ""))
	name_lbl.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY if is_unlocked else COLOR_TEXT_DISABLED)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	if _font_bold:
		name_lbl.add_theme_font_override("font", _font_bold)
	vbox.add_child(name_lbl)

	# Etiqueta de tier (solo desbloqueada)
	if is_unlocked:
		var tier_lbl := Label.new()
		tier_lbl.text = tier.to_upper()
		tier_lbl.add_theme_color_override("font_color", tier_color)
		tier_lbl.add_theme_font_size_override("font_size", 9)
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if _font_bold:
			tier_lbl.add_theme_font_override("font", _font_bold)
		vbox.add_child(tier_lbl)

	# Click
	card.pressed.connect(func(): _show_medal_detail(item))

	# Hover: escala suave
	card.pivot_offset = card.custom_minimum_size / 2.0
	card.mouse_entered.connect(func():
		var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(card, "scale", Vector2(1.07, 1.07), 0.15)
	)
	card.mouse_exited.connect(func():
		var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(card, "scale", Vector2.ONE, 0.12)
	)

	_medals_grid.add_child(card)

	# Animación stagger pop-in
	card.modulate.a = 0.0
	card.scale = Vector2(0.85, 0.85)
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "modulate:a", 1.0, 0.3).set_delay(index * STAGGER_DELAY)
	tween.parallel().tween_property(card, "scale", Vector2.ONE, 0.35).set_delay(index * STAGGER_DELAY)


# ─── Detalle de Medalla ─────────────────────────────────────────────────────

func _show_medal_detail(item: Dictionary) -> void:
	var is_unlocked: bool = item.get("is_unlocked", false)
	var tier: String = str(item.get("medal_tier", "bronce"))
	var tier_color := _get_tier_color(tier)

	# Nombre
	_detail_medal_name.text = str(item.get("medal_name", "???")) if is_unlocked else "🔒 Medalla Bloqueada"
	_detail_medal_name.add_theme_color_override("font_color", tier_color if is_unlocked else COLOR_TEXT_DISABLED)

	# Descripción
	if is_unlocked:
		_detail_medal_desc.text = str(item.get("medal_description", ""))
	else:
		_detail_medal_desc.text = "Desbloquea el logro '%s' para conseguir esta medalla.\n\nRequisito: %s" % [item.get("name", ""), item.get("how_to_unlock", "")]

	# Tier
	_detail_medal_tier.text = "✦ Rareza: %s" % tier.to_upper()
	_detail_medal_tier.add_theme_color_override("font_color", tier_color)

	# Emoji / Imagen
	_detail_medal_emoji.text = str(item.get("medal_placeholder_emoji", "🏅"))
	if _font_bold:
		_detail_medal_emoji.add_theme_font_override("font", _font_bold)
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

	# Estilo del panel de detalle basado en el tier
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.97)
	style.set_border_width_all(2)
	style.border_color = tier_color * Color(1.0, 1.0, 1.0, 0.6)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(0)
	style.shadow_color = _get_tier_glow_color(tier) * Color(1.0, 1.0, 1.0, 0.5)
	style.shadow_size = 10
	_medal_detail_panel.add_theme_stylebox_override("panel", style)

	# Animación de entrada
	_medal_detail_panel.show()
	_medal_detail_panel.pivot_offset = Vector2(280, 180)
	_medal_detail_panel.scale = Vector2(0.9, 0.9)
	_medal_detail_panel.modulate.a = 0.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_medal_detail_panel, "scale", Vector2.ONE, 0.25)
	tween.parallel().tween_property(_medal_detail_panel, "modulate:a", 1.0, 0.2)


func _hide_medal_detail() -> void:
	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_medal_detail_panel, "scale", Vector2(0.9, 0.9), 0.15)
	tween.parallel().tween_property(_medal_detail_panel, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): _medal_detail_panel.hide())


# ─── Colores por Tier ────────────────────────────────────────────────────────

func _get_tier_color(tier: String) -> Color:
	match tier.to_lower():
		"bronce":
			return Color(0.72, 0.50, 0.30)
		"plata":
			return Color(0.70, 0.75, 0.82)
		"oro":
			return Color(0.95, 0.78, 0.20)
		"platino":
			return Color(0.78, 0.92, 0.98)
		_:
			return Color(0.45, 0.45, 0.50)


func _get_tier_glow_color(tier: String) -> Color:
	match tier.to_lower():
		"bronce":
			return Color(0.72, 0.50, 0.30, 0.3)
		"plata":
			return Color(0.70, 0.75, 0.82, 0.3)
		"oro":
			return Color(0.95, 0.78, 0.20, 0.35)
		"platino":
			return Color(0.78, 0.92, 0.98, 0.4)
		_:
			return Color(0.45, 0.45, 0.50, 0.2)


# ─── Tabs ────────────────────────────────────────────────────────────────────

func _on_logros_tab_pressed() -> void:
	_apply_tab_style(_logros_tab_btn, true)
	_apply_tab_style(_medallas_tab_btn, false)
	_medallas_scroll.hide()
	_logros_scroll.show()
	# Transición suave
	_logros_scroll.modulate.a = 0.0
	var tween := create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(_logros_scroll, "modulate:a", 1.0, TAB_ANIM_DURATION)


func _on_medallas_tab_pressed() -> void:
	_apply_tab_style(_medallas_tab_btn, true)
	_apply_tab_style(_logros_tab_btn, false)
	_logros_scroll.hide()
	_medallas_scroll.show()
	# Transición suave
	_medallas_scroll.modulate.a = 0.0
	var tween := create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(_medallas_scroll, "modulate:a", 1.0, TAB_ANIM_DURATION)


# ─── Cierre ──────────────────────────────────────────────────────────────────

func _on_close_pressed() -> void:
	# Animación de cierre
	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_main_panel, "scale", Vector2(0.92, 0.92), 0.2)
	tween.parallel().tween_property(_main_panel, "modulate:a", 0.0, 0.2)
	tween.parallel().tween_property(_bg_dim, "color:a", 0.0, 0.25)
	tween.tween_callback(func(): queue_free())
