## Tarjeta de perfil del jugador, al estilo de la barra de vida de un RPG.
##
## El juego no tiene salud que mostrar, así que la esquina superior izquierda se
## aprovecha para dar identidad y sensación de avance: retrato del personaje,
## nombre, un alias que se gana leyendo y una barra con el recorrido completo
## (las tipologías de la progresión, cada una con su lectura y sus tres niveles).
##
## El alias se cambia pulsando sobre él. Los alias bloqueados se ven en la lista
## con lo que falta para conseguirlos, para que sirvan de meta.
##
## El panel de objetivos (ObjectivesHUD) se coloca justo debajo de esta tarjeta
## usando get_bottom_edge().
##
## Registrar como Autoload: Project Settings → Autoload → "ProfileHUD"
extends CanvasLayer

signal perfil_actualizado
signal error_perfil(mensaje: String)

# ─── Constantes ──────────────────────────────────────────────────────────────

const FONT_BOLD_PATH := "res://fonts/fuente_juego_negrita.tres"
const FONT_REGULAR_PATH := "res://fonts/fuente_juego.tres"

## Los retratos viven como animaciones "profile" y "profile_women" dentro de la
## escena del jugador, así que se sacan de ahí en vez de duplicar las regiones.
const PLAYER_SCENE := "res://scenes/Player/player.tscn"
const ANIM_RETRATO := "profile"

const MARGEN: int = 14
const ANCHO_PANEL: int = 296
const LADO_RETRATO: int = 64
const ANIM_DURACION: float = 0.22
const INTERVALO_REFRESCO: float = 0.6

## Una tipología cuenta como cuatro pasos: leer el texto y superar los niveles
## literal, inferencial y crítico. Así la barra se mueve en cada escenario y no
## solo al terminar una tipología entera.
const PASOS_POR_TIPOLOGIA: int = 4

const COLOR_ORO := Color(0.93, 0.79, 0.28)
const COLOR_FONDO := Color(0.06, 0.06, 0.12, 0.94)
const COLOR_BORDE := Color(0.85, 0.75, 0.3, 0.55)
const COLOR_NOMBRE := Color(0.97, 0.93, 0.75)
const COLOR_TENUE := Color(0.62, 0.64, 0.72)
const COLOR_BARRA := Color(0.36, 0.78, 0.52)
const COLOR_BARRA_FONDO := Color(0.12, 0.13, 0.2)

## Mismas escenas que ObjectivesHUD: pantallas completas con su propia interfaz.
const ESCENAS_OCULTAS: Array[String] = [
	"res://scenes/UI/login_screen.tscn",
	"res://scenes/UI/character_select.tscn",
	"res://scenes/UI/change_password_screen.tscn",
	"res://scenes/UI/session_results.tscn",
	"res://scenes/Challenges/Templates/quiz_challenge.tscn",
]

## Alias disponibles, ordenados por lecturas completadas necesarias.
## El primero siempre está desbloqueado y es el que se usa por defecto.
const ALIAS: Array[Dictionary] = [
	{"id": "intuicion", "nombre": "Intuición", "lecturas": 0},
	{"id": "interes", "nombre": "Interés", "lecturas": 1},
	{"id": "curiosidad", "nombre": "Curiosidad", "lecturas": 3},
	{"id": "comprension", "nombre": "Comprensión", "lecturas": 5},
	{"id": "perspectiva", "nombre": "Perspectiva", "lecturas": 8},
	{"id": "perspicacia", "nombre": "Perspicacia", "lecturas": 12},
	{"id": "sabiduria", "nombre": "Sabiduría", "lecturas": 16},
	{"id": "conocimiento", "nombre": "Conocimiento", "lecturas": 20},
]

const CONFIG_PATH := "user://progress.cfg"
const CONFIG_SECCION := "perfil"

# ─── Nodos ───────────────────────────────────────────────────────────────────

