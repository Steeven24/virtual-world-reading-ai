## Lista de objetivos siempre a la vista.
##
## Muchos jugadores se quedaban parados sin saber qué tocaba: el tutorial se ve
## una vez al principio y luego no queda nada que recuerde el recorrido. Este
## panel se queda en la esquina superior izquierda y va marcando los pasos de la
## fase en la que está el jugador (lobby, lectura o desafíos).
##
## Queda justo debajo de la tarjeta de perfil (ProfileHUD), que ocupa la
## esquina; si la tarjeta no se ve, sube hasta el margen superior.
##
## Se pliega con TAB o pulsando su cabecera, y se esconde solo mientras hay un
## cuadro de diálogo, el libro o el tutorial abiertos, para no taparlos.
##
## Registrar como Autoload: Project Settings → Autoload → "ObjectivesHUD"
extends CanvasLayer

# ─── Constantes ──────────────────────────────────────────────────────────────

const FONT_BOLD_PATH := "res://fonts/fuente_juego_negrita.tres"
const FONT_REGULAR_PATH := "res://fonts/fuente_juego.tres"

const MARGEN: int = 14
const ANCHO_PANEL: int = 296
const ANIM_DURACION: float = 0.22

## Cada cuánto se recalcula la lista. El estado del juego vive repartido entre
## GameSession, ProgressionManager y la escena actual, y no todos avisan por
## señal; sondear de vez en cuando sale más barato que cablearlo todo.
const INTERVALO_REFRESCO: float = 0.6

const COLOR_ORO := Color(0.93, 0.79, 0.28)
const COLOR_FONDO := Color(0.06, 0.06, 0.12, 0.94)
const COLOR_BORDE := Color(0.85, 0.75, 0.3, 0.55)
const COLOR_HECHO := Color(0.55, 0.80, 0.55)
const COLOR_ACTUAL := Color(0.97, 0.93, 0.75)
const COLOR_PENDIENTE := Color(0.62, 0.64, 0.72)
const COLOR_PIE := Color(0.66, 0.68, 0.78)

## Escenas donde el panel no pinta nada: tienen su propia interfaz a pantalla
## completa y sus propias instrucciones.
const ESCENAS_OCULTAS: Array[String] = [
	"res://scenes/UI/login_screen.tscn",
	"res://scenes/UI/character_select.tscn",
	"res://scenes/UI/change_password_screen.tscn",
	"res://scenes/UI/session_results.tscn",
	"res://scenes/Challenges/Templates/quiz_challenge.tscn",
]

const LOBBY_SCENE := "res://scenes/Scenery/Lobby/lobby.tscn"

## Nombre visible de cada nivel de comprensión.
const NOMBRES_NIVEL: Dictionary = {
	"Literal": "Literal",
	"Inferencial": "Inferencial",
	"Critico": "Crítico",
}

const CONFIG_PATH := "user://progress.cfg"
const CONFIG_SECCION := "ui"
const CONFIG_CLAVE_PLEGADO := "objectives_collapsed"

# ─── Nodos ───────────────────────────────────────────────────────────────────

var _panel: PanelContainer = null
var _cabecera: Button = null
var _indicador_plegado: Label = null
var _lista: VBoxContainer = null
var _pie: Label = null
var _separador: HSeparator = null

var _font_bold: Font = null
var _font_regular: Font = null

# ─── Estado ──────────────────────────────────────────────────────────────────

var _plegado: bool = false
var _pasos_actuales: Array = []
var _pie_actual: String = ""
var _visible_objetivo: bool = false
var _tween_visibilidad: Tween = null

