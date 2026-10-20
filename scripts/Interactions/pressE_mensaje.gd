## Interacción sencilla: al acercarse sale el globo de «Presiona E» y, al
## pulsarlo, un bocadillo con un texto que se desvanece solo. No abre ningún
## diálogo ni cambia de escena (por ejemplo, el perro que duerme en
## Descriptivos: «Debería dejarlo descansar»).
extends Node2D

## Texto del bocadillo.
@export_multiline var mensaje: String = "..."

## Segundos que el bocadillo se queda a la vista.
@export var duracion: float = 2.5

## Altura del bocadillo sobre el punto de interacción.
@export var altura_bocadillo: float = 70.0

const FONT_PATH := "res://fonts/fuente_juego.tres"

var _player_in_range := false
var _bocadillo: PanelContainer = null
var _tween: Tween = null


func _ready() -> void:
	$"Speech bubble".visible = false
	$Area2D.body_entered.connect(_on_body_entered)
	$Area2D.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		_player_in_range = true
		$"Speech bubble".visible = true


func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		_player_in_range = false
		$"Speech bubble".visible = false


func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("ui_accept") and not SceneManager.is_ui_open:
		_mostrar_mensaje()


func _mostrar_mensaje() -> void:
	if _bocadillo == null:
		_bocadillo = _crear_bocadillo()
		add_child(_bocadillo)
	Sonido.efecto("clic")
	$"Speech bubble".visible = false

	# El tamaño se conoce tras un frame: entonces se centra sobre el punto.
	_bocadillo.modulate.a = 0.0
	_bocadillo.visible = true
	await get_tree().process_frame
	_bocadillo.position = Vector2(-_bocadillo.size.x / 2.0, -altura_bocadillo - _bocadillo.size.y)

	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_bocadillo, "modulate:a", 1.0, 0.2)
	_tween.tween_interval(duracion)
	_tween.tween_property(_bocadillo, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(func():
		_bocadillo.visible = false
		$"Speech bubble".visible = _player_in_range
	)


func _crear_bocadillo() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.z_index = 10
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.98, 0.96, 0.9, 0.96)
	estilo.border_color = Color(0.35, 0.25, 0.15, 1.0)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(8)
	estilo.content_margin_left = 12
	estilo.content_margin_right = 12
	estilo.content_margin_top = 6
	estilo.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", estilo)

	var etiqueta := Label.new()
	etiqueta.text = mensaje
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.add_theme_color_override("font_color", Color(0.2, 0.14, 0.08))
	etiqueta.add_theme_font_size_override("font_size", 16)
	var fuente = load(FONT_PATH)
	if fuente:
		etiqueta.add_theme_font_override("font", fuente)
	panel.add_child(etiqueta)
	panel.visible = false
	return panel