var _panel: PanelContainer = null
var _retrato: TextureRect = null
var _nombre: Label = null
var _boton_alias: Button = null
var _barra: ProgressBar = null
var _estilo_relleno: StyleBoxFlat = null
var _porcentaje: Label = null
var _lista_alias: PanelContainer = null

var _font_bold: Font = null
var _font_regular: Font = null
var _frames_jugador: SpriteFrames = null

# ─── Estado ──────────────────────────────────────────────────────────────────

var _visible_objetivo: bool = false
var _tween_visibilidad: Tween = null
var _tween_barra: Tween = null
var _personaje_pintado: String = ""
var _usuario_actual: int = -1
var _alias_elegido: String = ""
var _hay_alias_nuevo: bool = false
var vitrina: Array = []
var perfil_cargado: bool = false
var guardando_perfil: bool = false
var _perfil_http: HTTPRequest
var _alias_local: bool = false
var _pendiente_perfil: bool = false
var _vitrina_pendiente: bool = false
var _revision_perfil: int = 0
var _revision_enviada: int = 0
var _recuperando_perfil: bool = false
var _operacion_perfil: String = ""
var _usuario_peticion: int = -1

# ─── Ciclo de vida ───────────────────────────────────────────────────────────

func _ready() -> void:
	# Por encima de ObjectivesHUD (20) para que la lista de alias lo tape.
	layer = 21
	# Coordenadas de ventana, no del viewport 192x108 del juego.
	follow_viewport_enabled = false

	_font_bold = load(FONT_BOLD_PATH) if ResourceLoader.exists(FONT_BOLD_PATH) else null
	_font_regular = load(FONT_REGULAR_PATH) if ResourceLoader.exists(FONT_REGULAR_PATH) else null
	if SceneManager:
		SceneManager.ensure_fallbacks(_font_bold)
		SceneManager.ensure_fallbacks(_font_regular)

	_perfil_http = HTTPRequest.new()
	_perfil_http.timeout = 10.0
	add_child(_perfil_http)
	_perfil_http.request_completed.connect(_perfil_recibido)
	AuthManager.progress_loaded.connect(func(_datos): _cargar_preferencias())
	AuthManager.logged_out.connect(_limpiar_perfil)
	_construir_ui()
	_panel.modulate.a = 0.0
	_panel.visible = false

	var temporizador := Timer.new()
	temporizador.wait_time = INTERVALO_REFRESCO
	temporizador.autostart = true
	temporizador.timeout.connect(_refrescar)
	add_child(temporizador)

	GameSession.session_completed_with_data.connect(_on_lectura_completada)
	get_tree().node_added.connect(_on_node_added)
	_refrescar()


func _on_node_added(nodo: Node) -> void:
	if nodo.get_parent() == get_tree().root:
		call_deferred("_refrescar")


## La lista de alias se cierra con Escape o pulsando fuera de ella.
func _input(event: InputEvent) -> void:
	if _lista_alias == null:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cerrar_lista_alias()
		get_viewport().set_input_as_handled()
		return

	var clic := event as InputEventMouseButton
	if clic and clic.pressed:
		var dentro_lista := _lista_alias.get_global_rect().has_point(clic.position)
		var dentro_boton := _boton_alias.get_global_rect().has_point(clic.position)
		if not dentro_lista and not dentro_boton:
			_cerrar_lista_alias()

# ─── API pública ─────────────────────────────────────────────────────────────

## Borde inferior de la tarjeta en coordenadas de ventana, o -1 si no se ve.
## ObjectivesHUD lo usa para colocarse debajo.
func get_bottom_edge() -> float:
	if not _visible_objetivo:
		return -1.0
	return _panel.position.y + _panel.size.y


## Alias que el jugador lleva puesto ahora mismo.
func get_alias_name() -> String:
	var alias := _alias_por_id(_alias_elegido)
	# Un alias guardado puede quedar fuera de alcance si el progreso se reinicia
	# (por ejemplo, al probar desde el editor): se muestra el de partida.
	if alias.is_empty() or not _esta_desbloqueado(alias):
		alias = ALIAS[0]
	return str(alias["nombre"])