# ─── Ciclo de vida ───────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 20
	# Panel de interfaz: no debe moverse ni escalarse con la cámara del mundo.
	follow_viewport_enabled = false

	_font_bold = load(FONT_BOLD_PATH) if ResourceLoader.exists(FONT_BOLD_PATH) else null
	_font_regular = load(FONT_REGULAR_PATH) if ResourceLoader.exists(FONT_REGULAR_PATH) else null
	if SceneManager:
		SceneManager.ensure_fallbacks(_font_bold)
		SceneManager.ensure_fallbacks(_font_regular)

	_plegado = _leer_plegado()
	_construir_ui()
	_aplicar_plegado(false)

	_panel.modulate.a = 0.0
	_panel.visible = false

	var temporizador := Timer.new()
	temporizador.wait_time = INTERVALO_REFRESCO
	temporizador.autostart = true
	temporizador.timeout.connect(_refrescar)
	add_child(temporizador)

	get_tree().node_added.connect(_on_node_added)
	_refrescar()


## Cambiar de escena no emite ninguna señal útil, pero sí añade nodos: en cuanto
## aparece una nueva escena raíz se recalculan los objetivos sin esperar al
## temporizador, para que el panel no muestre los de la sala anterior.
func _on_node_added(nodo: Node) -> void:
	if nodo.get_parent() == get_tree().root:
		call_deferred("_refrescar")


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_TAB:
		return
	# Con un diálogo abierto el TAB sirve para saltar entre sus botones.
	if SceneManager.is_ui_open or not _visible_objetivo:
		return

	_alternar_plegado()
	get_viewport().set_input_as_handled()

# ─── Construcción de la interfaz ─────────────────────────────────────────────

func _construir_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(ANCHO_PANEL, 0)
	_panel.position = Vector2(MARGEN, MARGEN)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	# La flecha del borde de GuiaDestino no se mete debajo de este panel.
	_panel.add_to_group("zona_hud")

	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_FONDO
	estilo.set_corner_radius_all(12)
	estilo.set_border_width_all(2)
	estilo.border_color = COLOR_BORDE
	estilo.set_content_margin_all(12)
	estilo.shadow_color = Color(0, 0, 0, 0.45)
	estilo.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", estilo)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# Cabecera: también es el botón de plegar, así que funciona con ratón
	# además del atajo TAB.
	_cabecera = Button.new()
	_cabecera.flat = true
	_cabecera.focus_mode = Control.FOCUS_NONE
	_cabecera.tooltip_text = "Plegar o desplegar la lista (TAB)"
	_cabecera.pressed.connect(_alternar_plegado)
	_cabecera.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_cabecera.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	_cabecera.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	vbox.add_child(_cabecera)

	var fila := HBoxContainer.new()
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cabecera.add_child(fila)

	var titulo := Label.new()
	titulo.text = "🎯 OBJETIVOS"
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulo.add_theme_color_override("font_color", COLOR_ORO)
	titulo.add_theme_font_size_override("font_size", 15)
	if _font_bold:
		titulo.add_theme_font_override("font", _font_bold)
	fila.add_child(titulo)

	_indicador_plegado = Label.new()
	_indicador_plegado.text = "–"
	_indicador_plegado.add_theme_color_override("font_color", COLOR_ORO)
	_indicador_plegado.add_theme_font_size_override("font_size", 15)
	if _font_bold:
		_indicador_plegado.add_theme_font_override("font", _font_bold)
	fila.add_child(_indicador_plegado)

	# El botón no tiene texto propio (el título va en un hijo), así que hay que
	# darle alto a mano o la cabecera se recortaría.
	_cabecera.custom_minimum_size = Vector2(0, 26)

	_separador = HSeparator.new()
	vbox.add_child(_separador)

	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 4)
	vbox.add_child(_lista)

	_pie = Label.new()
	_pie.add_theme_color_override("font_color", COLOR_PIE)
	_pie.add_theme_font_size_override("font_size", 11)
	_pie.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _font_regular:
		_pie.add_theme_font_override("font", _font_regular)
	vbox.add_child(_pie)

# ─── Plegado ─────────────────────────────────────────────────────────────────

func _alternar_plegado() -> void:
	_plegado = not _plegado
	_aplicar_plegado(true)
	_guardar_plegado()


