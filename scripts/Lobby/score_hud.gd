## HUD de puntuación para el Lobby.
## Muestra la puntuación total, botón para ver logros y botón de menú (⚙️)
## con opción de cerrar sesión.
## Se conecta a GameSession.score_changed para actualizarse automáticamente.
extends CanvasLayer

@onready var score_label: Label = %ScoreLabel
@onready var achievements_panel: PanelContainer = %AchievementsPanel
@onready var achievements_list: VBoxContainer = %AchievementsList
@onready var toggle_button: Button = %ToggleButton
@onready var close_button: Button = %CloseButton
@onready var leaderboard_button: Button = %LeaderboardButton
@onready var menu_button: Button = %MenuButton
@onready var menu_panel: PanelContainer = %MenuPanel
@onready var user_name_label: Label = %UserNameLabel
@onready var user_email_label: Label = %UserEmailLabel
@onready var logout_button: Button = %LogoutButton
@onready var close_menu_button: Button = %CloseMenuButton

const FONT_PATH := "res://fonts/fuente_juego.tres"
const LOGIN_SCENE := "res://scenes/UI/login_screen.tscn"

## Definición de logros con sus nombres para mostrar.
const ACHIEVEMENT_NAMES: Dictionary = {
	"first_reading": "📖 Primera lectura",
	"explorer": "🏅 Explorador",
	"perfectionist": "🎯 Perfeccionista",
	"avid_reader": "📚 Lector ávido",
	"star_literal": "⭐ Estrella literal",
	"star_inferencial": "⭐⭐ Estrella inferencial",
	"star_critico": "⭐⭐⭐ Estrella crítica",
	"improvement": "📈 En mejora",
	"centurion": "💯 Centurión",
	"half_millennium": "🏆 Medio milenio",
}


func _ready() -> void:
	achievements_panel.visible = false
	menu_panel.visible = false
	_update_score(GameSession.get_total_score())
	GameSession.score_changed.connect(_update_score)
	GameSession.achievement_unlocked.connect(_on_achievement_unlocked)
	ProgressionManager.progression_changed.connect(_on_progression_changed)
	toggle_button.pressed.connect(_toggle_achievements)
	close_button.pressed.connect(_toggle_achievements)
	leaderboard_button.pressed.connect(_show_leaderboard)
	menu_button.pressed.connect(_toggle_menu)
	close_menu_button.pressed.connect(_toggle_menu)
	logout_button.pressed.connect(_on_logout_pressed)

	# Mostrar datos del usuario autenticado
	_update_user_info()
	_construir_ajustes()


func _update_score(total: int) -> void:
	score_label.text = "⭐ %d pts" % total


func _update_user_info() -> void:
	var display_name: String = AuthManager.get_display_name()
	var email: String = AuthManager.current_user.get("email", "")
	user_name_label.text = display_name
	user_email_label.text = email


func _toggle_achievements() -> void:
	var panel_scene = load("res://scenes/UI/achievements_medals_panel.tscn")
	if panel_scene:
		var instance = panel_scene.instantiate()
		get_tree().root.add_child(instance)


func _show_leaderboard() -> void:
	var lb_scene = load("res://scenes/UI/leaderboard_panel.tscn")
	if lb_scene:
		var instance = lb_scene.instantiate()
		get_tree().root.add_child(instance)


func _toggle_menu() -> void:
	menu_panel.visible = not menu_panel.visible
	Sonido.efecto("abrir" if menu_panel.visible else "cerrar")
	_mostrar_lista(null)
	if menu_panel.visible:
		achievements_panel.visible = false  # Cerrar logros si están abiertos
		_update_user_info()
		_refrescar_ajustes()


# ─── Ajustes: fuente, música y efectos ──────────────────────────────────────
# Se construyen por código dentro del menú, entre el correo y «Cerrar sesión».
# Cada cambio va a Ajustes, que lo guarda por cuenta y lo aplica (Tipografia,
# Sonido).