# ─── Construcción de la interfaz ─────────────────────────────────────────────

func _construir_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(ANCHO_PANEL, 0)
	_panel.position = Vector2(MARGEN, MARGEN)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	# La flecha del borde de GuiaDestino no se mete debajo de este panel.
	_panel.add_to_group("zona_hud")
	_panel.add_theme_stylebox_override("panel", _estilo_panel())
	add_child(_panel)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)
	_panel.add_child(fila)

	# Marco del retrato: un recuadro dorado propio para que la foto se lea como
	# avatar y no como un sprite suelto encima del panel.
	var marco := PanelContainer.new()
	var estilo_marco := StyleBoxFlat.new()
	estilo_marco.bg_color = Color(0.16, 0.17, 0.27)
	estilo_marco.set_corner_radius_all(8)
	estilo_marco.set_border_width_all(2)
	estilo_marco.border_color = COLOR_ORO
	estilo_marco.set_content_margin_all(3)
	marco.add_theme_stylebox_override("panel", estilo_marco)
	marco.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(marco)

	_retrato = TextureRect.new()
	_retrato.custom_minimum_size = Vector2(LADO_RETRATO, LADO_RETRATO)
	_retrato.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_retrato.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Pixel art: sin filtrado para que no se emborrone al ampliarlo.
	_retrato.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	marco.add_child(_retrato)

	var columna := VBoxContainer.new()
	columna.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columna.alignment = BoxContainer.ALIGNMENT_CENTER
	columna.add_theme_constant_override("separation", 2)
	fila.add_child(columna)

	_nombre = Label.new()
	_nombre.add_theme_color_override("font_color", COLOR_NOMBRE)
	_nombre.add_theme_font_size_override("font_size", 16)
	_nombre.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_nombre.clip_text = true
	if _font_bold:
		_nombre.add_theme_font_override("font", _font_bold)
	columna.add_child(_nombre)

	_boton_alias = Button.new()
	_boton_alias.flat = false
	_boton_alias.custom_minimum_size.y = 30
	# Sin foco: E y Espacio son ui_accept y abrirían la lista al interactuar
	# con un NPC.
	_boton_alias.focus_mode = Control.FOCUS_NONE
	_boton_alias.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_boton_alias.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_boton_alias.clip_text = true
	_boton_alias.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_boton_alias.tooltip_text = "Cambiar alias"
	_boton_alias.add_theme_font_size_override("font_size", 13)
	_boton_alias.add_theme_color_override("font_color", COLOR_ORO)
	_boton_alias.add_theme_color_override("font_hover_color", COLOR_NOMBRE)
	_boton_alias.add_theme_color_override("font_pressed_color", COLOR_NOMBRE)
	for estado in ["normal", "hover", "pressed", "focus"]:
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = Color(0.26, 0.22, 0.10) if estado == "normal" else Color(0.38, 0.31, 0.12)
		estilo.border_color = COLOR_ORO
		estilo.set_border_width_all(1)
		estilo.set_corner_radius_all(5)
		estilo.set_content_margin_all(5)
		_boton_alias.add_theme_stylebox_override(estado, estilo)
	if _font_regular:
		_boton_alias.add_theme_font_override("font", _font_regular)
	_boton_alias.pressed.connect(_alternar_lista_alias)
	columna.add_child(_boton_alias)

	var fila_barra := HBoxContainer.new()
	fila_barra.add_theme_constant_override("separation", 8)
	columna.add_child(fila_barra)

	_barra = ProgressBar.new()
	_barra.show_percentage = false
	_barra.min_value = 0.0
	_barra.max_value = 1.0
	_barra.step = 0.0
	_barra.custom_minimum_size = Vector2(0, 12)
	_barra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_barra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_barra.mouse_filter = Control.MOUSE_FILTER_PASS

	var fondo_barra := StyleBoxFlat.new()
	fondo_barra.bg_color = COLOR_BARRA_FONDO
	fondo_barra.set_corner_radius_all(4)
	fondo_barra.set_border_width_all(1)
	fondo_barra.border_color = Color(0, 0, 0, 0.6)
	_barra.add_theme_stylebox_override("background", fondo_barra)

	_estilo_relleno = StyleBoxFlat.new()
	_estilo_relleno.bg_color = COLOR_BARRA
	_estilo_relleno.set_corner_radius_all(4)
	_barra.add_theme_stylebox_override("fill", _estilo_relleno)
	fila_barra.add_child(_barra)

	_porcentaje = Label.new()
	_porcentaje.custom_minimum_size = Vector2(38, 0)
	_porcentaje.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_porcentaje.add_theme_color_override("font_color", COLOR_TENUE)
	_porcentaje.add_theme_font_size_override("font_size", 12)
	if _font_bold:
		_porcentaje.add_theme_font_override("font", _font_bold)
	fila_barra.add_child(_porcentaje)


