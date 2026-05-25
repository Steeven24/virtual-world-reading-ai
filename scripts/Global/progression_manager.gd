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
const DIFFICULTY_ORDER: Array[String] = [
	"Narrativo", "Descriptivo", "Argumentativo", "Instructivo", "Expositivo"
]

## Nombre legible de cada dificultad (para UI).
const DIFFICULTY_LABELS: Dictionary = {
	"Narrativo": "Muy fácil",
	"Descriptivo": "Fácil",
	"Argumentativo": "Normal",
	"Instructivo": "Difícil",
	"Expositivo": "Muy difícil",
}

# ─── Exports (ajustables desde el Inspector) ────────────────────────────────

## Puntaje mínimo en Narrativo para desbloquear Descriptivo.
@export var threshold_descriptivo: int = 250

## Puntaje mínimo en Descriptivo para desbloquear Argumentativo.
@export var threshold_argumentativo: int = 250

## Puntaje mínimo en Argumentativo para desbloquear Instructivo.
@export var threshold_instructivo: int = 250

## Puntaje mínimo en Instructivo para desbloquear Expositivo.
@export var threshold_expositivo: int = 250

## Puntos bonus otorgados por cada herramienta utilizada durante la lectura.
@export var tool_bonus_points: int = 20

# ─── Estado de progresión ────────────────────────────────────────────────────

## Mejor puntaje obtenido por tipología. Ejemplo: {"Narrativo": 280}
var best_scores: Dictionary = {}

## Tipologías desbloqueadas. Narrativo siempre está desbloqueado.
var unlocked: Array[String] = ["Narrativo"]

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
		"Instructivo": threshold_instructivo,
		"Expositivo": threshold_expositivo,
	}


## ¿Está la tipología desbloqueada para el jugador?
func is_unlocked(typology: String) -> bool:
	return typology in unlocked


## Registra el resultado de una sesión completada.
## Solo guarda el puntaje si es mayor que el anterior (nunca baja).
## Verifica si se desbloquea la tipología inmediatamente siguiente.
func register_session_result(typology: String, session_score: int) -> void:
	var current_best: int = best_scores.get(typology, 0)
	best_scores[typology] = maxi(current_best, session_score)

	print("[ProgressionManager] Sesión registrada: %s → %d pts (mejor: %d)" % [
		typology, session_score, best_scores[typology]
	])

	_check_unlock(typology)
	progression_changed.emit()


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
	progression_changed.emit()
	print("[ProgressionManager] Progresión reiniciada.")


## Carga la progresión desde datos de la API (GET /progress/me).
## Llamar después de un login exitoso para restaurar el estado.
func load_from_api(typology_progress: Array) -> void:
	best_scores.clear()
	unlocked = ["Narrativo"]  # Siempre desbloqueado

	for tp in typology_progress:
		var typology: String = str(tp.get("typology", ""))
		var best: int = tp.get("best_score", 0)
		var is_unlocked: bool = tp.get("is_unlocked", false)

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
func _check_unlock(completed_typology: String) -> void:
	var idx: int = DIFFICULTY_ORDER.find(completed_typology)
	if idx < 0 or idx >= DIFFICULTY_ORDER.size() - 1:
		return

	# Solo verificar el inmediato siguiente
	var next_typology: String = DIFFICULTY_ORDER[idx + 1]

	# Si ya está desbloqueado, no hacer nada
	if next_typology in unlocked:
		return

	var thresholds: Dictionary = get_unlock_thresholds()
	var threshold: int = thresholds.get(next_typology, 999)

	if best_scores.get(completed_typology, 0) >= threshold:
		unlocked.append(next_typology)
		level_unlocked.emit(next_typology)
		print("[ProgressionManager] ¡Desbloqueado: %s! (umbral: %d)" % [next_typology, threshold])
	# NO se verifica recursivamente — desbloqueo uno a la vez