const COLOR_TITULO_AJUSTE := Color(0.79, 0.71, 0.35, 1.0)
const COLOR_NOTA_AJUSTE := Color(0.5, 0.54, 0.7, 1.0)

var _selector_fuente: Button
var _lista_fuentes: VBoxContainer
var _interruptor_musica: CheckButton
var _selector_pista: Button
var _lista_pistas: VBoxContainer
var _volumen_musica: HSlider
var _etiqueta_volumen_musica: Label
var _interruptor_efectos: CheckButton
var _volumen_efectos: HSlider
var _etiqueta_volumen_efectos: Label

## Lo que se ve de cada sección del menú, sin su lista. Con una lista abierta,
## el menú solo enseña la sección de esa lista (ver _mostrar_lista).
var _seccion_fuente: Array[Control] = []
var _seccion_musica: Array[Control] = []
var _seccion_efectos: Array[Control] = []

## Mientras se copian los valores de Ajustes a los controles, sus señales no
## deben volver a escribir en Ajustes.
var _refrescando := false


func _construir_ajustes() -> void:
	_seccion_fuente.append(HSeparator.new())
	_seccion_fuente.append(_etiqueta_ajuste("TituloFuente", "🔤 Fuente del texto"))
	_selector_fuente = _desplegable("SelectorFuente")
	_selector_fuente.pressed.connect(_alternar_lista.bind(true))
	_seccion_fuente.append(_selector_fuente)
	_lista_fuentes = _lista_ajuste("ListaFuentes")
	for id in Tipografia.ORDEN:
		var opcion := _opcion_ajuste("Fuente_" + id)
		# Cada nombre con su propia fuente, al tamaño que ocupa en el juego.
		opcion.add_theme_font_override("font", Tipografia.fuente_de(id))
		opcion.add_theme_font_size_override("font_size", roundi(16 * Tipografia.escala(id)))
		opcion.set_meta("sin_escala", true)
		opcion.pressed.connect(_elegir_fuente.bind(id))
		_lista_fuentes.add_child(opcion)

	_seccion_musica.append(HSeparator.new())
	_interruptor_musica = _interruptor_ajuste("InterruptorMusica", "🎵 Música")
	_interruptor_musica.toggled.connect(_on_interruptor.bind("musica_activa"))
	_seccion_musica.append(_interruptor_musica)
	_selector_pista = _desplegable("SelectorPista")
	_selector_pista.pressed.connect(_alternar_lista.bind(false))
	_seccion_musica.append(_selector_pista)
	_lista_pistas = _lista_ajuste("ListaPistas")
	for id in Sonido.ORDEN_PISTAS:
		var opcion := _opcion_ajuste("Pista_" + id)
		opcion.pressed.connect(_elegir_pista.bind(id))
		_lista_pistas.add_child(opcion)
	var fila_musica := _fila_volumen("VolumenMusica", "EtiquetaVolumenMusica")
	_volumen_musica = fila_musica.get_node("VolumenMusica")
	_etiqueta_volumen_musica = fila_musica.get_node("EtiquetaVolumenMusica")
	_volumen_musica.value_changed.connect(_on_volumen.bind("musica_volumen", _etiqueta_volumen_musica))
	_seccion_musica.append(fila_musica)

	_seccion_efectos.append(HSeparator.new())
	_interruptor_efectos = _interruptor_ajuste("InterruptorEfectos", "🔔 Efectos de sonido")
	_interruptor_efectos.toggled.connect(_on_interruptor.bind("efectos_activos"))
	_seccion_efectos.append(_interruptor_efectos)
	var fila_efectos := _fila_volumen("VolumenEfectos", "EtiquetaVolumenEfectos")
	_volumen_efectos = fila_efectos.get_node("VolumenEfectos")
	_etiqueta_volumen_efectos = fila_efectos.get_node("EtiquetaVolumenEfectos")
	_volumen_efectos.value_changed.connect(_on_volumen.bind("efectos_volumen", _etiqueta_volumen_efectos))
	_seccion_efectos.append(fila_efectos)

	# Todo antes del separador de «Cerrar sesión»; cada lista, bajo su selector.
	var nodos: Array[Control] = []
	nodos.append_array(_seccion_fuente)
	nodos.append(_lista_fuentes)
	nodos.append_array(_seccion_musica)
	nodos.insert(nodos.find(_selector_pista) + 1, _lista_pistas)
	nodos.append_array(_seccion_efectos)
	var caja := menu_panel.get_node("VBoxContainer")
	var antes := caja.get_node("HSeparator2")
	for nodo in nodos:
		caja.add_child(nodo)
		caja.move_child(nodo, antes.get_index())
	_refrescar_ajustes()