func _estilo_panel() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_FONDO
	estilo.set_corner_radius_all(12)
	estilo.set_border_width_all(2)
	estilo.border_color = COLOR_BORDE
	estilo.set_content_margin_all(10)
	estilo.shadow_color = Color(0, 0, 0, 0.45)
	estilo.shadow_size = 8
	return estilo

# ─── Refresco ────────────────────────────────────────────────────────────────

func _refrescar() -> void:
	var mostrar := _debe_mostrarse()
	if mostrar != _visible_objetivo:
		_visible_objetivo = mostrar
		_animar_visibilidad(mostrar)
		if not mostrar:
			_cerrar_lista_alias()

	if not mostrar:
		return

	var usuario := AuthManager.get_user_id()
	if usuario != _usuario_actual:
		_usuario_actual = usuario
		_cargar_preferencias()

	_pintar_retrato()
	_nombre.text = AuthManager.get_display_name()
	_pintar_alias()
	_pintar_progreso()


func _debe_mostrarse() -> bool:
	if SceneManager.is_ui_open:
		return false
	var escena := get_tree().current_scene
	if escena == null:
		return false
	return not (escena.scene_file_path in ESCENAS_OCULTAS)


func _animar_visibilidad(mostrar: bool) -> void:
	if _tween_visibilidad and _tween_visibilidad.is_valid():
		_tween_visibilidad.kill()

	if mostrar:
		_panel.visible = true
		_panel.reset_size()

	_tween_visibilidad = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween_visibilidad.tween_property(_panel, "modulate:a", 1.0 if mostrar else 0.0, ANIM_DURACION)
	if not mostrar:
		_tween_visibilidad.tween_callback(func(): _panel.visible = false)


func _pintar_retrato() -> void:
	var personaje: String = GameSession.selected_character
	if personaje == _personaje_pintado:
		return

	if _frames_jugador == null:
		_frames_jugador = _cargar_frames_jugador()
	if _frames_jugador == null:
		return

	var animacion := ANIM_RETRATO + GameSession.anim_suffix
	if not _frames_jugador.has_animation(animacion):
		animacion = ANIM_RETRATO
	if not _frames_jugador.has_animation(animacion) or _frames_jugador.get_frame_count(animacion) == 0:
		push_warning("[ProfileHUD] Falta la animación '%s' en %s" % [animacion, PLAYER_SCENE])
		return

	_retrato.texture = _frames_jugador.get_frame_texture(animacion, 0)
	_personaje_pintado = personaje


## Instanciar sin añadir al árbol no ejecuta _ready del jugador (ni toca la
## cámara): solo se coge el SpriteFrames y se libera.
func _cargar_frames_jugador() -> SpriteFrames:
	var escena := load(PLAYER_SCENE) as PackedScene
	if escena == null:
		return null
	var jugador := escena.instantiate()
	var sprite := jugador.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var frames: SpriteFrames = sprite.sprite_frames if sprite else null
	jugador.free()
	return frames


