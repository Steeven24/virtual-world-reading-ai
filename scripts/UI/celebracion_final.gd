## Celebración al aprobar la última tipología del recorrido.
##
## Pantalla completa por encima de los resultados: confeti, rayos de luz tras
## el trofeo, felicitación con el nombre del alumno, sus cinco medallas
## apareciendo una a una y el puntaje total contando hacia arriba. Se construye
## entera por código; basta con:
##   get_tree().root.add_child(CelebracionFinal.new())
class_name CelebracionFinal
extends CanvasLayer

## Se emite al cerrarla (con cualquiera de los dos botones).
signal cerrada

const FONT_PATH := "res://fonts/fuente_juego_negrita.tres"
const FONT_REGULAR_PATH := "res://fonts/fuente_juego.tres"
const PANEL_ACHIEVEMENTS := "res://scenes/UI/achievements_medals_panel.tscn"

const COLOR_GOLD := Color(0.98, 0.82, 0.30)
const COLOR_TEXT := Color(0.94, 0.95, 0.97)
const COLOR_TEXT_DIM := Color(0.72, 0.75, 0.82)
const COLORES_CONFETI: Array[Color] = [
	Color(0.98, 0.82, 0.30), Color(0.35, 0.80, 0.95), Color(0.95, 0.40, 0.55),
	Color(0.55, 0.85, 0.45), Color(0.75, 0.55, 0.95), Color(1.0, 0.6, 0.25),
]
const COLOR_METAL := {
	"oro": Color(0.95, 0.78, 0.20),
	"plata": Color(0.78, 0.82, 0.88),
	"bronce": Color(0.80, 0.52, 0.30),
	"platino": Color(0.70, 0.95, 1.0),
}

const MENSAJE := "Cada texto que leíste te hizo un lector más atento, más crítico y más curioso.\nEste logro es todo tuyo: ¡sigue leyendo el mundo!"

var _font_bold: Font
var _font_regular: Font
var _fondo: ColorRect
var _confeti: _Confeti
var _rayos: _Rayos
var _contenido: VBoxContainer
var _fila_medallas: HBoxContainer
var _puntaje_lbl: Label
var _botones: HBoxContainer
var _cerrando := false


func _ready() -> void:
	layer = 110
	follow_viewport_enabled = false
	_font_bold = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	_font_regular = load(FONT_REGULAR_PATH) if ResourceLoader.exists(FONT_REGULAR_PATH) else null
	if SceneManager:
		SceneManager.ensure_fallbacks(_font_bold)
		SceneManager.ensure_fallbacks(_font_regular)
	_construir()
	_animar_entrada()


# ─── Construcción ────────────────────────────────────────────────────────────

func _construir() -> void:
	_fondo = ColorRect.new()
	_fondo.color = Color(0.02, 0.02, 0.06, 0.0)
	_fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fondo)

	_rayos = _Rayos.new()
	_rayos.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rayos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rayos.modulate.a = 0.0
	add_child(_rayos)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centro)

	_contenido = VBoxContainer.new()
	_contenido.alignment = BoxContainer.ALIGNMENT_CENTER
	_contenido.add_theme_constant_override("separation", 10)
	_contenido.custom_minimum_size = Vector2(900, 0)
	centro.add_child(_contenido)

	var trofeo := _label("🏆", 92, COLOR_GOLD)
	trofeo.name = "Trofeo"
	_contenido.add_child(trofeo)
	_rayos.foco = trofeo

	var nombre := AuthManager.get_display_name() if AuthManager.is_authenticated else ""
	var titulo := _label("¡FELICIDADES, %s!" % nombre.to_upper() if not nombre.is_empty() else "¡FELICIDADES!", 40, COLOR_GOLD)
	titulo.add_theme_color_override("font_outline_color", Color(0.35, 0.2, 0.0))
	titulo.add_theme_constant_override("outline_size", 8)
	_contenido.add_child(titulo)

	_contenido.add_child(_label("Completaste las cuatro tipologías textuales del mundo virtual", 20, COLOR_TEXT, false))

	_fila_medallas = HBoxContainer.new()
	_fila_medallas.alignment = BoxContainer.ALIGNMENT_CENTER
	_fila_medallas.add_theme_constant_override("separation", 18)
	_fila_medallas.custom_minimum_size = Vector2(0, 150)
	_contenido.add_child(_fila_medallas)
	for tipologia in ProgressionManager.DIFFICULTY_ORDER:
		var datos: Dictionary = ProgressionManager.MEDALLAS[tipologia]
		_fila_medallas.add_child(_medalla(datos["emoji"], datos["nombre"], ProgressionManager.metal_de_medalla(tipologia)))
	var gran := ProgressionManager.MEDALLA_GRAN_LECTOR
	_fila_medallas.add_child(_medalla(gran["emoji"], gran["nombre"], "platino"))

	_puntaje_lbl = _label("Puntaje total: 0 pts", 24, COLOR_TEXT)
	_contenido.add_child(_puntaje_lbl)

	var mensaje := _label(MENSAJE, 16, COLOR_TEXT_DIM, false)
	mensaje.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contenido.add_child(mensaje)

	_botones = HBoxContainer.new()
	_botones.alignment = BoxContainer.ALIGNMENT_CENTER
	_botones.add_theme_constant_override("separation", 16)
	_contenido.add_child(_botones)
	var ver := _boton("🏅 Ver mis medallas", Color(0.55, 0.42, 0.08))
	ver.pressed.connect(_on_ver_medallas)
	var seguir := _boton("Continuar", Color(0.18, 0.2, 0.34))
	seguir.pressed.connect(_cerrar)
	_botones.add_child(ver)
	_botones.add_child(seguir)
	var orden: Array[Button] = [ver, seguir]
	DialogFocus.encadenar(orden)

	_confeti = _Confeti.new()
	_confeti.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confeti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confeti.colores = COLORES_CONFETI
	add_child(_confeti)

	# Todo aparece en la secuencia de _animar_entrada.
	for hijo in _contenido.get_children():
		hijo.modulate.a = 0.0
	for medalla in _fila_medallas.get_children():
		medalla.modulate.a = 0.0


