## Controlador global de progresión y desbloqueo de niveles.
## Mantiene el mejor puntaje por tipología, verifica umbrales de desbloqueo
## y controla qué tipologías están disponibles para el jugador.
##
## Registrar como Autoload (escena): Project Settings → Autoload → "ProgressionManager"
##
## Fase actual: Estado temporal en memoria (se reinicia al cerrar el juego).
## Fase futura: Persistencia por usuario (archivo local → API + PostgreSQL).
extends Node

# ─── Señales ─────────────────────────────────────────────────────────────────

## Emitida cuando se desbloquea una nueva tipología.
signal level_unlocked(typology: String)

## Emitida cuando cambia cualquier dato de progresión (puntaje, desbloqueo).
signal progression_changed

# ─── Constantes ──────────────────────────────────────────────────────────────

## Orden de dificultad de las tipologías (de más fácil a más difícil).
## Instructivo ya no forma parte de la progresión: su escenario es ahora la
## zona de práctica (GameSession.PRACTICE_SCENES).
## Debe coincidir con DIFFICULTY_ORDER de la API (api/game_rules.py).
const DIFFICULTY_ORDER: Array[String] = [
	"Narrativo", "Descriptivo", "Argumentativo", "Expositivo"
]

## Nombre legible de cada dificultad (para UI).
const DIFFICULTY_LABELS: Dictionary = {
	"Narrativo": "Fácil",
	"Descriptivo": "Normal",
	"Argumentativo": "Difícil",
	"Expositivo": "Muy difícil",
}

## Nombre del escenario de cada tipología, como en los carteles del lobby.
const NOMBRE_ESCENARIO: Dictionary = {
	"Narrativo": "Textos Narrativos",
	"Descriptivo": "Textos Descriptivos",
	"Argumentativo": "Textos Argumentativos",
	"Expositivo": "Textos Expositivos",
}

## Lecturas terminadas que tiene el alumno para aprobar cada tipología. Si las
## gasta sin aprobar, el juego termina: ya no puede avanzar. Espejo de
## MAX_INTENTOS_POR_TIPOLOGIA en la API (api/game_rules.py).
const MAX_INTENTOS: int = 5

const MENSAJE_FINAL_ESTACION := "🏆 ¡Completaste todas las tipologías!\n\nPuedes seguir practicando en la zona de práctica."
const MENSAJE_FINAL_RESULTADO := "🏆 ¡Completaste todas las tipologías! Puedes seguir practicando en la zona de práctica."

# ─── Exports (ajustables desde el Inspector) ────────────────────────────────

## Puntaje mínimo en Narrativo para desbloquear Descriptivo.
@export var threshold_descriptivo: int = 150

## Puntaje mínimo en Descriptivo para desbloquear Argumentativo.
@export var threshold_argumentativo: int = 150

## Puntaje mínimo en Argumentativo para desbloquear Expositivo.
@export var threshold_expositivo: int = 150

## Puntos bonus otorgados por cada herramienta utilizada durante la lectura.
@export var tool_bonus_points: int = 20

# ─── Estado de progresión ────────────────────────────────────────────────────

## Mejor puntaje obtenido por tipología. Ejemplo: {"Narrativo": 280}
var best_scores: Dictionary = {}

## Tipologías desbloqueadas. Narrativo siempre está desbloqueado.
var unlocked: Array[String] = ["Narrativo"]

## Intentos gastados por tipología (lecturas de progresión terminadas desde
## que existen los intentos). Ejemplo: {"Narrativo": 2}
var intentos: Dictionary = {}

# ─── Ciclo de vida ──────────────────────────────────────────────────────────

func _ready() -> void:
	# En modo editor, reiniciar todo al iniciar el juego para pruebas.
	if OS.has_feature("editor"):
		print("[ProgressionManager] Ejecución desde editor: Reiniciando progresión.")
		reset_all()
	
	# Escuchar evento de sesión invalidada
	if AuthManager.has_signal("session_invalidated"):
		AuthManager.session_invalidated.connect(_on_session_invalidated)


func _on_session_invalidated() -> void:
	reset_all()
	print("[ProgressionManager] Progresión borrada por sesión invalidada")


