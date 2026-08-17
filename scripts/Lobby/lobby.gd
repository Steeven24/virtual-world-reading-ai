## Controlador del Lobby.
## - Muestra el tutorial guiado la primera vez que el jugador entra
##   tras seleccionar personaje (persistido vía GameSession).
## - Permite re-abrir el tutorial al interactuar con el punto "Tutorial"
##   del centro del lobby.
extends Node2D

const TUTORIAL_OVERLAY_SCENE: String = "res://scenes/UI/tutorial_overlay.tscn"

## Pequeño retraso antes de abrir el tutorial automáticamente, para que
## la transición de cambio de escena termine y el HUD ya sea visible.
const AUTO_OPEN_DELAY: float = 0.4

var _tutorial_instance: CanvasLayer = null


func _ready() -> void:
	# 1) Conectar el punto "Tutorial" del lobby como trigger del overlay.
	var tutorial_node := get_node_or_null("Tutorial")
	if tutorial_node:
		# Activar el modo tutorial sobre la instancia ya colocada en la escena.
		if "is_tutorial_trigger" in tutorial_node:
			tutorial_node.is_tutorial_trigger = true
		if tutorial_node.has_signal("tutorial_triggered"):
			tutorial_node.tutorial_triggered.connect(_on_tutorial_requested)

	# 2) Si es la primera vez que entra al lobby, mostrar tutorial.
	if not GameSession.is_tutorial_completed():
		await get_tree().create_timer(AUTO_OPEN_DELAY).timeout
		_show_tutorial(true)

	# 3) Mostrar indicador de lectura pendiente (si existe).
	#    Pequeño delay para que ReadingProgressManager haya tenido tiempo de
	#    consultar la API (check_pending_reading se ejecuta al cargar progreso).
	await get_tree().create_timer(0.8).timeout
	_show_pending_reading_indicator()


func _on_tutorial_requested() -> void:
	# Re-abrir manualmente desde el punto del lobby.
	_show_tutorial(false)


func _show_tutorial(mark_on_finish: bool) -> void:
	# Evitar duplicados si el overlay ya está visible.
	if _tutorial_instance and is_instance_valid(_tutorial_instance):
		return

	var packed: PackedScene = load(TUTORIAL_OVERLAY_SCENE)
	if packed == null:
		push_warning("[Lobby] No se pudo cargar el tutorial overlay.")
		return

	_tutorial_instance = packed.instantiate()
	add_child(_tutorial_instance)

	if _tutorial_instance.has_signal("finished"):
		_tutorial_instance.finished.connect(_on_tutorial_finished.bind(mark_on_finish))


func _on_tutorial_finished(mark_on_finish: bool) -> void:
	_tutorial_instance = null
	if mark_on_finish:
		GameSession.mark_tutorial_completed()


# ─── Indicador de lectura pendiente ─────────────────────────────────────────

var _pending_banner: CanvasLayer = null


func _show_pending_reading_indicator() -> void:
	if not ReadingProgressManager.has_active_reading():
		return

	var pending_typology := ReadingProgressManager.get_active_typology()
	if pending_typology.is_empty():
		return

	# Crear banner de CanvasLayer
	_pending_banner = CanvasLayer.new()
	_pending_banner.layer = 10
	add_child(_pending_banner)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.22, 0.92)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.85, 0.65, 0.2, 0.8)
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	_pending_banner.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	var icon_label := Label.new()
	icon_label.text = "📖"
	icon_label.add_theme_font_size_override("font_size", 20)
	hbox.add_child(icon_label)

	var text_label := Label.new()
	text_label.text = "Lectura pendiente en %s — ¡Regresa para continuar!" % pending_typology
	text_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4, 1.0))
	text_label.add_theme_font_size_override("font_size", 14)
	# Cargar fuente del proyecto si existe
	var font_path := "res://fonts/PixelifySans-SemiBold.ttf"
	if ResourceLoader.exists(font_path):
		text_label.add_theme_font_override("font", load(font_path))
	hbox.add_child(text_label)

	# Posicionar arriba centrado
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# Animación de pulso suave en el borde dorado
	var tween := create_tween().set_loops()
	tween.tween_property(panel, "modulate:a", 0.7, 1.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(panel, "modulate:a", 1.0, 1.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Animación de entrada (slide down)
	panel.position.y = -60
	var entry_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	entry_tween.tween_property(panel, "position:y", 0.0, 0.4)