func _label(texto: String, tam: int, color: Color, negrita: bool = true) -> Label:
	var lbl := Label.new()
	lbl.text = texto
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", tam)
	lbl.add_theme_color_override("font_color", color)
	var fuente := _font_bold if negrita else _font_regular
	if fuente:
		lbl.add_theme_font_override("font", fuente)
	return lbl


## Una medalla: disco del color del metal con el emoji, nombre y metal.
func _medalla(emoji: String, nombre: String, metal: String) -> Control:
	var color: Color = COLOR_METAL.get(metal, COLOR_TEXT_DIM)
	var caja := VBoxContainer.new()
	caja.alignment = BoxContainer.ALIGNMENT_CENTER
	caja.custom_minimum_size = Vector2(150, 0)
	caja.add_theme_constant_override("separation", 4)

	var disco := PanelContainer.new()
	disco.custom_minimum_size = Vector2(84, 84)
	disco.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = color.darkened(0.55)
	estilo.set_border_width_all(4)
	estilo.border_color = color
	estilo.set_corner_radius_all(42)
	estilo.shadow_color = Color(color, 0.55)
	estilo.shadow_size = 14
	disco.add_theme_stylebox_override("panel", estilo)
	var emoji_lbl := _label(emoji, 40, Color.WHITE)
	emoji_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disco.add_child(emoji_lbl)
	caja.add_child(disco)

	var nombre_lbl := _label(nombre, 13, COLOR_TEXT)
	nombre_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(nombre_lbl)
	caja.add_child(_label(metal.to_upper(), 12, color))
	return caja


