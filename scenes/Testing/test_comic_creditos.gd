## Prueba de la pantalla de créditos de los cómics. Se lanza en headless:
##   Godot --headless --path <copia aislada> --quit-after 60000 res://scenes/Testing/test_comic_creditos.tscn
## IMPORTANTE: ejecutar sobre una copia con config/use_custom_user_dir, nunca sobre
## el user:// real. La prueba aborta si el user:// no es el aislado o hay sesión.
extends Node

const ESCENA_CREDITOS := "res://scenes/UI/comic_creditos.tscn"
const ESCENA_CATALOGO := "res://scenes/UI/comic_catalogo.tscn"

var _fallos := 0


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK    - %s" % descripcion)
	else:
		_fallos += 1
		print("FALLO - %s" % descripcion)


func _ready() -> void:
	print("USERDIR: %s" % OS.get_user_data_dir())
	if not OS.get_user_data_dir().contains("vw_prueba_t9"):
		push_error("ABORTADO: el user:// no es el aislado de la prueba.")
		get_tree().quit(2)
		return
	if AuthManager.is_authenticated or not AuthManager.auth_token.is_empty():
		push_error("ABORTADO: hay una sesión real restaurada.")
		get_tree().quit(2)
		return
	if not ResourceLoader.exists(ESCENA_CREDITOS):
		print("FALLO - falta la escena de créditos")
		print("RESULTADO: ROJO (escena ausente)")
		get_tree().quit(1)
		return
	await _probar()
	print("RESULTADO: %s (%d fallos)" % ["VERDE" if _fallos == 0 else "ROJO", _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)


func _esperar() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _texto_visible(raiz: Node) -> String:
	var t := ""
	for n in raiz.find_children("*", "Label", true, false):
		t += (n as Label).text + "\n"
	for n in raiz.find_children("*", "RichTextLabel", true, false):
		t += (n as RichTextLabel).text + "\n"
	for n in raiz.find_children("*", "LinkButton", true, false):
		t += (n as LinkButton).text + "\n"
	return t


func _probar() -> void:
	var atrib := ComicLibrary.atribucion()
	_comprobar(not atrib.is_empty(), "ComicLibrary.atribucion() trae datos")

	# Escena suelta: el texto sale de atribucion().
	var creditos: Node = load(ESCENA_CREDITOS).instantiate()
	add_child(creditos)
	await _esperar()
	var texto := _texto_visible(creditos)
	for clave in ["autor", "titulo", "titulo_original", "licencia", "enlace"]:
		_comprobar(texto.contains(str(atrib.get(clave, "#"))), "los créditos muestran «%s»: %s" % [clave, atrib.get(clave)])
	_comprobar(texto.contains("CC BY 4.0"), "los créditos muestran «CC BY 4.0»")
	_comprobar(texto.contains("https://"), "los créditos muestran un enlace")
	var cerrado := [false]
	creditos.cerrado.connect(func(): cerrado[0] = true)
	var b: Button = creditos.get_node("%BotonCerrar")
	_comprobar(b.focus_mode == Control.FOCUS_NONE, "el botón Cerrar no roba el foco")
	b.pressed.emit()
	_comprobar(cerrado[0], "Cerrar emite cerrado")
	# Atribución incompleta: texto de reserva visible, nunca en blanco.
	creditos.mostrar({"autor": "Alguien"})
	texto = _texto_visible(creditos)
	_comprobar(texto.contains("Alguien"), "con datos parciales se muestra lo que hay")
	_comprobar(texto.contains("Licencia: [dato no disponible]"), "licencia ausente: texto de reserva")
	_comprobar(texto.contains("[dato no disponible]"), "título y enlace ausentes: texto de reserva")
	creditos.mostrar({})
	_comprobar(not _texto_visible(creditos).contains("Autor: 
"), "atribución vacía no deja «Autor:» en blanco")
	creditos.queue_free()
	await _esperar()

	# Desde el catálogo.
	var cat: Node = load(ESCENA_CATALOGO).instantiate()
	add_child(cat)
	await _esperar()
	var boton: Button = cat.get_node_or_null("%BotonCreditos")
	_comprobar(boton != null, "el catálogo tiene BotonCreditos")
	if boton == null:
		return
	_comprobar(boton.focus_mode == Control.FOCUS_NONE, "BotonCreditos sin foco")
	_comprobar(cat.creditos_abiertos() == null, "al inicio no hay créditos abiertos")
	boton.pressed.emit()
	await _esperar()
	var abiertos: Node = cat.creditos_abiertos()
	_comprobar(abiertos != null, "pulsar el botón abre los créditos")
	if abiertos != null:
		_comprobar(_texto_visible(abiertos).contains("CC BY 4.0"), "los créditos abiertos muestran CC BY 4.0")
	boton.pressed.emit()
	await _esperar()
	_comprobar(cat.creditos_abiertos() == abiertos, "no se abre un segundo panel")
	var cat_cerrado := [false]
	cat.cerrado.connect(func(): cat_cerrado[0] = true)
	await _pulsar("ui_cancel")
	await _esperar()
	_comprobar(cat.creditos_abiertos() == null, "Escape cierra los créditos")
	_comprobar(not cat_cerrado[0], "Escape con créditos abiertos no cierra el catálogo")
	boton.pressed.emit()
	await _esperar()
	cat.creditos_abiertos().get_node("%BotonCerrar").pressed.emit()
	await _esperar()
	_comprobar(cat.creditos_abiertos() == null, "el botón Cerrar cierra los créditos")
	cat.queue_free()


func _pulsar(accion: String) -> void:
	var ev := InputEventAction.new()
	ev.action = accion
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	ev = InputEventAction.new()
	ev.action = accion
	ev.pressed = false
	Input.parse_input_event(ev)