# ─── API Pública ─────────────────────────────────────────────────────────────

## Retorna el diccionario de umbrales de desbloqueo.
func get_unlock_thresholds() -> Dictionary:
	return {
		"Narrativo": 0,
		"Descriptivo": threshold_descriptivo,
		"Argumentativo": threshold_argumentativo,
		"Expositivo": threshold_expositivo,
	}


## ¿Está la tipología desbloqueada para el jugador?
func is_unlocked(typology: String) -> bool:
	return typology in unlocked


## Registra el resultado de una sesión completada.
## Solo guarda el puntaje si es mayor que el anterior (nunca baja).
## Verifica si se desbloquea la tipología inmediatamente siguiente.
## Devuelve {"aprobada_ahora": bool, "desbloqueada": String}: si esta lectura
## aprobó la tipología y qué tipología abrió ("" si ninguna).
func register_session_result(typology: String, session_score: int) -> Dictionary:
	var era_aprobada := is_approved(typology)
	var current_best: int = best_scores.get(typology, 0)
	best_scores[typology] = maxi(current_best, session_score)
	# Cada lectura terminada gasta un intento, apruebe o no. Se suma aquí para
	# no depender de que la sesión llegue a la API.
	if typology in DIFFICULTY_ORDER:
		intentos[typology] = intentos_usados(typology) + 1

	print("[ProgressionManager] Sesión registrada: %s → %d pts (mejor: %d)" % [
		typology, session_score, best_scores[typology]
	])

	var desbloqueada := _check_unlock(typology)
	progression_changed.emit()
	return {
		"aprobada_ahora": not era_aprobada and is_approved(typology),
		"desbloqueada": desbloqueada,
	}


# ─── Tipologías aprobadas ────────────────────────────────────────────────────
# Aprobar una tipología la cierra en el lobby: el alumno sigue con la
# siguiente. Se decide por el puntaje, no por el desbloqueo de la siguiente,
# que puede haberlo cambiado un administrador.

## Puntaje con el que se aprueba una tipología: el que abre la siguiente.
## La última no abre nada y usa el umbral con el que se llegó a ella.
func get_pass_threshold(typology: String) -> int:
	var next: String = get_next_typology(typology)
	if next.is_empty():
		return threshold_expositivo
	return get_unlock_thresholds().get(next, threshold_expositivo)


## ¿Superó el alumno esta tipología?
func is_approved(typology: String) -> bool:
	if typology not in DIFFICULTY_ORDER:
		return false
	return best_scores.get(typology, 0) >= get_pass_threshold(typology)


## Primera tipología del recorrido que falta aprobar, o "" si están todas.
func get_next_unapproved() -> String:
	for typology in DIFFICULTY_ORDER:
		if not is_approved(typology):
			return typology
	return ""


func all_approved() -> bool:
	return get_next_unapproved().is_empty()


## Qué hacer cuando el alumno pulsa E en la estación de una tipología.
## pendiente es la tipología de la lectura a medias conocida, o "".
## "bloqueada", "aprobada", "reanudar" (aprobada, pero con su propia lectura
## a medias: se deja terminarla), "agotada" (sin intentos) o "normal".
func decidir_entrada(typology: String, pendiente: String) -> String:
	if not is_unlocked(typology):
		return "bloqueada"
	if is_approved(typology):
		return "reanudar" if pendiente == typology else "aprobada"
	if esta_agotada(typology) and pendiente != typology:
		return "agotada"
	return "normal"


# ─── Intentos ────────────────────────────────────────────────────────────────

func intentos_usados(typology: String) -> int:
	return int(intentos.get(typology, 0))


func intentos_restantes(typology: String) -> int:
	return maxi(0, MAX_INTENTOS - intentos_usados(typology))


## Sin aprobar y sin intentos: no puede empezar otra lectura en ella.
func esta_agotada(typology: String) -> bool:
	return typology in DIFFICULTY_ORDER and not is_approved(typology) \
			and intentos_usados(typology) >= MAX_INTENTOS


