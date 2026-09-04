## Guardián de sesión única en el navegador.
##
## El juego se publica en web, donde nada impide abrir el mismo enlace en varias
## pestañas. Dos ventanas del mismo alumno comparten token y progreso, así que
## acaban pisándose: una guarda la lectura activa que la otra acaba de terminar,
## las puntuaciones se solapan y el estado deja de tener sentido.
##
## Esta guardia toma un cerrojo en localStorage con un latido periódico. La
## primera pestaña se queda con el turno; las demás se bloquean con un aviso
## hasta que la dueña se cierre. Si una pestaña se cierra o se cuelga, el latido
## caduca (STALE_MS) y otra puede reclamar el turno.
##
## Fuera de la web (editor y escritorio) no hace nada: no hay pestañas.
##
## Complementa —no sustituye— al control del servidor: session_version invalida
## la sesión anterior cuando alguien entra desde otro navegador o equipo, donde
## localStorage ya no alcanza.
##
## Registrar como Autoload: Project Settings → Autoload → "SessionGuard"
extends Node

# ─── Señales ─────────────────────────────────────────────────────────────────

## Emitida cuando esta ventana gana o pierde el turno.
signal ownership_changed(es_duena: bool)

# ─── Constantes ──────────────────────────────────────────────────────────────

const OVERLAY_SCENE: String = "res://scenes/UI/duplicate_tab_overlay.tscn"

## Cada cuánto se consulta al navegador el estado del cerrojo.
const INTERVALO_COMPROBACION: float = 1.2

## Código que instala el cerrojo en el navegador. Se inyecta una sola vez por
## pestaña y devuelve el estado actual: "owner" o "duplicate".
##
## STALE: milisegundos sin latido tras los que se da la pestaña por muerta.
## BEAT: cada cuánto refresca el latido la pestaña dueña.
const JS_GUARDIA: String = """
(function(){
	var K = 'vw_active_tab', STALE = 6000, BEAT = 2000;
	if (!window.__vwGuard) {
		var g = {
			id: Date.now().toString(36) + Math.random().toString(36).slice(2),
			state: 'unknown'
		};
		window.__vwGuard = g;
		g.read = function(){
			try { return JSON.parse(localStorage.getItem(K) || 'null'); } catch (e) { return null; }
		};
		g.write = function(o){
			try { localStorage.setItem(K, JSON.stringify(o)); } catch (e) {}
		};
		g.claim = function(){
			var cur = g.read(), now = Date.now();
			if (cur && cur.id !== g.id && (now - (cur.t || 0)) < STALE) {
				g.state = 'duplicate';
				return g.state;
			}
			g.write({ id: g.id, t: now });
			var back = g.read();
			g.state = (back && back.id === g.id) ? 'owner' : 'duplicate';
			return g.state;
		};
		g.beat = function(){
			if (g.state !== 'owner') { return; }
			var cur = g.read(), now = Date.now();
			if (cur && cur.id !== g.id && (now - (cur.t || 0)) < STALE) {
				g.state = 'duplicate';
				return;
			}
			g.write({ id: g.id, t: now });
		};
		g.release = function(){
			var cur = g.read();
			if (cur && cur.id === g.id) {
				try { localStorage.removeItem(K); } catch (e) {}
			}
		};
		g.claim();
		g.timer = setInterval(g.beat, BEAT);
		window.addEventListener('pagehide', g.release);
		window.addEventListener('beforeunload', g.release);
	}
	return window.__vwGuard.state;
})()
"""

const JS_ESTADO: String = "window.__vwGuard ? window.__vwGuard.state : 'off'"
const JS_RECLAMAR: String = "window.__vwGuard ? window.__vwGuard.claim() : 'off'"

# ─── Estado ──────────────────────────────────────────────────────────────────

## False mientras otra ventana tenga el turno.
var es_duena: bool = true

var _activo: bool = false
var _overlay: CanvasLayer = null

# ─── Ciclo de vida ───────────────────────────────────────────────────────────

func _ready() -> void:
	_activo = OS.has_feature("web")
	if not _activo:
		print("[SessionGuard] Fuera de la web: control de ventana única desactivado")
		return

	var estado := str(JavaScriptBridge.eval(JS_GUARDIA, true))
	_aplicar_estado(estado)

	var temporizador := Timer.new()
	temporizador.wait_time = INTERVALO_COMPROBACION
	temporizador.autostart = true
	temporizador.timeout.connect(_comprobar)
	add_child(temporizador)

# ─── API pública ─────────────────────────────────────────────────────────────

## Vuelve a intentar tomar el turno. La usa el aviso de ventana duplicada
## cuando el jugador ya ha cerrado la otra pestaña.
func reintentar() -> bool:
	if not _activo:
		return true
	_aplicar_estado(str(JavaScriptBridge.eval(JS_RECLAMAR, true)))
	return es_duena

# ─── Interno ─────────────────────────────────────────────────────────────────

func _comprobar() -> void:
	if not _activo:
		return
	_aplicar_estado(str(JavaScriptBridge.eval(JS_ESTADO, true)))


func _aplicar_estado(estado: String) -> void:
	# "off" solo aparece si la inyección falló; ante la duda se deja jugar en
	# vez de bloquear a alguien por un fallo del navegador.
	var nueva_duena := estado != "duplicate"
	if nueva_duena == es_duena:
		return

	es_duena = nueva_duena
	if es_duena:
		_ocultar_aviso()
		print("[SessionGuard] Esta ventana toma el turno")
	else:
		_mostrar_aviso()
		print("[SessionGuard] El juego ya está abierto en otra ventana")
	ownership_changed.emit(es_duena)


func _mostrar_aviso() -> void:
	if _overlay and is_instance_valid(_overlay):
		return

	var packed: PackedScene = load(OVERLAY_SCENE)
	if packed == null:
		push_error("[SessionGuard] No se pudo cargar el aviso de ventana duplicada.")
		return

	_overlay = packed.instantiate()
	get_tree().root.add_child(_overlay)


func _ocultar_aviso() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