## Copia a los controles lo que dice Ajustes.
func _refrescar_ajustes() -> void:
	_refrescando = true
	var fuente := str(Ajustes.obtener("fuente"))
	if not Tipografia.FAMILIAS.has(fuente):
		fuente = "adventor"
	_selector_fuente.text = Tipografia.FAMILIAS[fuente]["nombre"]
	for id in Tipografia.ORDEN:
		var familia: Dictionary = Tipografia.FAMILIAS[id]
		_marcar_opcion(_lista_fuentes.get_node("Fuente_" + id), id == fuente, familia["nombre"], familia["nota"])

	var musica_activa := bool(Ajustes.obtener("musica_activa"))
	var pista := str(Ajustes.obtener("musica_pista"))
	if not Sonido.PISTAS.has(pista):
		pista = "biblioteca"
	_interruptor_musica.button_pressed = musica_activa
	_selector_pista.text = Sonido.PISTAS[pista]["nombre"]
	_selector_pista.disabled = not musica_activa
	_volumen_musica.editable = musica_activa
	for id in Sonido.ORDEN_PISTAS:
		var datos: Dictionary = Sonido.PISTAS[id]
		_marcar_opcion(_lista_pistas.get_node("Pista_" + id), id == pista, datos["nombre"], datos["nota"])
	_volumen_musica.value = int(Ajustes.obtener("musica_volumen"))
	_etiqueta_volumen_musica.text = "%d %%" % int(Ajustes.obtener("musica_volumen"))

	var efectos_activos := bool(Ajustes.obtener("efectos_activos"))
	_interruptor_efectos.button_pressed = efectos_activos
	_volumen_efectos.editable = efectos_activos
	_volumen_efectos.value = int(Ajustes.obtener("efectos_volumen"))
	_etiqueta_volumen_efectos.text = "%d %%" % int(Ajustes.obtener("efectos_volumen"))
	_refrescando = false


## Abre la lista de fuentes (o la de músicas), o la cierra si ya lo estaba.
func _alternar_lista(fuentes: bool) -> void:
	var lista := _lista_fuentes if fuentes else _lista_pistas
	if lista.visible:
		_mostrar_lista(null)
	else:
		_mostrar_lista(lista)


## Deja abierta como mucho una lista (null: ninguna). Con una lista abierta,
## el menú solo enseña la sección de esa lista: así cabe en 720 px con
## cualquier fuente.
func _mostrar_lista(lista: Control) -> void:
	_lista_fuentes.visible = lista == _lista_fuentes
	_lista_pistas.visible = lista == _lista_pistas
	for nodo in _seccion_fuente:
		nodo.visible = lista == null or lista == _lista_fuentes
	for nodo in _seccion_musica:
		nodo.visible = lista == null or lista == _lista_pistas
	for nodo in _seccion_efectos:
		nodo.visible = lista == null


func _elegir_fuente(id: String) -> void:
	Ajustes.fijar("fuente", id)
	_mostrar_lista(null)
	_refrescar_ajustes()


func _elegir_pista(id: String) -> void:
	Ajustes.fijar("musica_pista", id)
	_mostrar_lista(null)
	_refrescar_ajustes()


