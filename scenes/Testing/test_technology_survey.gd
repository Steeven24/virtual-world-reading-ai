## Prueba estructural y de navegación del formulario, sin red ni sesión real.
extends Node

const SCENE := "res://scenes/UI/technology_survey.tscn"
var _fails := 0


func check(condition: bool, description: String) -> void:
	if condition:
		print("OK    - %s" % description)
	else:
		_fails += 1
		print("FALLO - %s" % description)


func _ready() -> void:
	print("USERDIR: %s" % OS.get_user_data_dir())
	if not OS.get_user_data_dir().contains("vw_prueba_encuesta"):
		push_error("ABORTADO: el user:// no está aislado.")
		get_tree().quit(2)
		return
	var packed = load(SCENE)
	if packed == null:
		print("RESULTADO: ROJO (no carga)")
		get_tree().quit(1)
		return
	var survey = packed.instantiate()
	add_child(survey)
	await get_tree().process_frame
	check(survey.PAGINAS.size() == 4, "el instrumento se reparte en cuatro secciones")
	var total := 0
	for page in survey.PAGINAS:
		total += page["items"].size()
	check(total == 22, "hay exactamente 22 ítems SUS + TAM")
	check(survey.PAGINAS[0]["scale"] == 5 and survey.PAGINAS[2]["scale"] == 7,
		"SUS usa escala 1-5 y TAM escala 1-7")
	survey._go_next()
	check(survey.current_page() == 0 and not survey.get_node("Margin/Panel/Padding/Content/Error").text.is_empty(),
		"no avanza con respuestas incompletas")
	for item in survey.PAGINAS[0]["items"]:
		survey._select_answer(item[0], 3)
	survey._go_next()
	check(survey.current_page() == 1 and survey.answer_count() == 5,
		"avanza al completar la sección y conserva respuestas")
	check(survey.get_node("Margin/Panel/Padding/Content/Actions/Close").text == "Responder después",
		"permite cerrar sin presentar los cómics como desbloqueados")
	print("RESULTADO: %s (%d fallos)" % ["VERDE" if _fails == 0 else "ROJO", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
