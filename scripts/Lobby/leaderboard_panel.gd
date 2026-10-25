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

const FONT_PATH := "res://fonts/fuente_juego.tres"
const RANK_EMOJIS: Dictionary = {1: "🥇", 2: "🥈", 3: "🥉"}
const REFRESH_INTERVAL: float = 60.0

# ─── Estado ──────────────────────────────────────────────────────────────────

var _http: HTTPRequest
var _is_requesting: bool = false
var _current_limit: int = 5
var _refresh_timer: Timer
var _last_update_time: float = 0.0
var _frames_retratos: SpriteFrames
var _font: Font

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	Sonido.efecto("abrir")
	_frames_retratos = ProfileHUD._cargar_frames_jugador()
	_font = load(FONT_PATH)
	if SceneManager and _font:
		SceneManager.ensure_fallbacks(_font)
	
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
		
		_add_player_row(rank, display_name, total_score, total_achievements, character, player_data)


func _etiqueta(texto: String, tamano: int = 14) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", tamano)
	if _font:
		etiqueta.add_theme_font_override("font", _font)
	return etiqueta


func _marco(color: Color) -> PanelContainer:
	var marco := PanelContainer.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.12, 0.13, 0.20)
	estilo.border_color = color
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(6)
	estilo.set_content_margin_all(4)
	marco.add_theme_stylebox_override("panel", estilo)
	return marco


func _add_player_row(rank: int, nombre: String, puntos: int, logros: int, personaje: String, datos: Dictionary = {}) -> void:
	var tarjeta := _marco(Color(0.35, 0.32, 0.18, 0.6))
	tarjeta.custom_minimum_size.y = 112
	leaderboard_list.add_child(tarjeta)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)
	tarjeta.add_child(fila)
	var rango := _etiqueta(RANK_EMOJIS.get(rank, "%d." % rank), 22)
	rango.custom_minimum_size.x = 36
	fila.add_child(rango)
	var marco := _marco(ProfileHUD.COLOR_ORO)
	marco.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(marco)
	var retrato := TextureRect.new()
	retrato.name = "Retrato"
	retrato.custom_minimum_size = Vector2(64, 64)
	retrato.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	retrato.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	retrato.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var animacion := "profile_women" if personaje.to_lower() in ["women", "female", "woman", "girl", "f", "mujer"] else "profile"
	if _frames_retratos and _frames_retratos.has_animation(animacion) and _frames_retratos.get_frame_count(animacion) > 0:
		retrato.texture = _frames_retratos.get_frame_texture(animacion, 0)
	marco.add_child(retrato)
	var columna := VBoxContainer.new()
	columna.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(columna)
	var cabecera := HBoxContainer.new()
	columna.add_child(cabecera)
	var etiqueta_nombre := _etiqueta(nombre, 17)
	etiqueta_nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	etiqueta_nombre.clip_text = true
	cabecera.add_child(etiqueta_nombre)
	var puntuacion := _etiqueta("⭐ %d" % puntos, 16)
	puntuacion.add_theme_color_override("font_color", ProfileHUD.COLOR_ORO)
	cabecera.add_child(puntuacion)
	var nombre_alias = datos.get("alias")
	var alias := _etiqueta("« %s »" % (str(nombre_alias) if nombre_alias else "Intuición"), 14)
	alias.name = "Alias"
	alias.clip_text = true
	alias.add_theme_color_override("font_color", ProfileHUD.COLOR_ORO)
	columna.add_child(alias)
	var huecos := HBoxContainer.new()
	huecos.name = "Vitrina"
	huecos.add_theme_constant_override("separation", 8)
	columna.add_child(huecos)
	var piezas = datos.get("vitrina", [])
	if not piezas is Array:
		piezas = []
	for indice in range(3):
		_agregar_hueco(huecos, piezas[indice] if indice < piezas.size() else {})
	var cantidad := _etiqueta("🏆 %d" % logros, 12)
	cantidad.tooltip_text = "Logros conseguidos"
	cantidad.add_theme_color_override("font_color", Color(0.62, 0.64, 0.72))
	huecos.add_child(cantidad)


func _agregar_hueco(fila: HBoxContainer, pieza: Dictionary) -> void:
	var marco := _marco(_color_metal(str(pieza.get("tier", ""))))
	marco.custom_minimum_size = Vector2(42, 42)
	marco.tooltip_text = str(pieza.get("nombre", "Hueco libre de la vitrina"))
	fila.add_child(marco)
	var centro := CenterContainer.new()
	marco.add_child(centro)
	# Un hueco libre se dibuja como un rombo tenue, no como un punto suelto: así
	# se lee como un sitio por llenar y no como un carácter perdido.
	var icono := _etiqueta(str(pieza.get("emoji", "🏅")) if not pieza.is_empty() else "◇", 24)
	if pieza.is_empty():
		icono.add_theme_color_override("font_color", Color(0.45, 0.47, 0.56))
	centro.add_child(icono)
	var imagen = pieza.get("imagen")
	if imagen is String and not imagen.is_empty():
		var textura := TextureRect.new()
		textura.custom_minimum_size = Vector2(30, 30)
		textura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		textura.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		textura.hide()
		centro.add_child(textura)
		var url: String = ApiConfig.BASE_URL + imagen if imagen.begins_with("/") else imagen
		MedalImageLoader.load_medal_image(str(pieza.get("tipo", "")) + "_" + str(pieza.get("id", "")), url, func(tex):
			if tex and is_instance_valid(textura):
				textura.texture = tex
				textura.show()
				icono.hide()
		)


func _color_metal(tier: String) -> Color:
	# Mismo criterio que el panel de medallas para reconocer el metal en ambas vistas.
	match tier.to_lower():
		"bronce": return Color(0.72, 0.50, 0.30)
		"plata": return Color(0.70, 0.75, 0.82)
		"oro": return Color(0.95, 0.78, 0.20)
		"platino": return Color(0.78, 0.92, 0.98)
		_: return Color(0.45, 0.45, 0.50)


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
	Sonido.efecto("cerrar")
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