func _on_interruptor(activado: bool, clave: String) -> void:
	if _refrescando:
		return
	Ajustes.fijar(clave, activado)
	if clave == "musica_activa":
		_mostrar_lista(null)
	_refrescar_ajustes()


func _on_volumen(valor: float, clave: String, etiqueta: Label) -> void:
	if _refrescando:
		return
	Ajustes.fijar(clave, int(valor))
	etiqueta.text = "%d %%" % int(valor)


# ─── Piezas del menú de ajustes ──────────────────────────────────────────────

func _estilo_ajuste(fondo: Color, borde: Color) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = fondo
	estilo.border_color = borde
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(8)
	estilo.content_margin_left = 10
	estilo.content_margin_right = 10
	estilo.content_margin_top = 5
	estilo.content_margin_bottom = 5
	return estilo


func _etiqueta_ajuste(nombre: String, texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.name = nombre
	etiqueta.text = texto
	etiqueta.add_theme_color_override("font_color", COLOR_TITULO_AJUSTE)
	etiqueta.add_theme_font_size_override("font_size", 14)
	return etiqueta


## Botón que abre una lista, con la flecha a la derecha.
func _desplegable(nombre: String) -> Button:
	var boton := Button.new()
	boton.name = nombre
	boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
	boton.add_theme_font_size_override("font_size", 16)
	boton.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	var normal := _estilo_ajuste(Color(1, 1, 1, 0.04), Color(0.85, 0.75, 0.3, 0.6))
	boton.add_theme_stylebox_override("normal", normal)
	boton.add_theme_stylebox_override("pressed", normal)
	boton.add_theme_stylebox_override("hover", _estilo_ajuste(Color(1, 1, 1, 0.09), Color(0.85, 0.75, 0.3, 0.9)))
	boton.add_theme_stylebox_override("disabled", _estilo_ajuste(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.15)))
	var flecha := Label.new()
	flecha.text = "▾"
	flecha.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	flecha.position.x -= 22
	flecha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flecha.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 0.8))
	boton.add_child(flecha)
	return boton


func _lista_ajuste(nombre: String) -> VBoxContainer:
	var lista := VBoxContainer.new()
	lista.name = nombre
	lista.visible = false
	lista.add_theme_constant_override("separation", 2)
	return lista


func _opcion_ajuste(nombre: String) -> Button:
	var opcion := Button.new()
	opcion.name = nombre
	opcion.alignment = HORIZONTAL_ALIGNMENT_LEFT
	opcion.add_theme_font_size_override("font_size", 15)
	opcion.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	opcion.add_theme_stylebox_override("normal", _estilo_ajuste(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.08)))
	opcion.add_theme_stylebox_override("hover", _estilo_ajuste(Color(0.85, 0.75, 0.3, 0.16), Color(0.85, 0.75, 0.3, 0.5)))
	opcion.add_theme_stylebox_override("pressed", _estilo_ajuste(Color(0.85, 0.75, 0.3, 0.16), Color(0.85, 0.75, 0.3, 0.5)))
	return opcion


## La opción elegida lleva ✓; todas, su nota de para qué sirve.
func _marcar_opcion(opcion: Button, elegida: bool, nombre: String, nota: String) -> void:
	opcion.text = ("✓ " if elegida else "") + nombre + "  · " + nota


func _interruptor_ajuste(nombre: String, texto: String) -> CheckButton:
	var interruptor := CheckButton.new()
	interruptor.name = nombre
	interruptor.text = texto
	interruptor.add_theme_font_size_override("font_size", 14)
	interruptor.add_theme_color_override("font_color", COLOR_TITULO_AJUSTE)
	interruptor.add_theme_color_override("font_pressed_color", COLOR_TITULO_AJUSTE)
	interruptor.add_theme_color_override("font_hover_color", COLOR_TITULO_AJUSTE)
	interruptor.add_theme_color_override("font_hover_pressed_color", COLOR_TITULO_AJUSTE)
	return interruptor