## Con una tipología agotada el recorrido se acaba: como se desbloquean en
## orden, las siguientes ya no se abren.
func juego_terminado() -> bool:
	return not tipologia_agotada().is_empty()


## Tipología que se quedó sin intentos, o "".
func tipologia_agotada() -> String:
	for typology in DIFFICULTY_ORDER:
		if esta_agotada(typology):
			return typology
	return ""


## «Intento N de 5» para la lectura que se va a jugar (o la que está a medias).
func texto_intento(typology: String) -> String:
	return "Intento %d de %d" % [mini(intentos_usados(typology) + 1, MAX_INTENTOS), MAX_INTENTOS]


func mensaje_estacion_agotada(typology: String) -> String:
	return "Se acabaron tus %d intentos en %s.\n\nEl juego terminó: ya no puedes avanzar a otras tipologías. Puedes seguir practicando en la zona de práctica y ver tus logros y el ranking." % [
		MAX_INTENTOS, NOMBRE_ESCENARIO.get(typology, typology),
	]


## Aviso de una estación bloqueada cuando ya no hay forma de desbloquearla.
func mensaje_juego_terminado() -> String:
	var agotada := tipologia_agotada()
	return "🏁 El juego terminó: se acabaron tus intentos en %s, así que esta tipología ya no se puede desbloquear.\n\nPuedes seguir practicando en la zona de práctica." % NOMBRE_ESCENARIO.get(agotada, agotada)


## Línea de la pantalla de resultados de una lectura que no aprobó.
func mensaje_resultado_intentos(typology: String) -> String:
	var escenario: String = NOMBRE_ESCENARIO.get(typology, typology)
	if esta_agotada(typology):
		return "Se acabaron tus %d intentos en %s. El juego terminó: ya no puedes avanzar, pero puedes seguir en la zona de práctica." % [MAX_INTENTOS, escenario]
	var quedan := intentos_restantes(typology)
	if quedan == 1:
		return "Te queda 1 intento en %s." % escenario
	return "Te quedan %d intentos en %s." % [quedan, escenario]


## Aviso de la estación de una tipología aprobada.
func mensaje_estacion_aprobada(typology: String) -> String:
	if all_approved():
		return MENSAJE_FINAL_ESTACION
	return "✓ Ya aprobaste %s con %d pts.\n\nContinúa con %s." % [
		NOMBRE_ESCENARIO.get(typology, typology),
		get_best_score(typology),
		NOMBRE_ESCENARIO[get_next_unapproved()],
	]


## Mensaje de la pantalla de resultados cuando la tipología queda aprobada.
func mensaje_resultado_aprobada(typology: String) -> String:
	if all_approved():
		return MENSAJE_FINAL_RESULTADO
	return "✓ ¡Aprobaste %s! Continúa con %s en el lobby." % [
		NOMBRE_ESCENARIO.get(typology, typology),
		NOMBRE_ESCENARIO[get_next_unapproved()],
	]


## Calcula el bonus total por herramientas usadas en la sesión.
## Retorna la cantidad de puntos bonus.
func calculate_tool_bonus(tools_used: Dictionary) -> int:
	var bonus: int = 0
	if tools_used.get("highlight", false):
		bonus += tool_bonus_points
	if tools_used.get("underline", false):
		bonus += tool_bonus_points
	if tools_used.get("notes", false):
		bonus += tool_bonus_points
	return bonus


## Retorna el puntaje total global (suma de mejores puntajes de todas las tipologías).
func get_total_score() -> int:
	var total: int = 0
	for score in best_scores.values():
		total += score
	return total


## Retorna el mejor puntaje registrado para una tipología.
func get_best_score(typology: String) -> int:
	return best_scores.get(typology, 0)


## Retorna la tipología que sigue a la indicada en el orden de dificultad.
## Retorna "" si no hay siguiente (es la última).
func get_next_typology(current: String) -> String:
	var idx: int = DIFFICULTY_ORDER.find(current)
	if idx < 0 or idx >= DIFFICULTY_ORDER.size() - 1:
		return ""
	return DIFFICULTY_ORDER[idx + 1]