func _aplicar_plegado(_animar: bool) -> void:
	_indicador_plegado.text = "+" if _plegado else "–"
	_separador.visible = not _plegado
	_lista.visible = not _plegado
	_pie.visible = not _plegado and not _pie_actual.is_empty()
	_reajustar()

# ─── Refresco de contenido ───────────────────────────────────────────────────

func _refrescar() -> void:
	var mostrar := _debe_mostrarse()
	if mostrar != _visible_objetivo:
		_visible_objetivo = mostrar
		_animar_visibilidad(mostrar)

	if not mostrar:
		return

	_colocar()

	var datos := _calcular_objetivos()
	var pasos: Array = datos.get("pasos", [])
	var pie: String = str(datos.get("pie", ""))

	if pasos == _pasos_actuales and pie == _pie_actual:
		return

	_pasos_actuales = pasos
	_pie_actual = pie
	_pintar(pasos, pie)


## El panel solo estorba cuando hay algo abierto encima o cuando la escena ya
## explica por sí sola qué hacer.
func _debe_mostrarse() -> bool:
	if SceneManager.is_ui_open:
		return false
	var escena := get_tree().current_scene
	if escena == null:
		return false
	return not (escena.scene_file_path in ESCENAS_OCULTAS)


## Separación entre la tarjeta de perfil y este panel.
const SEPARACION_PERFIL: int = 8

func _colocar() -> void:
	var y := float(MARGEN)
	var perfil := get_node_or_null("/root/ProfileHUD")
	if perfil and perfil.has_method("get_bottom_edge"):
		var borde: float = perfil.get_bottom_edge()
		if borde >= 0.0:
			y = borde + SEPARACION_PERFIL
	_panel.position = Vector2(MARGEN, y)


func _animar_visibilidad(mostrar: bool) -> void:
	if _tween_visibilidad and _tween_visibilidad.is_valid():
		_tween_visibilidad.kill()

	if mostrar:
		_panel.visible = true

	_tween_visibilidad = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween_visibilidad.tween_property(_panel, "modulate:a", 1.0 if mostrar else 0.0, ANIM_DURACION)
	if not mostrar:
		_tween_visibilidad.tween_callback(func(): _panel.visible = false)


func _pintar(pasos: Array, pie: String) -> void:
	for hijo in _lista.get_children():
		hijo.queue_free()

	# El paso actual es el primero sin completar: el resto queda por delante.
	var indice_actual := -1
	for i in pasos.size():
		if not bool(pasos[i].get("hecho", false)):
			indice_actual = i
			break

	for i in pasos.size():
		var paso: Dictionary = pasos[i]
		var hecho: bool = bool(paso.get("hecho", false))
		var es_actual: bool = (i == indice_actual)

		var etiqueta := Label.new()
		var simbolo := "✓" if hecho else ("➜" if es_actual else "○")
		etiqueta.text = "%s  %s" % [simbolo, str(paso.get("texto", ""))]
		etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		etiqueta.add_theme_font_size_override("font_size", 12)

		if hecho:
			etiqueta.add_theme_color_override("font_color", COLOR_HECHO)
		elif es_actual:
			etiqueta.add_theme_color_override("font_color", COLOR_ACTUAL)
		else:
			etiqueta.add_theme_color_override("font_color", COLOR_PENDIENTE)

		var fuente := _font_bold if es_actual else _font_regular
		if fuente:
			etiqueta.add_theme_font_override("font", fuente)

		_lista.add_child(etiqueta)

	_pie.text = pie
	_pie.visible = not _plegado and not pie.is_empty()
	_reajustar()


## El panel cuelga directamente del CanvasLayer, así que nadie le ajusta el
## tamaño: hay que pedírselo. Y hacen falta dos pasadas, porque los objetivos
## se envuelven en varias líneas y hasta que no tienen el ancho definitivo no
## saben cuánto alto necesitan; con una sola pasada el último paso se cortaba.
func _reajustar() -> void:
	_panel.reset_size()
	await get_tree().process_frame
	if is_instance_valid(_panel):
		_panel.reset_size()

