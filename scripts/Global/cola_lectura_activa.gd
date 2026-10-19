## Cola de peticiones de la lectura activa (la usa ReadingProgressManager).
##
## Hay un solo HTTPRequest, así que va una petición en vuelo cada vez. Antes,
## lo que llegaba mientras tanto se descartaba: un guardado tras una respuesta
## se perdía, una limpieza al terminar la lectura no se hacía y la consulta de
## una estación se quedaba sin respuesta. Ahora todo espera su turno, con estas
## reglas:
##   save:  si la última pendiente es otro save, se sustituye su cuerpo (gana el
##          último estado); si no, se añade al final.
##   clear: quita los save pendientes (ya no hay nada que guardar) y se añade si
##          no hay otro clear pendiente.
##   check / load: si ya hay uno igual pendiente, no se repite.
class_name ColaLecturaActiva
extends RefCounted

var _pendientes: Array = []
var _en_vuelo: Dictionary = {}


func pedir(accion: String, cuerpo: String = "") -> void:
	match accion:
		"save":
			if not _pendientes.is_empty() and _pendientes[-1]["accion"] == "save":
				_pendientes[-1]["cuerpo"] = cuerpo
			else:
				_pendientes.append({"accion": "save", "cuerpo": cuerpo})
		"clear":
			_pendientes = _pendientes.filter(func(p): return p["accion"] != "save")
			if not _pendientes.any(func(p): return p["accion"] == "clear"):
				_pendientes.append({"accion": "clear", "cuerpo": ""})
		_:
			if not _pendientes.any(func(p): return p["accion"] == accion):
				_pendientes.append({"accion": accion, "cuerpo": ""})


## La próxima petición que hay que lanzar ({"accion", "cuerpo"}), que queda en
## vuelo, o {} si está vacía o ya hay una en vuelo.
func siguiente() -> Dictionary:
	if ocupada() or _pendientes.is_empty():
		return {}
	_en_vuelo = _pendientes.pop_front()
	return _en_vuelo


## La petición en vuelo terminó (bien o mal).
func terminar() -> void:
	_en_vuelo = {}


func ocupada() -> bool:
	return not _en_vuelo.is_empty()


func pendientes() -> Array:
	return _pendientes.duplicate(true)