## Retorna la tipología que precede a la indicada (requisito previo).
## Retorna "" si no hay anterior (es la primera).
func get_previous_typology(current: String) -> String:
	var idx: int = DIFFICULTY_ORDER.find(current)
	if idx <= 0:
		return ""
	return DIFFICULTY_ORDER[idx - 1]


## Retorna información de progreso hacia el desbloqueo de la siguiente tipología.
## Útil para mostrar en la pantalla de resultados.
func get_unlock_progress(typology: String) -> Dictionary:
	var next: String = get_next_typology(typology)
	if next.is_empty():
		return {
			"next": "",
			"current": best_scores.get(typology, 0),
			"threshold": 0,
			"unlocked": true,
			"is_last": true,
		}

	var thresholds: Dictionary = get_unlock_thresholds()
	var threshold: int = thresholds.get(next, 0)
	var current: int = best_scores.get(typology, 0)

	return {
		"next": next,
		"current": current,
		"threshold": threshold,
		"unlocked": next in unlocked,
		"is_last": false,
	}


## Retorna el requisito de desbloqueo para una tipología bloqueada.
## Útil para mostrar al jugador qué necesita hacer para desbloquear.
func get_lock_info(typology: String) -> Dictionary:
	if is_unlocked(typology):
		return {"locked": false}

	var prev: String = get_previous_typology(typology)
	if prev.is_empty():
		return {"locked": false}  # Narrativo nunca está bloqueado

	var thresholds: Dictionary = get_unlock_thresholds()
	var threshold: int = thresholds.get(typology, 0)
	var current_score: int = best_scores.get(prev, 0)

	return {
		"locked": true,
		"required_typology": prev,
		"required_score": threshold,
		"current_score": current_score,
		"difficulty_label": DIFFICULTY_LABELS.get(typology, ""),
	}


## Reinicia toda la progresión (para pruebas o reset desde menú).
func reset_all() -> void:
	best_scores.clear()
	unlocked = ["Narrativo"]
	intentos.clear()
	progression_changed.emit()
	print("[ProgressionManager] Progresión reiniciada.")


## Carga la progresión desde datos de la API (GET /progress/me).
## Llamar después de un login exitoso para restaurar el estado.
func load_from_api(typology_progress: Array) -> void:
	best_scores.clear()
	unlocked = ["Narrativo"]  # Siempre desbloqueado
	intentos.clear()

	for tp in typology_progress:
		var typology: String = str(tp.get("typology", ""))
		var best: int = tp.get("best_score", 0)
		var is_unlocked: bool = tp.get("is_unlocked", false)
		intentos[typology] = int(tp.get("attempts_used", 0))

		if best > 0:
			best_scores[typology] = best
		if is_unlocked and typology not in unlocked:
			unlocked.append(typology)

	progression_changed.emit()
	print("[ProgressionManager] Progresión cargada desde API: %s" % str(best_scores))


# ─── Lógica interna de desbloqueo ───────────────────────────────────────────

## Verifica si al completar una tipología se desbloquea la siguiente.
## REGLA: Solo verifica el inmediato siguiente, NO recursivamente.
## Esto garantiza desbloqueo uno a la vez.
## Devuelve la tipología desbloqueada ahora, o "" si no se abrió ninguna.
func _check_unlock(completed_typology: String) -> String:
	var idx: int = DIFFICULTY_ORDER.find(completed_typology)
	if idx < 0 or idx >= DIFFICULTY_ORDER.size() - 1:
		return ""

	# Solo verificar el inmediato siguiente
	var next_typology: String = DIFFICULTY_ORDER[idx + 1]

	# Si ya está desbloqueado, no hacer nada
	if next_typology in unlocked:
		return ""

	var thresholds: Dictionary = get_unlock_thresholds()
	var threshold: int = thresholds.get(next_typology, 999)

	if best_scores.get(completed_typology, 0) >= threshold:
		unlocked.append(next_typology)
		level_unlocked.emit(next_typology)
		print("[ProgressionManager] ¡Desbloqueado: %s! (umbral: %d)" % [next_typology, threshold])
		return next_typology
	# NO se verifica recursivamente — desbloqueo uno a la vez
	return ""