func _boton(texto: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = texto
	btn.custom_minimum_size = Vector2(230, 48)
	btn.add_theme_font_size_override("font_size", 18)
	if _font_bold:
		btn.add_theme_font_override("font", _font_bold)
	for estado in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color.lightened(0.15) if estado in ["hover", "focus"] else color
		s.set_corner_radius_all(10)
		s.set_border_width_all(2)
		s.border_color = COLOR_GOLD if estado in ["hover", "focus"] else Color(1, 1, 1, 0.15)
		btn.add_theme_stylebox_override(estado, s)
	return btn


# ─── Animación ───────────────────────────────────────────────────────────────

func _animar_entrada() -> void:
	Sonido.efecto("aprobada")
	_confeti.explotar()

	var t := create_tween()
	t.tween_property(_fondo, "color:a", 0.82, 0.5)
	t.parallel().tween_property(_rayos, "modulate:a", 1.0, 1.0)

	var hijos := _contenido.get_children()
	# Trofeo y título entran con rebote.
	for i in 2:
		var nodo: Control = hijos[i]
		t.tween_callback(func():
			nodo.pivot_offset = nodo.size / 2.0
			nodo.scale = Vector2(0.3, 0.3)
		)
		t.tween_property(nodo, "modulate:a", 1.0, 0.25)
		t.parallel().tween_property(nodo, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(hijos[2], "modulate:a", 1.0, 0.35)
	t.tween_callback(func(): _fila_medallas.modulate.a = 1.0)

	# Las medallas, una a una; la de platino, con una segunda explosión.
	var medallas := _fila_medallas.get_children()
	for i in medallas.size():
		var m: Control = medallas[i]
		var ultima := i == medallas.size() - 1
		t.tween_interval(0.35 if not ultima else 0.6)
		t.tween_callback(func():
			m.pivot_offset = m.size / 2.0
			m.scale = Vector2(0.2, 0.2)
			Sonido.efecto("desbloqueo" if ultima else "acierto")
			if ultima:
				_confeti.explotar()
		)
		t.tween_property(m, "modulate:a", 1.0, 0.2)
		t.parallel().tween_property(m, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# El puntaje total cuenta hacia arriba.
	t.tween_property(hijos[4], "modulate:a", 1.0, 0.3)
	t.tween_method(func(v: float): _puntaje_lbl.text = "Puntaje total: %d pts" % int(v),
			0.0, float(ProgressionManager.get_total_score()), 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(hijos[5], "modulate:a", 1.0, 0.5)
	t.tween_property(_botones, "modulate:a", 1.0, 0.4)
	t.tween_callback(func():
		DialogFocus.enfocar(_botones.get_child(1) as Button)
		_latir(hijos[0])
	)


## El trofeo late mientras la pantalla sigue abierta. Con escala y no con
## posición: el contenedor recoloca a sus hijos y anularía el movimiento.
func _latir(trofeo: Control) -> void:
	var latido := create_tween().set_loops()
	latido.tween_property(trofeo, "scale", Vector2(1.08, 1.08), 0.7).set_trans(Tween.TRANS_SINE)
	latido.tween_property(trofeo, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)


func _on_ver_medallas() -> void:
	var escena = load(PANEL_ACHIEVEMENTS)
	_cerrar()
	if escena:
		get_tree().root.add_child(escena.instantiate())


func _cerrar() -> void:
	if _cerrando:
		return
	_cerrando = true
	Sonido.efecto("cerrar")
	var t := create_tween().set_parallel(true)
	for nodo in [_fondo, _rayos, _contenido, _confeti]:
		t.tween_property(nodo, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(func():
		cerrada.emit()
		queue_free()
	)


func _unhandled_input(event: InputEvent) -> void:
	# Mientras está abierta, nada de lo que hay debajo recibe teclas.
	if event is InputEventKey:
		get_viewport().set_input_as_handled()


# ─── Dibujo: confeti y rayos ─────────────────────────────────────────────────

## Papelitos que salen disparados desde abajo y caen girando.
class _Confeti extends Control:
	var colores: Array[Color] = []
	var _piezas: Array[Dictionary] = []

	func explotar() -> void:
		var tam := get_viewport_rect().size
		for i in 140:
			var desde_izquierda := i % 2 == 0
			_piezas.append({
				"pos": Vector2(tam.x * (0.08 if desde_izquierda else 0.92), tam.y + 10),
				"vel": Vector2(randf_range(150, 520) * (1 if desde_izquierda else -1), randf_range(-950, -520)),
				"rot": randf() * TAU,
				"giro": randf_range(-8, 8),
				"color": colores[randi() % colores.size()],
				"tam": Vector2(randf_range(6, 12), randf_range(10, 18)),
			})

	func _process(delta: float) -> void:
		if _piezas.is_empty():
			return
		var alto := get_viewport_rect().size.y
		for p in _piezas:
			var vel: Vector2 = p["vel"]
			vel.y += 620.0 * delta
			vel.x *= 0.99
			p["vel"] = vel
			p["pos"] = p["pos"] + vel * delta
			p["rot"] = p["rot"] + p["giro"] * delta
		_piezas = _piezas.filter(func(p): return p["pos"].y < alto + 40 or p["vel"].y < 0)
		queue_redraw()

	func _draw() -> void:
		for p in _piezas:
			# Achatar con el seno del giro simula el papel dando vueltas.
			var ancho: float = p["tam"].x * absf(sin(p["rot"]))
			draw_set_transform(p["pos"], p["rot"], Vector2.ONE)
			draw_rect(Rect2(Vector2(-ancho / 2.0, -p["tam"].y / 2.0), Vector2(ancho, p["tam"].y)), p["color"])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Rayos dorados que giran despacio detrás del trofeo.
class _Rayos extends Control:
	var foco: Control
	var _angulo := 0.0

	func _process(delta: float) -> void:
		_angulo += delta * 0.25
		queue_redraw()

	func _draw() -> void:
		var tam := get_viewport_rect().size
		var centro := Vector2(tam.x / 2.0, tam.y * 0.3)
		if is_instance_valid(foco):
			centro = foco.get_global_rect().get_center()
		var largo := tam.length()
		for i in 12:
			var a := _angulo + i * TAU / 12.0
			var puntos := PackedVector2Array([
				centro,
				centro + Vector2.from_angle(a - 0.09) * largo,
				centro + Vector2.from_angle(a + 0.09) * largo,
			])
			draw_colored_polygon(puntos, Color(1.0, 0.85, 0.35, 0.07))
		draw_circle(centro, 120.0, Color(1.0, 0.85, 0.35, 0.08))