func _pintar_alias() -> void:
	var texto := "« %s »  ▾" % get_alias_name()
	if _hay_alias_nuevo:
		texto = "▾ ● nuevo · « %s »" % get_alias_name()
	_boton_alias.text = texto

# ─── Progreso ────────────────────────────────────────────────────────────────

func _pintar_progreso() -> void:
	var datos := _calcular_progreso()
	var fraccion: float = datos["fraccion"]

	_porcentaje.text = "%d%%" % roundi(fraccion * 100.0)
	_barra.tooltip_text = "Recorrido: %d de %d pasos\nTipologías completadas: %d/%d" % [
		datos["hechos"], datos["total"], datos["tipologias"], ProgressionManager.DIFFICULTY_ORDER.size()
	]

	if is_equal_approx(_barra.value, fraccion):
		return

	# Solo se celebra cuando sube; al cambiar de usuario puede bajar y ahí
	# basta con colocarla sin más.
	var sube := fraccion > _barra.value
	if _tween_barra and _tween_barra.is_valid():
		_tween_barra.kill()
	_tween_barra = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween_barra.tween_property(_barra, "value", fraccion, 0.6)
	if sube:
		_estilo_relleno.bg_color = COLOR_ORO
		_tween_barra.parallel().tween_property(_estilo_relleno, "bg_color", COLOR_BARRA, 0.9)


## Cuenta los pasos hechos del recorrido completo. Las tipologías terminadas
## valen sus cuatro pasos; la que está en curso suma la lectura (si ya se leyó)
## y los niveles superados.
func _calcular_progreso() -> Dictionary:
	var tipologias: Array[String] = ProgressionManager.DIFFICULTY_ORDER
	var completadas: Array = GameSession.score_data.get("typologies_completed", [])
	var total := tipologias.size() * PASOS_POR_TIPOLOGIA

	var hechos := 0
	var num_completadas := 0
	for tipologia in tipologias:
		if tipologia in completadas:
			hechos += PASOS_POR_TIPOLOGIA
			num_completadas += 1

	var en_curso := ""
	var nivel := 0
	var lectura_hecha := false
	var en_progresion := GameSession.current_progression_typology()
	if not en_progresion.is_empty():
		en_curso = en_progresion
		nivel = GameSession.current_level_index
		lectura_hecha = GameSession.reading_end_time > 0.0
	elif ReadingProgressManager.has_active_reading():
		# En el lobby la sesión no está activa, pero la lectura a medias sigue
		# guardada: el avance hecho no debe desaparecer de la barra.
		var activa: Dictionary = ReadingProgressManager.get_active_data()
		en_curso = str(activa.get("typology", ""))
		nivel = int(activa.get("current_level_index", 0))
		lectura_hecha = bool(activa.get("reading_completed", false))

	# Repetir una tipología ya completada no suma: ya cuenta entera.
	if en_curso in tipologias and not (en_curso in completadas):
		var pasos_en_curso := clampi(nivel, 0, GameSession.LEVELS.size())
		if lectura_hecha:
			pasos_en_curso += 1
		hechos += mini(pasos_en_curso, PASOS_POR_TIPOLOGIA - 1)

	return {
		"hechos": hechos,
		"total": total,
		"tipologias": num_completadas,
		"fraccion": float(hechos) / float(total) if total > 0 else 0.0,
	}

# ─── Alias ───────────────────────────────────────────────────────────────────

func _lecturas_completadas() -> int:
	return int(GameSession.score_data.get("sessions_completed", 0))


func _alias_por_id(id: String) -> Dictionary:
	for alias in ALIAS:
		if alias["id"] == id:
			return alias
	return {}


func _esta_desbloqueado(alias: Dictionary) -> bool:
	return _lecturas_completadas() >= int(alias["lecturas"])


func _alternar_lista_alias() -> void:
	if _lista_alias:
		_cerrar_lista_alias()
	else:
		_abrir_lista_alias()