## Fila «🔈 [deslizador] 40 %» con el deslizador y la etiqueta con nombre.
func _fila_volumen(nombre_deslizador: String, nombre_etiqueta: String) -> HBoxContainer:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	var icono := Label.new()
	icono.text = "🔈"
	icono.add_theme_font_size_override("font_size", 13)
	fila.add_child(icono)
	var deslizador := HSlider.new()
	deslizador.name = nombre_deslizador
	deslizador.min_value = 0
	deslizador.max_value = 100
	deslizador.step = 5
	deslizador.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deslizador.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(deslizador)
	var etiqueta := Label.new()
	etiqueta.name = nombre_etiqueta
	etiqueta.custom_minimum_size = Vector2(44, 0)
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	etiqueta.add_theme_font_size_override("font_size", 13)
	etiqueta.add_theme_color_override("font_color", COLOR_NOTA_AJUSTE)
	fila.add_child(etiqueta)
	return fila


func _on_logout_pressed() -> void:
	# Cerrar sesión en el AuthManager
	AuthManager.logout()
	
	# Resetear estado local del juego
	GameSession.score_data = {
		"total_score": 0,
		"sessions_completed": 0,
		"correct_by_level": {"Literal": 0, "Inferencial": 0, "Critico": 0},
		"incorrect_by_level": {"Literal": 0, "Inferencial": 0, "Critico": 0},
		"typologies_completed": [],
		"perfect_sessions": 0,
		"achievements": [],
		"best_scores_by_typology": {},
	}
	GameSession.set_character("male")
	GameSession.reset_tutorial()
	
	# Resetear progresión
	ProgressionManager.reset_all()
	
	print("[ScoreHUD] Sesión cerrada, volviendo al login")
	get_tree().change_scene_to_file(LOGIN_SCENE)


func _populate_achievements() -> void:
	# Limpiar lista anterior
	for child in achievements_list.get_children():
		child.queue_free()

	var unlocked: Array = GameSession.get_achievements()
	var font = load(FONT_PATH)
	if SceneManager and font:
		SceneManager.ensure_fallbacks(font)

	for achievement_id in ACHIEVEMENT_NAMES:
		var display_name: String = ACHIEVEMENT_NAMES[achievement_id]
		var is_unlocked: bool = achievement_id in unlocked

		var label := Label.new()
		if is_unlocked:
			label.text = "✅ %s" % display_name
			label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8, 1.0))
		else:
			label.text = "🔒 %s" % display_name
			label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))

		if font:
			label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 16)
		achievements_list.add_child(label)

	# Estadísticas
	var separator := HSeparator.new()
	achievements_list.add_child(separator)

	var stats := Label.new()
	var sd = GameSession.score_data
	var unlocked_count: int = ProgressionManager.unlocked.size()
	var total_tipologias: int = ProgressionManager.DIFFICULTY_ORDER.size()
	stats.text = "Sesiones: %d | Perfectas: %d\nTipologías: %d/%d | Desbloqueados: %d/%d" % [
		sd.get("sessions_completed", 0),
		sd.get("perfect_sessions", 0),
		sd.get("typologies_completed", []).size(),
		total_tipologias,
		unlocked_count,
		total_tipologias,
	]
	stats.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 1.0))
	if font:
		stats.add_theme_font_override("font", font)
	stats.add_theme_font_size_override("font_size", 14)
	achievements_list.add_child(stats)


func _on_achievement_unlocked(_id: String, _display_name: String) -> void:
	# La notificación visual la gestiona el Autoload AchievementToast.
	# Aquí solo refrescamos la lista si está abierta.
	if achievements_panel.visible:
		_populate_achievements()


func _on_progression_changed() -> void:
	_update_score(ProgressionManager.get_total_score())
	if achievements_panel.visible:
		_populate_achievements()
