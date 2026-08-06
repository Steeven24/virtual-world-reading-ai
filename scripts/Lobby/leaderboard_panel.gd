## Panel de Leaderboard para el Lobby.
## Muestra el Top 5/20 de jugadores ordenados por puntaje total.
## Se actualiza automáticamente cada 60 segundos.
## Accesible desde el HUD del lobby.
extends CanvasLayer

# ─── Nodos ───────────────────────────────────────────────────────────────────

@onready var background: ColorRect = %LeaderboardBg
@onready var panel_container: PanelContainer = %LeaderboardPanelContainer
@onready var title_label: Label = %LeaderboardTitle
@onready var close_button: Button = %LeaderboardCloseButton
@onready var top5_button: Button = %Top5Button
@onready var top20_button: Button = %Top20Button
@onready var leaderboard_list: VBoxContainer = %LeaderboardList
@onready var update_label: Label = %UpdateLabel
@onready var loading_label: Label = %LeaderboardLoading

# ─── Constantes ──────────────────────────────────────────────────────────────

const FONT_PATH := "res://fonts/PixelifySans-SemiBold.ttf"
const RANK_EMOJIS: Dictionary = {1: "🥇", 2: "🥈", 3: "🥉"}
const REFRESH_INTERVAL: float = 60.0

# ─── Estado ──────────────────────────────────────────────────────────────────

var _http: HTTPRequest
var _is_requesting: bool = false
var _current_limit: int = 5
var _refresh_timer: Timer
var _last_update_time: float = 0.0
var _font: Font

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	_font = load(FONT_PATH)
	
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_INTERVAL
	_refresh_timer.one_shot = false
	_refresh_timer.timeout.connect(_on_refresh_timeout)
	add_child(_refresh_timer)
	
	close_button.pressed.connect(_close)
	top5_button.pressed.connect(func(): _switch_view(5))
	top20_button.pressed.connect(func(): _switch_view(20))
	
	_apply_styles()
	_update_tab_buttons()
	
	# Cargar datos iniciales
	_fetch_leaderboard()
	_refresh_timer.start()


func _process(_delta: float) -> void:
	if _last_update_time > 0 and update_label:
		var elapsed: float = Time.get_unix_time_from_system() - _last_update_time
		if elapsed < 60:
			update_label.text = "Actualizado hace %ds" % int(elapsed)
		else:
			update_label.text = "Actualizado hace %dm" % int(elapsed / 60)


# ─── API ─────────────────────────────────────────────────────────────────────

func _fetch_leaderboard() -> void:
	if _is_requesting or not AuthManager.is_authenticated:
		return
	
	_is_requesting = true
	loading_label.visible = true
	
	var url := "%s/leaderboard/top?limit=%d" % [ApiConfig.BASE_URL, _current_limit]
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % AuthManager.auth_token,
	]
	
	var err := _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_is_requesting = false
		loading_label.visible = false
		push_error("[Leaderboard] Error al iniciar petición: %s" % error_string(err))


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_is_requesting = false
	loading_label.visible = false
	
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[Leaderboard] Error de red")
		return
	
	if response_code < 200 or response_code >= 300:
		push_warning("[Leaderboard] HTTP %d" % response_code)
		return
	
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("[Leaderboard] Error parseando JSON")
		return
	
	var data = json.data
	if data is Dictionary and data.has("players"):
		_render_leaderboard(data["players"])
		_last_update_time = Time.get_unix_time_from_system()


func _on_refresh_timeout() -> void:
	_fetch_leaderboard()


# ─── Renderizado ─────────────────────────────────────────────────────────────

func _render_leaderboard(players: Array) -> void:
	# Limpiar lista
	for child in leaderboard_list.get_children():
		child.queue_free()
	
	if players.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Sin datos de jugadores aún"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		if _font:
			empty_label.add_theme_font_override("font", _font)
		empty_label.add_theme_font_size_override("font_size", 14)
		leaderboard_list.add_child(empty_label)
		return
	
	for player_data in players:
		var rank: int = int(player_data.get("rank", 0))
		var display_name: String = str(player_data.get("display_name", "???"))
		var total_score: int = int(player_data.get("total_score", 0))
		var total_achievements: int = int(player_data.get("total_achievements", 0))
		var character: String = str(player_data.get("character", "male"))
		
		_add_player_row(rank, display_name, total_score, total_achievements, character)


