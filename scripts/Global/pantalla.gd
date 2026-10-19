## Pantalla completa: activada por defecto y desactivable desde el menú ⚙️ del
## lobby.
##
## La preferencia es del equipo, no de la cuenta: se guarda en
## user://progress.cfg, sección "equipo", fuera de las claves por cuenta de
## Ajustes. Así el login ya la respeta y no cambia al entrar otro alumno.
##
## En la web el navegador solo deja entrar en pantalla completa tras una
## interacción: se pide con el primer clic o tecla de cada visita. Si el alumno
## sale con el navegador, no se le vuelve a forzar hasta la visita siguiente.
## Desde el editor no se fuerza nunca.
##
## El juego usa Esc para cerrar paneles y diálogos. En Chrome y Edge se bloquea
## Esc (Keyboard Lock) mientras dura la pantalla completa: sigue llegando al
## juego y para salir se mantiene pulsado, como indica el navegador.
##
## Registrar como Autoload: Project Settings → Autoload → "Pantalla"
extends Node

## Emitida al aplicar un modo, por el menú o por la entrada automática.
signal cambiada(completa: bool)

const SECCION := "equipo"
const CLAVE := "pantalla_completa"

## Archivo de preferencias. Las pruebas lo cambian para no tocar el real.
var ruta_archivo: String = "user://progress.cfg"

## En la web, esperando la primera pulsación de la visita para entrar.
var _pendiente_web := false


func _ready() -> void:
	if OS.has_feature("editor") or not preferencia():
		return
	if OS.has_feature("web"):
		_pendiente_web = true
	else:
		aplicar(true)


func _input(event: InputEvent) -> void:
	if not _pendiente_web:
		return
	var es_pulsacion := event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch
	if es_pulsacion and event.is_pressed():
		_pendiente_web = false
		aplicar(true)


# ─── API pública ─────────────────────────────────────────────────────────────

## ¿Quiere este equipo jugar en pantalla completa? Sin nada guardado, sí.
func preferencia() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(ruta_archivo) != OK:
		return true
	return bool(cfg.get_value(SECCION, CLAVE, true))


## Guarda la preferencia del equipo y la aplica al momento.
func fijar_preferencia(completa: bool) -> void:
	var cfg := ConfigFile.new()
	# Se carga antes de escribir para no pisar las demás secciones.
	cfg.load(ruta_archivo)
	cfg.set_value(SECCION, CLAVE, completa)
	cfg.save(ruta_archivo)
	_pendiente_web = false
	aplicar(completa)


func es_completa() -> bool:
	var modo := DisplayServer.window_get_mode()
	return modo == DisplayServer.WINDOW_MODE_FULLSCREEN or modo == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func aplicar(completa: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if completa else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if OS.has_feature("web"):
		var codigo := "navigator.keyboard && navigator.keyboard.lock && navigator.keyboard.lock(['Escape']).catch(function () {})" \
				if completa else "navigator.keyboard && navigator.keyboard.unlock && navigator.keyboard.unlock()"
		JavaScriptBridge.eval(codigo, true)
	cambiada.emit(completa)