# ─── Cálculo de objetivos por fase ───────────────────────────────────────────

func _calcular_objetivos() -> Dictionary:
	match _fase(get_tree().current_scene):
		"lobby":
			return _objetivos_lobby()
		"lectura":
			return _objetivos_lectura()
		"desafio":
			return _objetivos_desafio()
	return {"pasos": [], "pie": ""}


## Fase en la que está el jugador: "lobby", "lectura", "desafio" o "" sin
## escena. La lista de pasos y la flecha de destino (GuiaDestino) salen de
## aquí, para que nunca se contradigan.
func _fase(escena: Node) -> String:
	if escena == null:
		return ""
	if escena.scene_file_path == LOBBY_SCENE:
		return "lobby"

	# Escenario de tipología: si tiene libro y la lectura no ha terminado,
	# el jugador sigue en la fase de leer; si no, le toca el profesor.
	var tiene_libro := escena.has_node("Book") or escena.has_node("CanvasLayer/LecturaYLibro")
	var lectura_terminada: bool = GameSession.reading_end_time > 0.0

	if tiene_libro and not lectura_terminada:
		return "lectura"
	return "desafio"


## Nodo al que tiene que ir el jugador ahora, o null: la estación que toca en
## el lobby, el libro mientras lee y el profesor en los desafíos.
func destino_actual() -> Node2D:
	var escena := get_tree().current_scene
	if escena == null or escena.scene_file_path in ESCENAS_OCULTAS:
		return null
	match _fase(escena):
		"lobby":
			return _destino_lobby(escena)
		"lectura":
			return escena.get_node_or_null("Book") as Node2D
		"desafio":
			return escena.get_node_or_null("Teacher") as Node2D
	return null


## La estación de la lectura a medias o de la primera tipología sin aprobar;
## con todo aprobado, la de práctica. Con el juego terminado, ninguna.
func _destino_lobby(escena: Node) -> Node2D:
	if ProgressionManager.juego_terminado():
		return null
	var tipologia := _tipologia_pendiente()
	if tipologia.is_empty():
		if ProgressionManager.all_approved():
			return _estacion(escena, func(n): return n.get("is_practice_station") == true)
		tipologia = ProgressionManager.get_next_unapproved()
	return _estacion(escena, func(n): return n.get("typology") == tipologia and n.get("is_practice_station") != true)


## Primera estación del lobby (los nodos con is_practice_station) que cumple
## la condición, o null.
func _estacion(escena: Node, condicion: Callable) -> Node2D:
	for nodo in escena.find_children("*", "Node2D", true, false):
		if nodo.get("is_practice_station") != null and condicion.call(nodo):
			return nodo
	return null


## Tipología de la lectura de progresión a medias, o "".
func _tipologia_pendiente() -> String:
	if ReadingProgressManager.has_active_reading():
		return ReadingProgressManager.get_active_typology()
	return GameSession.current_progression_typology()


func _objetivos_lobby() -> Dictionary:
	var pasos: Array = []

	pasos.append({
		"texto": "Repasa el tutorial en el ícono central (E)",
		"hecho": GameSession.is_tutorial_completed(),
	})

	# Sin intentos en una tipología el recorrido se acabó: solo queda practicar.
	if ProgressionManager.juego_terminado():
		pasos.append({"texto": "Juego terminado: ya no puedes avanzar", "hecho": false})
		return {"pasos": pasos, "pie": "Puedes seguir practicando en la zona de práctica"}

	# Una lectura a medias manda sobre todo lo demás: no se puede empezar otra
	# hasta terminarla, así que es lo primero que hay que contar.
	var pendiente := _tipologia_pendiente()

	# Las tipologías aprobadas se cierran: el objetivo señala la siguiente y,
	# con el recorrido completo, solo queda practicar.
	var recorrido_completo := pendiente.is_empty() and ProgressionManager.all_approved()
	if recorrido_completo:
		pasos.append({"texto": "¡Completaste las 4 tipologías! Sigue practicando en la zona de práctica", "hecho": true})
	elif pendiente.is_empty():
		var siguiente := ProgressionManager.get_next_unapproved()
		pasos.append({
			"texto": "Acércate al cartel de %s y pulsa E (%s)" % [
				ProgressionManager.NOMBRE_ESCENARIO[siguiente],
				ProgressionManager.texto_intento(siguiente).to_lower(),
			],
			"hecho": false,
		})
	else:
		pasos.append({"texto": "Vuelve al escenario %s: tienes una lectura sin terminar" % pendiente, "hecho": false})

	if not recorrido_completo:
		pasos.append({"texto": "Lee el texto y marca lo importante", "hecho": false})
		pasos.append({"texto": "Supera los 3 desafíos con el profesor", "hecho": false})

	var completadas: int = GameSession.score_data.get("typologies_completed", []).size()
	var pie := "Tipologías completadas: %d/%d  ·  %d pts" % [
		completadas, ProgressionManager.DIFFICULTY_ORDER.size(), GameSession.get_total_score()
	]
	return {"pasos": pasos, "pie": pie}


