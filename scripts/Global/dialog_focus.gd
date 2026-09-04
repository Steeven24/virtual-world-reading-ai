## Utilidades de foco para los cuadros de diálogo y paneles modales del juego.
##
## Los diálogos del proyecto (AcceptDialog / ConfirmationDialog) se muestran con
## show() y se colocan a mano para poder animarlos entrando desde abajo. Eso se
## salta el POST_POPUP que Godot usa normalmente para dejar el foco en el botón
## de aceptar, y sin foco el cuadro solo respondía al ratón: las flechas no
## movían nada y Enter o E no pulsaban ningún botón. Lo mismo ocurría en los
## paneles de tutorial y guía, que nunca enfocaban ninguno de sus botones.
##
## preparar() arregla los diálogos; encadenar() y enfocar() hacen lo propio con
## los paneles construidos con Control.
class_name DialogFocus
extends RefCounted

const COLOR_FOCO := Color(0.95, 0.85, 0.4, 1.0)


## Deja un diálogo listo para manejarse con teclado: foco en aceptar, flechas
## entre los botones y contorno visible.
## Llamar DESPUÉS de show()/popup(), cuando los botones ya están en el árbol.
static func preparar(dialog: AcceptDialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return

	var botones := _botones(dialog)
	if botones.is_empty():
		return

	encadenar(botones)

	# Un frame de margen: si el diálogo acaba de mostrarse, sus botones aún no
	# tienen tamaño y el foco no se sostiene sobre un Control sin rectángulo.
	var arbol := dialog.get_tree()
	if arbol:
		await arbol.process_frame

	if not is_instance_valid(dialog) or not dialog.visible:
		return
	enfocar(dialog.get_ok_button())


## Encadena un grupo de botones para que las flechas salten entre ellos en
## círculo, y les pinta el contorno de foco.
## Con vertical = true encadena arriba/abajo (listas de opciones, como las del
## quiz) en lugar de izquierda/derecha (filas de botones de un diálogo).
static func encadenar(botones: Array[Button], vertical: bool = false) -> void:
	for boton in botones:
		if not is_instance_valid(boton):
			continue
		if not boton.disabled:
			boton.focus_mode = Control.FOCUS_ALL
		marcar(boton)

	if botones.size() < 2:
		return

	for i in botones.size():
		var actual: Button = botones[i]
		if not is_instance_valid(actual):
			continue
		var anterior: Button = botones[(i - 1 + botones.size()) % botones.size()]
		var siguiente: Button = botones[(i + 1) % botones.size()]
		if not is_instance_valid(anterior) or not is_instance_valid(siguiente):
			continue
		var ruta_anterior := actual.get_path_to(anterior)
		var ruta_siguiente := actual.get_path_to(siguiente)
		if vertical:
			actual.focus_neighbor_top = ruta_anterior
			actual.focus_neighbor_bottom = ruta_siguiente
		else:
			actual.focus_neighbor_left = ruta_anterior
			actual.focus_neighbor_right = ruta_siguiente
		actual.focus_previous = ruta_anterior
		actual.focus_next = ruta_siguiente


## Pone el foco en el botón dado, si sigue siendo utilizable.
static func enfocar(boton: Button) -> void:
	if not is_instance_valid(boton) or boton.disabled:
		return
	if boton.focus_mode == Control.FOCUS_NONE:
		boton.focus_mode = Control.FOCUS_ALL
	boton.grab_focus()


## Contorno dorado sobre el botón enfocado. Sin esto el jugador mueve el foco
## con las flechas pero no ve dónde está.
static func marcar(boton: Button) -> void:
	if not is_instance_valid(boton):
		return
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.95, 0.85, 0.4, 0.13)
	estilo.set_border_width_all(3)
	estilo.border_color = COLOR_FOCO
	estilo.set_corner_radius_all(8)
	estilo.set_expand_margin_all(2.0)
	boton.add_theme_stylebox_override("focus", estilo)
	boton.add_theme_color_override("font_focus_color", COLOR_FOCO)


## Botones de acción del diálogo, de izquierda a derecha.
static func _botones(dialog: AcceptDialog) -> Array[Button]:
	var lista: Array[Button] = []
	var ok := dialog.get_ok_button()
	if is_instance_valid(ok):
		lista.append(ok)
	if dialog is ConfirmationDialog:
		var cancelar := (dialog as ConfirmationDialog).get_cancel_button()
		if is_instance_valid(cancelar):
			lista.append(cancelar)
	return lista