func _abrir_lista_alias() -> void:
	if _hay_alias_nuevo:
		_hay_alias_nuevo = false
		_guardar_preferencia("nuevo", false)
		_pintar_alias()

	_lista_alias = PanelContainer.new()
	_lista_alias.custom_minimum_size = Vector2(ANCHO_PANEL, 0)
	_lista_alias.add_theme_stylebox_override("panel", _estilo_panel())
	add_child(_lista_alias)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_lista_alias.add_child(vbox)

	var titulo := Label.new()
	titulo.text = "🏷 ELIGE TU ALIAS"
	titulo.add_theme_color_override("font_color", COLOR_ORO)
	titulo.add_theme_font_size_override("font_size", 14)
	if _font_bold:
		titulo.add_theme_font_override("font", _font_bold)
	vbox.add_child(titulo)

	var subtitulo := Label.new()
	subtitulo.text = "Lecturas completadas: %d" % _lecturas_completadas()
	subtitulo.add_theme_color_override("font_color", COLOR_TENUE)
	subtitulo.add_theme_font_size_override("font_size", 11)
	if _font_regular:
		subtitulo.add_theme_font_override("font", _font_regular)
	vbox.add_child(subtitulo)

	vbox.add_child(HSeparator.new())

	for alias in ALIAS:
		vbox.add_child(_crear_opcion_alias(alias))

	# Justo debajo de la tarjeta, encima del panel de objetivos.
	_lista_alias.position = Vector2(_panel.position.x, _panel.position.y + _panel.size.y + 6)
	_lista_alias.reset_size()


func _crear_opcion_alias(alias: Dictionary) -> Button:
	var desbloqueado := _esta_desbloqueado(alias)
	var elegido: bool = alias["id"] == _alias_elegido

	var opcion := Button.new()
	opcion.focus_mode = Control.FOCUS_NONE
	opcion.alignment = HORIZONTAL_ALIGNMENT_LEFT
	opcion.add_theme_font_size_override("font_size", 13)

	var fuente := _font_bold if elegido else _font_regular
	if fuente:
		opcion.add_theme_font_override("font", fuente)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.08) if elegido else Color(0, 0, 0, 0)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 3
	normal.content_margin_bottom = 3
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.93, 0.79, 0.28, 0.18)
	opcion.add_theme_stylebox_override("normal", normal)
	opcion.add_theme_stylebox_override("hover", hover)
	opcion.add_theme_stylebox_override("pressed", hover)
	opcion.add_theme_stylebox_override("disabled", normal)

	if desbloqueado:
		opcion.text = ("✓  %s" if elegido else "     %s") % alias["nombre"]
		opcion.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		opcion.add_theme_color_override("font_color", COLOR_ORO if elegido else COLOR_NOMBRE)
		opcion.add_theme_color_override("font_hover_color", COLOR_ORO)
		opcion.pressed.connect(_elegir_alias.bind(str(alias["id"])))
	else:
		var faltan: int = int(alias["lecturas"]) - _lecturas_completadas()
		opcion.text = "🔒  %s  ·  %d %s más" % [
			alias["nombre"], faltan, "lectura" if faltan == 1 else "lecturas"
		]
		opcion.disabled = true
		opcion.add_theme_color_override("font_disabled_color", Color(COLOR_TENUE, 0.7))

	return opcion


func _elegir_alias(id: String) -> void:
	_alias_elegido = id
	_guardar_preferencia("alias", id)
	_alias_local = true
	_marcar_perfil_pendiente()
	guardar_perfil()
	_pintar_alias()
	_cerrar_lista_alias()


func _cerrar_lista_alias() -> void:
	if _lista_alias:
		_lista_alias.queue_free()
		_lista_alias = null


