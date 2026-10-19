## Flecha y chispas que señalan a dónde ir ahora.
##
## El panel de objetivos dice qué toca; esto lo enseña en el mapa: una flecha
## dorada que rebota sobre el destino, unas chispas alrededor de su base y, si
## el destino queda fuera de la pantalla, otra flecha en el borde que apunta
## hacia él. El destino lo decide ObjectivesHUD.destino_actual(), así que la
## flecha y la lista de pasos nunca se contradicen.
##
## Todo se esconde con una interfaz abierta (diálogos, libro, tutorial) y
## cuando el jugador ya está en el área del destino, donde sale la burbuja «E».
##
## Registrar como Autoload después de ObjectivesHUD: "GuiaDestino".
extends CanvasLayer

const TEXTURA_FLECHA := preload("res://assets/Guia/flecha.png")
const TEXTURA_CHISPA := preload("res://assets/Guia/chispa.png")

## Cada cuánto se vuelve a preguntar el destino. La posición se sigue en cada
## frame, para que la flecha del borde no vaya a saltos al moverse la cámara.
const INTERVALO_DESTINO: float = 0.2

## La punta de la flecha queda a esta altura sobre el origen del destino: por
## encima del profesor (64 px de alto) y del cartel de las estaciones.
const ALTURA_FLECHA: float = 70.0
const REBOTE: float = 6.0
const DURACION_REBOTE: float = 0.6
const ESCALA_FLECHA: float = 2.0

## Flecha del borde: más grande, separada del borde y con un pulso suave.
const ESCALA_FLECHA_BORDE: float = 3.0
const MARGEN_BORDE: float = 32.0
const DURACION_PULSO: float = 0.5

## Por encima de todo lo del mapa (las escenas no pasan de z_index 1).
const Z_MUNDO: int = 10

## Grupo de los paneles de la interfaz que ocupan el borde (perfil, objetivos,
## marcador, franja del lobby). Se dibujan encima de la flecha del borde, así
## que esta se queda antes de entrar en ellos.
const GRUPO_ZONAS := "zona_hud"
## Distancia que la flecha (33 px a ×3) guarda con esos paneles.
const HOLGURA_ZONA: float = 24.0

## Destino actual (o null) y escena en la que se buscó.
var _destino: Node2D = null
var _id_escena: int = 0

## Flecha y chispas sobre el destino: hijo de la escena actual, se rehace al
## cambiar de escena.
var _mundo: Node2D = null
var _flecha_borde: Sprite2D = null


func _ready() -> void:
	layer = 15
	follow_viewport_enabled = false

	_flecha_borde = Sprite2D.new()
	_flecha_borde.name = "FlechaBorde"
	_flecha_borde.texture = TEXTURA_FLECHA
	_flecha_borde.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flecha_borde.scale = Vector2.ONE * ESCALA_FLECHA_BORDE
	_flecha_borde.visible = false
	add_child(_flecha_borde)

	var pulso := _flecha_borde.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	pulso.tween_property(_flecha_borde, "scale", Vector2.ONE * ESCALA_FLECHA_BORDE * 1.15, DURACION_PULSO)
	pulso.tween_property(_flecha_borde, "scale", Vector2.ONE * ESCALA_FLECHA_BORDE, DURACION_PULSO)

	var temporizador := Timer.new()
	temporizador.wait_time = INTERVALO_DESTINO
	temporizador.autostart = true
	temporizador.timeout.connect(_actualizar_destino)
	add_child(temporizador)


func _process(_delta: float) -> void:
	var mostrar := _hay_que_mostrar()
	if is_instance_valid(_mundo):
		_mundo.visible = mostrar
		if mostrar:
			_mundo.global_position = _destino.global_position
	_colocar_flecha_borde(mostrar)


## Pide el destino al panel de objetivos; en una escena nueva, rehace antes el
## nodo de mundo.
func _actualizar_destino() -> void:
	var escena := get_tree().current_scene
	var id := escena.get_instance_id() if escena else 0
	if id != _id_escena:
		_id_escena = id
		_rehacer_mundo(escena)
	_destino = ObjectivesHUD.destino_actual()


func _hay_que_mostrar() -> bool:
	if not is_instance_valid(_destino) or not _destino.is_inside_tree():
		return false
	if SceneManager.is_ui_open:
		return false
	# Dentro del área ya sale la burbuja de «E»: la flecha sobraría.
	return _destino.get("player_in_range") != true


## Con el destino fuera de la vista, flecha en el borde apuntando hacia él.
func _colocar_flecha_borde(mostrar: bool) -> void:
	if mostrar:
		var vista := get_viewport().get_visible_rect()
		var en_pantalla := get_viewport().get_canvas_transform() * _destino.global_position
		mostrar = not vista.has_point(en_pantalla)
		if mostrar:
			_flecha_borde.position = posicion_libre(vista.get_center(), en_pantalla, vista, MARGEN_BORDE, _zonas_hud(), HOLGURA_ZONA)
			# El arte apunta hacia abajo; se gira para que apunte al destino.
			_flecha_borde.rotation = (en_pantalla - _flecha_borde.position).angle() - PI / 2.0
	_flecha_borde.visible = mostrar