func _objetivos_lectura() -> Dictionary:
	var herramientas: Dictionary = GameSession.tools_used
	var uso_herramientas: bool = (
		bool(herramientas.get("highlight", false))
		or bool(herramientas.get("underline", false))
		or bool(herramientas.get("notes", false))
	)

	var pasos: Array = [
		{
			"texto": "Habla con el Sabio y el Robot (E) si te atascas",
			"hecho": GameSession.is_hint_seen(GameSession.HINT_INTRO_SAGE),
		},
		{"texto": "Acércate al libro y pulsa E para abrirlo", "hecho": false},
		{"texto": "Resalta (1), subraya (2) o toma notas mientras lees", "hecho": uso_herramientas},
		{"texto": "Pulsa «Hecho» al terminar la lectura", "hecho": false},
	]

	var pie := ""
	if not GameSession.current_typology.is_empty():
		if GameSession.is_practice:
			pie = "Práctica · Texto %s · no cuenta para tu progreso" % GameSession.current_typology
		else:
			pie = "Texto %s  ·  3 desafíos por delante" % GameSession.current_typology
	return {"pasos": pasos, "pie": pie}


func _objetivos_desafio() -> Dictionary:
	var nivel: String = GameSession.get_current_level()
	var nombre_nivel: String = str(NOMBRES_NIVEL.get(nivel, nivel))
	var indice: int = GameSession.current_level_index

	var pasos: Array = [
		{"texto": "Lectura completada", "hecho": true},
		{"texto": "Acércate al profesor y pulsa E", "hecho": false},
		{
			"texto": "Responde las %d preguntas del nivel %s" % [GameSession.QUESTIONS_PER_LEVEL, nombre_nivel],
			"hecho": false,
		},
	]

	# Los niveles ya superados se marcan para que se vea el avance.
	for i in indice:
		var superado: String = str(NOMBRES_NIVEL.get(GameSession.LEVELS[i], GameSession.LEVELS[i]))
		pasos.insert(1 + i, {"texto": "Nivel %s superado" % superado, "hecho": true})

	var pie := "Nivel %d de %d  ·  %d pts en esta %s" % [
		indice + 1, GameSession.LEVELS.size(), GameSession.get_session_score(),
		"práctica" if GameSession.is_practice else "sesión",
	]
	return {"pasos": pasos, "pie": pie}

# ─── Persistencia del plegado ────────────────────────────────────────────────

func _leer_plegado() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return false
	return bool(cfg.get_value(CONFIG_SECCION, CONFIG_CLAVE_PLEGADO, false))


func _guardar_plegado() -> void:
	var cfg := ConfigFile.new()
	# Se carga antes de escribir para no llevarse por delante el tutorial y las
	# guías, que viven en el mismo archivo.
	cfg.load(CONFIG_PATH)
	cfg.set_value(CONFIG_SECCION, CONFIG_CLAVE_PLEGADO, _plegado)
	cfg.save(CONFIG_PATH)
