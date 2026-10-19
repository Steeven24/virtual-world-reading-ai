## Panel «Crear cuenta» del login.
##
## Pide nombre, correo y la contraseña dos veces, y la valida con las mismas
## reglas que la API (/auth/register: 8 caracteres o más, una mayúscula y un
## número). Solo emite registro_pedido cuando todo está bien; la pantalla de
## login hace la petición, aplica el estilo de sus campos y botones, y muestra
## los errores que devuelva la API con mostrar_error().
class_name PanelRegistro
extends PanelContainer

signal registro_pedido(nombre: String, correo: String, clave: String)
signal volver_pedido

const PATRON_CORREO := "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"

var nombre_input: LineEdit
var correo_input: LineEdit
var clave_input: LineEdit
var repetir_input: LineEdit
var ojo_button: Button
var crear_button: Button
var volver_button: Button
var titulo_label: Label

var _error_label: Label
var _cargando_label: Label


func _init() -> void:
	name = "PanelRegistro"
	visible = false
	_construir()


## Texto del primer problema que impide crear la cuenta, o "" si no hay.
static func validar(nombre: String, correo: String, clave: String, repetida: String) -> String:
	if nombre.strip_edges().is_empty():
		return "Escribe tu nombre."
	var patron := RegEx.create_from_string(PATRON_CORREO)
	if patron.search(correo.strip_edges()) == null:
		return "Escribe un correo válido."
	if clave.length() < 8:
		return "La contraseña debe tener al menos 8 caracteres."
	if clave.to_lower() == clave:
		return "La contraseña debe tener al menos una mayúscula."
	if not RegEx.create_from_string("[0-9]").search(clave):
		return "La contraseña debe tener al menos un número."
	if clave != repetida:
		return "Las contraseñas no coinciden."
	return ""


func mostrar_error(texto: String) -> void:
	_error_label.text = texto


func set_cargando(activo: bool) -> void:
	_cargando_label.visible = activo
	crear_button.disabled = activo
	volver_button.disabled = activo
	if activo:
		_error_label.text = ""


## Campos de texto, para que la pantalla de login les ponga su estilo.
func campos() -> Array[LineEdit]:
	return [nombre_input, correo_input, clave_input, repetir_input]


func vaciar() -> void:
	for campo in campos():
		campo.text = ""
	_error_label.text = ""
	set_cargando(false)


# ─── Construcción ────────────────────────────────────────────────────────────

func _construir() -> void:
	var margen := MarginContainer.new()
	for lado in ["margin_left", "margin_right"]:
		margen.add_theme_constant_override(lado, 32)
	for lado in ["margin_top", "margin_bottom"]:
		margen.add_theme_constant_override(lado, 24)
	add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	caja.custom_minimum_size = Vector2(380, 0)
	margen.add_child(caja)

	titulo_label = _etiqueta("📝 Crear cuenta", 24)
	titulo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(titulo_label)

	caja.add_child(_etiqueta("Nombre (así saldrás en el ranking)", 14))
	nombre_input = _campo("NombreInput", "Tu nombre")
	nombre_input.max_length = 100
	caja.add_child(nombre_input)

	caja.add_child(_etiqueta("✉️ Correo electrónico", 14))
	correo_input = _campo("CorreoInput", "correo@ejemplo.com")
	caja.add_child(correo_input)

	caja.add_child(_etiqueta("Contraseña (8 o más, con una mayúscula y un número)", 14))
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 6)
	clave_input = _campo("ClaveInput", "Contraseña")
	clave_input.secret = true
	clave_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(clave_input)
	ojo_button = Button.new()
	ojo_button.name = "OjoButton"
	ojo_button.toggle_mode = true
	ojo_button.text = "👁"
	ojo_button.tooltip_text = "Mostrar contraseña"
	ojo_button.custom_minimum_size = Vector2(44, 0)
	ojo_button.toggled.connect(_on_ojo)
	fila.add_child(ojo_button)
	caja.add_child(fila)

	caja.add_child(_etiqueta("Repetir contraseña", 14))
	repetir_input = _campo("RepetirInput", "Repite la contraseña")
	repetir_input.secret = true
	repetir_input.text_submitted.connect(func(_texto: String): _on_crear())
	caja.add_child(repetir_input)

	_error_label = _etiqueta("", 14)
	_error_label.name = "ErrorRegistro"
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	caja.add_child(_error_label)

	_cargando_label = _etiqueta("Creando tu cuenta...", 14)
	_cargando_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cargando_label.visible = false
	caja.add_child(_cargando_label)

	crear_button = Button.new()
	crear_button.name = "CrearButton"
	crear_button.text = "Crear cuenta"
	crear_button.custom_minimum_size = Vector2(0, 44)
	crear_button.pressed.connect(_on_crear)
	caja.add_child(crear_button)

	volver_button = Button.new()
	volver_button.name = "VolverButton"
	volver_button.text = "Ya tengo cuenta"
	volver_button.pressed.connect(func(): volver_pedido.emit())
	caja.add_child(volver_button)


func _etiqueta(texto: String, tam: int) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", tam)
	return etiqueta


func _campo(nombre: String, sugerencia: String) -> LineEdit:
	var campo := LineEdit.new()
	campo.name = nombre
	campo.placeholder_text = sugerencia
	campo.custom_minimum_size = Vector2(0, 40)
	return campo


func _on_ojo(mostrar: bool) -> void:
	clave_input.secret = not mostrar
	repetir_input.secret = not mostrar
	ojo_button.text = "🙈" if mostrar else "👁"
	ojo_button.tooltip_text = "Ocultar contraseña" if mostrar else "Mostrar contraseña"


func _on_crear() -> void:
	var problema := validar(nombre_input.text, correo_input.text, clave_input.text, repetir_input.text)
	if not problema.is_empty():
		mostrar_error(problema)
		return
	_error_label.text = ""
	registro_pedido.emit(nombre_input.text.strip_edges(), correo_input.text.strip_edges(), clave_input.text)