## Al terminar una lectura se comprueba si con ella se llega a algún alias.
## Se hace aquí y no sondeando el contador porque al iniciar sesión el
## contador salta de 0 al valor guardado y lanzaría avisos de alias viejos.
func _on_lectura_completada(_tipologia: String, _puntos: int, _herramientas: Dictionary) -> void:
	var lecturas := _lecturas_completadas()
	for alias in ALIAS:
		if int(alias["lecturas"]) != lecturas or lecturas == 0:
			continue
		_hay_alias_nuevo = true
		_guardar_preferencia("nuevo", true)
		AchievementToast.show_notice(
			"¡Nuevo alias desbloqueado!",
			str(alias["nombre"]),
			"🏷"
		)

# ─── Persistencia ────────────────────────────────────────────────────────────

## Cada cuenta guarda su propio alias: en un mismo equipo pueden jugar varios
## alumnos y no deben heredar el del anterior.
func _clave(nombre: String) -> String:
	return "%s_%d" % [nombre, _usuario_actual]


func _cargar_preferencias() -> void:
	# Una carga nueva reemplaza la petición anterior; lo pendiente ya está en disco.
	_perfil_http.cancel_request()
	_operacion_perfil = ""
	guardando_perfil = false
	_recuperando_perfil = false
	_usuario_actual = AuthManager.get_user_id()
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	_alias_local = cfg.has_section_key(CONFIG_SECCION, _clave("alias"))
	_pendiente_perfil = bool(cfg.get_value(CONFIG_SECCION, _clave("pendiente"), false))
	vitrina = cfg.get_value(CONFIG_SECCION, _clave("vitrina"), [])
	_vitrina_pendiente = bool(cfg.get_value(CONFIG_SECCION, _clave("vitrina_pendiente"), false))
	perfil_cargado = false
	_alias_elegido = str(cfg.get_value(CONFIG_SECCION, _clave("alias"), ALIAS[0]["id"]))
	_hay_alias_nuevo = bool(cfg.get_value(CONFIG_SECCION, _clave("nuevo"), false))
	if _alias_por_id(_alias_elegido).is_empty():
		_alias_elegido = ALIAS[0]["id"]
	_cerrar_lista_alias()
	_peticion_perfil("GET")


func _guardar_preferencia(nombre: String, valor: Variant) -> void:
	var cfg := ConfigFile.new()
	# Se carga antes de escribir para no pisar el tutorial, las guías ni el
	# plegado de objetivos, que comparten archivo.
	cfg.load(CONFIG_PATH)
	cfg.set_value(CONFIG_SECCION, _clave(nombre), valor)
	cfg.save(CONFIG_PATH)


func _limpiar_perfil() -> void:
	_perfil_http.cancel_request()
	_operacion_perfil = ""
	guardando_perfil = false
	_recuperando_perfil = false
	perfil_cargado = false
	vitrina = []
	_usuario_actual = -1
	_alias_elegido = ""


func tiene_en_vitrina(tipo: String, id: String) -> bool:
	for pieza in vitrina:
		if pieza.get("tipo") == tipo and pieza.get("id") == id:
			return true
	return false


func cambiar_vitrina(tipo: String, id: String) -> void:
	if not perfil_cargado or guardando_perfil:
		return
	var nueva := vitrina.duplicate(true)
	if tiene_en_vitrina(tipo, id):
		for indice in range(nueva.size() - 1, -1, -1):
			if nueva[indice].get("tipo") == tipo and nueva[indice].get("id") == id:
				nueva.remove_at(indice)
	elif nueva.size() < 3:
		nueva.append({"tipo": tipo, "id": id})
	else:
		return
	vitrina = nueva
	_vitrina_pendiente = true
	_guardar_preferencia("vitrina_pendiente", true)
	_guardar_preferencia("vitrina", vitrina)
	_marcar_perfil_pendiente()
	guardar_perfil()
	perfil_actualizado.emit()


func _marcar_perfil_pendiente() -> void:
	_revision_perfil += 1
	_pendiente_perfil = true
	_guardar_preferencia("pendiente", true)