func _add_player_row(rank: int, name: String, score: int, achievements: int, character: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 32
	
	# Fondo para top 3
	if rank <= 3:
		var bg := ColorRect.new()
		bg.color = Color(0.95, 0.85, 0.4, 0.06) if rank == 1 else Color(0.7, 0.75, 0.8, 0.04) if rank == 2 else Color(0.8, 0.5, 0.2, 0.04)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_child(bg)
	
	# Rango
	var rank_label := Label.new()
	var rank_emoji: String = RANK_EMOJIS.get(rank, "%d." % rank)
	rank_label.text = rank_emoji
	rank_label.custom_minimum_size.x = 36
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 16 if rank <= 3 else 13)
	if rank > 3:
		rank_label.add_theme_color_override("font_color", Color(0.5, 0.52, 0.6))
	if _font:
		rank_label.add_theme_font_override("font", _font)
	row.add_child(rank_label)
	
	# Icono de personaje
	var char_label := Label.new()
	char_label.text = "👩" if character == "women" else "👨"
	char_label.custom_minimum_size.x = 24
	char_label.add_theme_font_size_override("font_size", 14)
	row.add_child(char_label)
	
	# Nombre
	var name_label := Label.new()
	name_label.text = name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 14)
	var name_color := Color(0.95, 0.92, 0.7) if rank == 1 else Color(0.85, 0.88, 0.92) if rank <= 3 else Color(0.7, 0.72, 0.8)
	name_label.add_theme_color_override("font_color", name_color)
	if _font:
		name_label.add_theme_font_override("font", _font)
	row.add_child(name_label)
	
	# Puntaje
	var score_label := Label.new()
	score_label.text = "⭐ %d" % score
	score_label.custom_minimum_size.x = 70
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 13)
	score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if rank <= 3 else Color(0.6, 0.62, 0.7))
	if _font:
		score_label.add_theme_font_override("font", _font)
	row.add_child(score_label)
	
	# Logros
	var ach_label := Label.new()
	ach_label.text = "🏆 %d" % achievements
	ach_label.custom_minimum_size.x = 50
	ach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ach_label.add_theme_font_size_override("font_size", 12)
	ach_label.add_theme_color_override("font_color", Color(0.5, 0.52, 0.6))
	if _font:
		ach_label.add_theme_font_override("font", _font)
	row.add_child(ach_label)
	
	leaderboard_list.add_child(row)
	
	# Separador
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.2, 0.22, 0.3, 0.3))
	leaderboard_list.add_child(sep)


# ─── Controles de UI ────────────────────────────────────────────────────────

func _switch_view(limit: int) -> void:
	_current_limit = limit
	_update_tab_buttons()
	_fetch_leaderboard()


func _update_tab_buttons() -> void:
	# Estilizar botones activos/inactivos
	for btn in [top5_button, top20_button]:
		var is_active: bool = (btn == top5_button and _current_limit == 5) or (btn == top20_button and _current_limit == 20)
		
		var style := StyleBoxFlat.new()
		if is_active:
			style.bg_color = Color(0.39, 0.4, 0.95, 0.8)
		else:
			style.bg_color = Color(0.15, 0.16, 0.22, 0.5)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", style)
		
		var color: Color = Color.WHITE if is_active else Color(0.5, 0.52, 0.6)
		btn.add_theme_color_override("font_color", color)


func _close() -> void:
	_refresh_timer.stop()
	queue_free()


func _apply_styles() -> void:
	# Panel principal
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.13, 0.95)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.85, 0.7, 0.2, 0.3)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel_container.add_theme_stylebox_override("panel", panel_style)
	
	# Título
	if _font:
		title_label.add_theme_font_override("font", _font)
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	
	# Update label
	if _font:
		update_label.add_theme_font_override("font", _font)
	update_label.add_theme_font_size_override("font_size", 10)
	update_label.add_theme_color_override("font_color", Color(0.4, 0.42, 0.5))
	
	# Loading
	if _font:
		loading_label.add_theme_font_override("font", _font)
	loading_label.add_theme_font_size_override("font_size", 14)
	loading_label.add_theme_color_override("font_color", Color(0.5, 0.52, 0.6))
	
	# Botones tab
	for btn in [top5_button, top20_button]:
		if _font:
			btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 13)
	
	# Close button
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.15, 0.16, 0.22, 0.5)
	close_style.corner_radius_top_left = 6
	close_style.corner_radius_top_right = 6
	close_style.corner_radius_bottom_left = 6
	close_style.corner_radius_bottom_right = 6
	close_button.add_theme_stylebox_override("normal", close_style)
	close_button.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	if _font:
		close_button.add_theme_font_override("font", _font)
	close_button.add_theme_font_size_override("font_size", 16)
