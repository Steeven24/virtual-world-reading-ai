## comic_creditos.gd
## Pantalla de créditos de la zona de cómics: cumple la atribución que exige la
## licencia CC BY 4.0 de Pepper&Carrot. Los datos salen de ComicLibrary.atribucion()
## (catalogo.json), no están escritos aquí. Emite cerrado; quien la abre la libera.
extends CanvasLayer

## El alumno pulsó Cerrar o Escape.
signal cerrado

@onready var _obra: Label = %Obra
@onready var _autor: Label = %Autor
@onready var _licencia: Label = %Licencia
@onready var _enlace: LinkButton = %Enlace
@onready var _boton_cerrar: Button = %BotonCerrar


func _ready() -> void:
	var atrib := ComicLibrary.atribucion()
	_obra.text = "«%s» (Pepper&Carrot)" % atrib.get("titulo", "")
	_autor.text = "Autor: %s" % atrib.get("autor", "")
	_licencia.text = "Licencia: %s" % atrib.get("licencia", "")
	_enlace.text = str(atrib.get("enlace", ""))
	_enlace.uri = _enlace.text
	_boton_cerrar.pressed.connect(func(): cerrado.emit())
	# Sin foco: así Escape sigue llegando a _unhandled_input.
	_boton_cerrar.focus_mode = Control.FOCUS_NONE
	_enlace.focus_mode = Control.FOCUS_NONE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cerrado.emit()
		get_viewport().set_input_as_handled()