func guardar_perfil() -> void:
	# El GET previo evita borrar una vitrina del servidor al elegir el alias.
	if not perfil_cargado:
		_peticion_perfil("GET")
	else:
		_peticion_perfil("PUT")


func _peticion_perfil(metodo: String) -> void:
	if not AuthManager.is_authenticated or not _operacion_perfil.is_empty():
		return
	_usuario_peticion = AuthManager.get_user_id()
	_operacion_perfil = metodo
	guardando_perfil = metodo == "PUT"
	_revision_enviada = _revision_perfil
	var cabeceras := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + AuthManager.auth_token])
	var cuerpo := JSON.stringify({"alias": _alias_elegido if _alias_local else null, "vitrina": vitrina}) if metodo == "PUT" else ""
	var error := _perfil_http.request(ApiConfig.BASE_URL + "/progress/profile", cabeceras, HTTPClient.METHOD_PUT if metodo == "PUT" else HTTPClient.METHOD_GET, cuerpo)
	if error != OK:
		_operacion_perfil = ""
		guardando_perfil = false
		error_perfil.emit("No se pudo conectar. Se reintentará al cargar el progreso.")


func _perfil_recibido(resultado: int, codigo: int, _cabeceras: PackedStringArray, cuerpo: PackedByteArray) -> void:
	var operacion := _operacion_perfil
	_operacion_perfil = ""
	guardando_perfil = false
	if _usuario_peticion != AuthManager.get_user_id():
		return
	var datos = JSON.parse_string(cuerpo.get_string_from_utf8())
	if resultado != HTTPRequest.RESULT_SUCCESS or codigo < 200 or codigo >= 300 or not datos is Dictionary:
		var mensaje := "No se pudo sincronizar el perfil. Se reintentará al cargar el progreso."
		if datos is Dictionary and datos.has("detail"):
			mensaje = str(datos["detail"])
		_boton_alias.tooltip_text = "Cambiar alias\n" + mensaje
		# Un 422 no es un fallo de red: el servidor dice que lo que guardamos ya
		# no vale (una pieza que dejó de estar desbloqueada, un catálogo que
		# cambió, un progreso corregido). Reintentarlo no lo arregla nunca y la
		# copia local se queda bloqueando la vitrina en 3/3, así que se tira y se
		# adopta la del servidor, que ya filtra lo que no corresponde.
		if codigo == 422 and operacion == "PUT" and not _recuperando_perfil:
			vitrina = []
			_vitrina_pendiente = false
			_pendiente_perfil = false
			_guardar_preferencia("vitrina", vitrina)
			_guardar_preferencia("vitrina_pendiente", false)
			_guardar_preferencia("pendiente", false)
			_recuperando_perfil = true
			_peticion_perfil("GET")
		perfil_actualizado.emit()
		error_perfil.emit(mensaje)
		return
	_boton_alias.tooltip_text = "Cambiar alias"
	perfil_cargado = true
	if operacion == "GET":
		if not _alias_local and datos.get("alias") != null:
			_alias_elegido = str(datos["alias"])
			_alias_local = true
			_guardar_preferencia("alias", _alias_elegido)
		if not _vitrina_pendiente:
			vitrina = datos.get("vitrina", [])
			_guardar_preferencia("vitrina", vitrina)
		# Una preferencia local explícita prevalece incluso si se eligió sin red,
		# salvo mientras nos recuperamos de un rechazo: ahí volver a enviarla
		# sería un ciclo PUT→422→GET→PUT sin salida.
		if _recuperando_perfil:
			_recuperando_perfil = false
		elif _pendiente_perfil or _alias_local and datos.get("alias") != _alias_elegido:
			guardar_perfil()
	elif _revision_enviada == _revision_perfil:
		_pendiente_perfil = false
		_vitrina_pendiente = false
		_guardar_preferencia("vitrina_pendiente", false)
		_guardar_preferencia("pendiente", false)
	else:
		guardar_perfil()
	_pintar_alias()
	perfil_actualizado.emit()
