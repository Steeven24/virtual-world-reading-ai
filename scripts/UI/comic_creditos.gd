## comic_creditos.gd
## Pantalla de créditos de la zona de cómics: cumple la atribución que exige la
## licencia CC BY 4.0 de Pepper&Carrot. Los datos salen de ComicLibrary.atribucion()
## (catalogo.json), no están escritos aquí. Emite cerrado; quien la abre la libera.
extends CanvasLayer

## El alumno pulsó Cerrar o Escape.
signal cerrado

## Se muestra en lugar de un dato de atribución que falte.
const TEXTO_RESERVA := "[dato no disponible]"

@onready var _obra: Label = %Obra
@onready var _autor: Label = %Autor
@onready var _licencia: Label = %Licencia
@onready var _enlace: LinkButton = %Enlace
@onready var _boton_cerrar: Button = %BotonCerrar


func _ready() -> void:
	mostrar(ComicLibrary.atribucion())
	_boton_cerrar.pressed.connect(func(): cerrado.emit())
	# Sin foco: así Escape sigue llegando a _unhandled_input.
	_boton_cerrar.focus_mode = Control.FOCUS_NONE
	_enlace.focus_mode = Control.FOCUS_NONE


## Pinta la atribución. Si falta algún dato se muestra un texto de reserva visible
## y se avisa: una atribución en blanco incumpliría la licencia en silencio.
func mostrar(atrib: Dictionary) -> void:
	var faltan: Array[String] = []
	var datos := {}
	for clave in ["autor", "titulo", "titulo_original", "licencia", "enlace"]:
		var valor := str(atrib.get(clave, "")).strip_edges()
		if valor.is_empty():
			faltan.append(clave)
			valor = TEXTO_RESERVA
		datos[clave] = valor
	if not faltan.is_empty():
		push_warning("[ComicCreditos] Faltan datos de atribución: %s" % ", ".join(faltan))
	_obra.text = "«%s» (%s)" % [datos["titulo"], datos["titulo_original"]]
	_autor.text = "Autor: %s" % datos["autor"]
	_licencia.text = "Licencia: %s" % datos["licencia"]
	_enlace.text = datos["enlace"]
	_enlace.uri = "" if faltan.has("enlace") else datos["enlace"]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cerrado.emit()
		get_viewport().set_input_as_handled()