## Punto donde la recta de centro a objetivo sale de rect encogido margen: ahí
## va la flecha del borde. Si objetivo ya está dentro, él mismo.
static func posicion_en_borde(centro: Vector2, objetivo: Vector2, rect: Rect2, margen: float) -> Vector2:
	var interior := rect.grow(-margen)
	var direccion := objetivo - centro
	if interior.has_point(objetivo) or direccion.is_zero_approx():
		return objetivo
	# Cuánto se puede avanzar hacia el objetivo antes de cruzar cada borde.
	var t := INF
	if not is_zero_approx(direccion.x):
		var borde_x := interior.end.x if direccion.x > 0.0 else interior.position.x
		t = minf(t, (borde_x - centro.x) / direccion.x)
	if not is_zero_approx(direccion.y):
		var borde_y := interior.end.y if direccion.y > 0.0 else interior.position.y
		t = minf(t, (borde_y - centro.y) / direccion.y)
	return centro + direccion * t


## Como posicion_en_borde, pero si el camino hasta el borde cruza una de las
## zonas (agrandada holgura), la flecha se queda justo antes de entrar en ella.
static func posicion_libre(centro: Vector2, objetivo: Vector2, rect: Rect2, margen: float, zonas: Array[Rect2], holgura: float) -> Vector2:
	var borde := posicion_en_borde(centro, objetivo, rect, margen)
	var direccion := borde - centro
	var t := 1.0
	for zona in zonas:
		var entrada := _entrada(centro, direccion, zona.grow(holgura))
		if entrada >= 0.0:
			t = minf(t, entrada)
	return centro + direccion * t


## Fracción del segmento centro → centro + direccion en la que entra en rect,
## o -1 si no lo cruza (o si centro ya está dentro).
static func _entrada(centro: Vector2, direccion: Vector2, rect: Rect2) -> float:
	if rect.has_point(centro):
		return -1.0
	var t_min := 0.0
	var t_max := 1.0
	for eje in 2:
		if is_zero_approx(direccion[eje]):
			if centro[eje] < rect.position[eje] or centro[eje] > rect.end[eje]:
				return -1.0
			continue
		var t1 := (rect.position[eje] - centro[eje]) / direccion[eje]
		var t2 := (rect.end[eje] - centro[eje]) / direccion[eje]
		t_min = maxf(t_min, minf(t1, t2))
		t_max = minf(t_max, maxf(t1, t2))
	return t_min if t_min <= t_max else -1.0


## Rectángulos (en pantalla) de los paneles visibles del grupo GRUPO_ZONAS.
func _zonas_hud() -> Array[Rect2]:
	var zonas: Array[Rect2] = []
	for nodo in get_tree().get_nodes_in_group(GRUPO_ZONAS):
		var control := nodo as Control
		if control and control.is_visible_in_tree():
			zonas.append(control.get_global_rect())
	return zonas


func _rehacer_mundo(escena: Node) -> void:
	if is_instance_valid(_mundo):
		_mundo.queue_free()
	_mundo = null
	if escena == null:
		return
	_mundo = _crear_mundo()
	escena.add_child(_mundo)


## Flecha que rebota y chispas alrededor de la base del destino.
func _crear_mundo() -> Node2D:
	var mundo := Node2D.new()
	mundo.name = "GuiaDestino"
	mundo.z_index = Z_MUNDO
	mundo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mundo.visible = false

	var flecha := Sprite2D.new()
	flecha.texture = TEXTURA_FLECHA
	flecha.scale = Vector2.ONE * ESCALA_FLECHA
	# Punta en el origen del sprite: así ALTURA_FLECHA mide hasta la punta.
	flecha.offset = Vector2(0.0, -TEXTURA_FLECHA.get_height() / 2.0)
	flecha.position.y = -ALTURA_FLECHA
	mundo.add_child(flecha)
	var rebote := flecha.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	rebote.tween_property(flecha, "position:y", -ALTURA_FLECHA - REBOTE, DURACION_REBOTE)
	rebote.tween_property(flecha, "position:y", -ALTURA_FLECHA, DURACION_REBOTE)

	# Chispas doradas con el centro blanco (el color ya viene en el arte: la
	# rampa solo las desvanece).
	var chispas := CPUParticles2D.new()
	chispas.texture = TEXTURA_CHISPA
	chispas.amount = 8
	chispas.lifetime = 1.2
	chispas.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	chispas.emission_ring_radius = 24.0
	chispas.emission_ring_inner_radius = 20.0
	chispas.direction = Vector2.UP
	chispas.spread = 20.0
	chispas.gravity = Vector2(0.0, -8.0)
	chispas.initial_velocity_min = 4.0
	chispas.initial_velocity_max = 12.0
	chispas.scale_amount_min = 1.0
	chispas.scale_amount_max = 2.0
	var desvanecer := Gradient.new()
	desvanecer.set_color(0, Color.WHITE)
	desvanecer.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	chispas.color_ramp = desvanecer
	mundo.add_child(chispas)
	return mundo
