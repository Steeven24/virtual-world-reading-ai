## Controlador de sesión de juego.
## Mantiene el estado entre cambios de escena: lectura activa, preguntas,
## nivel de comprensión actual, resultados del jugador.
##
## Registrar como Autoload: Project Settings → Autoload → "GameSession"
extends Node

# ─── Señales ─────────────────────────────────────────────────────────────────

## Emitida cuando la lectura completa se carga (con preguntas).
signal session_ready
## Emitida si falla la carga de la sesión.
signal session_failed(error: String)
## Emitida cuando la puntuación cambia (para actualizar HUD).
signal score_changed(total_score: int)
## Emitida cuando se desbloquea un logro nuevo.
signal achievement_unlocked(achievement_id: String, achievement_name: String)

# ─── Constantes ──────────────────────────────────────────────────────────────

## Niveles de comprensión en orden de progresión.
const LEVELS: Array[String] = ["Literal", "Inferencial", "Critico"]

## Cantidad de preguntas aleatorias por nivel.
const QUESTIONS_PER_LEVEL: int = 2

## Mostrar la respuesta correcta en los desafíos (solo para desarrollo).
const DEBUG_SHOW_ANSWER: bool = true

## Puntos por respuesta correcta según nivel.
const POINTS_BY_LEVEL: Dictionary = {
	"Literal": 10,
	"Inferencial": 20,
	"Critico": 30,
}

## Penalización por respuesta incorrecta según nivel (escalada).
const PENALTY_BY_LEVEL: Dictionary = {
	"Literal": 3,
	"Inferencial": 5,
	"Critico": 8,
}

## Bonus por completar un nivel sin errores (2/2 correctas).
const LEVEL_PERFECT_BONUS: int = 15

## Bonus por completar los 3 niveles de una lectura.
const SESSION_COMPLETE_BONUS: int = 50

## Bonus adicional por sesión perfecta (0 errores en toda la sesión).
const SESSION_PERFECT_BONUS: int = 25

# ─── Rutas de escenas ────────────────────────────────────────────────────────

## Escena del quiz genérico.
const QUIZ_SCENE: String = "res://scenes/Challenges/Templates/quiz_challenge.tscn"

## Escena de resultados al completar la sesión.
const RESULTS_SCENE: String = "res://scenes/UI/session_results.tscn"

## Escenas de niveles (escenarios intermedios).
## Estas se configuran al iniciar sesión según la lectura.
var level_scenes: Dictionary = {
	"Literal": "",       # Se configura dinámicamente (level 1 ya pasó, no se usa)
	"Inferencial": "",   # Path al level 2
	"Critico": "",       # Path al level 3
}

## Escena de retorno al completar todos los niveles.
var lobby_scene: String = ""

# ─── Estado de la sesión ─────────────────────────────────────────────────────

## Lectura completa con preguntas (respuesta de /readings/{id}/full).
var current_reading: Dictionary = {}

## Tipología activa.
var current_typology: String = ""

## Nivel de comprensión actual (índice en LEVELS).
var current_level_index: int = 0

## Índice de la pregunta actual dentro del nivel (0 o 1).
var current_question_index: int = 0

## Preguntas seleccionadas para el nivel actual (2 aleatorias).
var level_questions: Array = []

## Historial de resultados: [{level, question_id, correct, letter_selected}]
var results: Array = []

## True si hay una sesión activa.
var is_active: bool = false

## Contador de errores en el nivel actual (para bonus perfecto).
var _level_errors: int = 0

## Registro de herramientas usadas durante la lectura.
## Se llena desde bookAndTools.gd al confirmar el inicio de desafíos.
var tools_used: Dictionary = {"highlight": false, "underline": false, "notes": false}

# ─── Sistema de puntuación ───────────────────────────────────────────────

## Datos de puntuación. Se reinicia al iniciar el juego.
## En el futuro, persistirá por usuario.
var score_data: Dictionary = {
	"total_score": 0,
	"sessions_completed": 0,
	"correct_by_level": {"Literal": 0, "Inferencial": 0, "Critico": 0},
	"incorrect_by_level": {"Literal": 0, "Inferencial": 0, "Critico": 0},
	"typologies_completed": [],
	"perfect_sessions": 0,
	"achievements": [],
	"best_scores_by_typology": {},
}

## Puntaje acumulado solo en la sesión actual (para comparar con best).
var _current_session_score: int = 0

# ─── API Pública ─────────────────────────────────────────────────────────────

## Inicia una sesión de juego para la tipología dada.
## Llama a la API para obtener una lectura completa con preguntas.
## Configurar level_scenes y lobby_scene ANTES de llamar a esto,
## o usar configure_scenes() después.
func start_session(typology: String) -> void:
	current_typology = typology
	current_level_index = 0
	current_question_index = 0
	results.clear()
	_current_session_score = 0
	is_active = true
	_connect_api()
	ReadingAPI.get_random_reading_full(typology)


## Configura las rutas de escenas para los niveles intermedios y el lobby.
func configure_scenes(inferencial_scene: String, critico_scene: String, return_scene: String) -> void:
	level_scenes["Inferencial"] = inferencial_scene
	level_scenes["Critico"] = critico_scene
	lobby_scene = return_scene


## Inicia la sesión usando datos ya cargados (desde caché del libro).
func start_session_with_data(data: Dictionary) -> void:
	current_reading = data
	current_typology = str(data.get("typology", ""))
	current_level_index = 0
	current_question_index = 0
	results.clear()
	_current_session_score = 0
	is_active = true
	_prepare_level_questions()
	session_ready.emit()


## Retorna el nivel de comprensión actual como String.
func get_current_level() -> String:
	if current_level_index < LEVELS.size():
		return LEVELS[current_level_index]
	return ""


## Retorna la pregunta actual que debe mostrarse en el quiz.
func get_current_question() -> Dictionary:
	if current_question_index < level_questions.size():
		return level_questions[current_question_index]
	return {}


## Retorna el texto de progreso: "Pregunta 1/2"
func get_progress_text() -> String:
	return "Pregunta %d/%d" % [current_question_index + 1, QUESTIONS_PER_LEVEL]


## Valida la respuesta del jugador.
## Retorna un Dictionary con {correct, justification, correct_answer, points_earned, penalty}
func submit_answer(letter: String) -> Dictionary:
	var question := get_current_question()
	if question.is_empty():
		return {"correct": false, "justification": "", "correct_answer": ""}

	var correct_letter: String = str(question.get("correct_answer", ""))
	var is_correct: bool = letter.to_upper() == correct_letter.to_upper()
	var justification: String = str(question.get("justification", ""))
	var current_level := get_current_level()

	# Registrar resultado
	results.append({
		"level": current_level,
		"question_id": question.get("id", 0),
		"correct": is_correct,
		"letter_selected": letter,
		"correct_answer": correct_letter,
	})

	# Otorgar puntos o penalizar
	var points_earned: int = 0
	var penalty: int = 0
	if is_correct:
		points_earned = POINTS_BY_LEVEL.get(current_level, 10)
		score_data["total_score"] += points_earned
		_current_session_score += points_earned
		score_data["correct_by_level"][current_level] += 1
	else:
		penalty = PENALTY_BY_LEVEL.get(current_level, 5)
		score_data["total_score"] = maxi(0, score_data["total_score"] - penalty)
		_current_session_score = maxi(0, _current_session_score - penalty)
		_level_errors += 1
		score_data["incorrect_by_level"][current_level] += 1

	score_changed.emit(score_data["total_score"])

	return {
		"correct": is_correct,
		"justification": justification,
		"correct_answer": correct_letter,
		"points_earned": points_earned,
		"penalty": penalty,
	}


## Avanza a la siguiente pregunta o nivel.
## Retorna la ruta de la escena a la que se debe transicionar.
## - Si hay más preguntas en el nivel → QUIZ_SCENE (misma escena, nueva pregunta)
## - Si se completó el nivel → escena del siguiente escenario intermedio
## - Si se completaron todos los niveles → RESULTS_SCENE
func advance_to_next() -> String:
	current_question_index += 1

	# ¿Hay más preguntas en este nivel?
	if current_question_index < level_questions.size():
		return QUIZ_SCENE

	# Avanzar al siguiente nivel
	# Verificar bonus de nivel perfecto antes de avanzar
	if _level_errors == 0:
		var bonus := LEVEL_PERFECT_BONUS
		score_data["total_score"] += bonus
		_current_session_score += bonus
		score_changed.emit(score_data["total_score"])
	current_level_index += 1
	current_question_index = 0
	_level_errors = 0

	# ¿Hay más niveles?
	if current_level_index < LEVELS.size():
		var next_level := get_current_level()
		_prepare_level_questions()
		# Retornar la escena del escenario intermedio
		var scene_path: String = level_scenes.get(next_level, "")
		if scene_path.is_empty():
			# Si no hay escenario intermedio, ir directo al quiz
			return QUIZ_SCENE
		return scene_path

	# Todos los niveles completados → pantalla de resultados
	_on_session_complete()
	return RESULTS_SCENE


## Inicia una nueva sesión con otra lectura de la misma tipología.
## Usado desde la pantalla de resultados para mejorar el puntaje.
func retry_with_new_reading() -> void:
	var typology := current_typology
	current_level_index = 0
	current_question_index = 0
	results.clear()
	_current_session_score = 0
	_level_errors = 0
	is_active = true
	_connect_api()
	ReadingAPI.get_random_reading_full(typology)


## Retorna el puntaje obtenido solo en la sesión actual.
func get_session_score() -> int:
	return _current_session_score


## Retorna el mejor puntaje registrado para una tipología.
func get_best_score(typology: String) -> int:
	return score_data["best_scores_by_typology"].get(typology, 0)


## Retorna true si la sesión actual superó el mejor puntaje previo.
func is_new_record() -> bool:
	var best: int = get_best_score(current_typology)
	return _current_session_score > best


## Retorna un resumen de los resultados al final de la sesión.
func get_results_summary() -> Dictionary:
	var total := results.size()
	var correct := results.filter(func(r): return r["correct"]).size()
	return {
		"total": total,
		"correct": correct,
		"incorrect": total - correct,
		"score_percent": (float(correct) / float(total) * 100.0) if total > 0 else 0.0,
		"details": results,
	}


## Retorna la puntuación total actual.
func get_total_score() -> int:
	return score_data.get("total_score", 0)


## Retorna la lista de logros desbloqueados.
func get_achievements() -> Array:
	return score_data.get("achievements", [])


# ─── Lógica de sesión completada ───────────────────────────────────────

func _on_session_complete() -> void:
	is_active = false
	score_data["sessions_completed"] += 1

	# Registrar tipología completada
	if not current_typology.is_empty() and current_typology not in score_data["typologies_completed"]:
		score_data["typologies_completed"].append(current_typology)

	# Bonus por sesión completa
	score_data["total_score"] += SESSION_COMPLETE_BONUS
	_current_session_score += SESSION_COMPLETE_BONUS

	# Verificar sesión perfecta (0 errores en toda la sesión)
	var total_errors := results.filter(func(r): return not r["correct"]).size()
	if total_errors == 0:
		score_data["perfect_sessions"] += 1
		score_data["total_score"] += SESSION_PERFECT_BONUS
		_current_session_score += SESSION_PERFECT_BONUS

	# Actualizar mejor puntaje por tipología
	var best: int = score_data["best_scores_by_typology"].get(current_typology, 0)
	if _current_session_score > best:
		score_data["best_scores_by_typology"][current_typology] = _current_session_score

	score_changed.emit(score_data["total_score"])
	_check_achievements()


func _check_achievements() -> void:
	var unlocked: Array = score_data["achievements"]

	# Primera lectura
	if score_data["sessions_completed"] >= 1 and "first_reading" not in unlocked:
		_unlock("first_reading", "📖 Primera lectura")

	# Explorador: 1 sesión de cada tipología (5 tipologías)
	if score_data["typologies_completed"].size() >= 5 and "explorer" not in unlocked:
		_unlock("explorer", "🏅 Explorador")

	# Perfeccionista: 1 sesión sin errores
	if score_data["perfect_sessions"] >= 1 and "perfectionist" not in unlocked:
		_unlock("perfectionist", "🎯 Perfeccionista")

	# Lector ávido: 5 sesiones
	if score_data["sessions_completed"] >= 5 and "avid_reader" not in unlocked:
		_unlock("avid_reader", "📚 Lector ávido")

	# Estrellas por nivel
	if score_data["correct_by_level"]["Literal"] >= 10 and "star_literal" not in unlocked:
		_unlock("star_literal", "⭐ Estrella literal")
	if score_data["correct_by_level"]["Inferencial"] >= 10 and "star_inferencial" not in unlocked:
		_unlock("star_inferencial", "⭐⭐ Estrella inferencial")
	if score_data["correct_by_level"]["Critico"] >= 10 and "star_critico" not in unlocked:
		_unlock("star_critico", "⭐⭐⭐ Estrella crítica")

	# En mejora: mejorar un puntaje previo
	if is_new_record() and score_data["sessions_completed"] >= 2 and "improvement" not in unlocked:
		_unlock("improvement", "📈 En mejora")

	# Centurión: 100 pts totales
	if score_data["total_score"] >= 100 and "centurion" not in unlocked:
		_unlock("centurion", "💯 Centurión")

	# Medio milenio: 500 pts totales
	if score_data["total_score"] >= 500 and "half_millennium" not in unlocked:
		_unlock("half_millennium", "🏆 Medio milenio")


func _unlock(id: String, display_name: String) -> void:
	score_data["achievements"].append(id)
	achievement_unlocked.emit(id, display_name)
	print("[GameSession] Logro desbloqueado: %s" % display_name)


# ─── Conexión con la API ─────────────────────────────────────────────────────

func _connect_api() -> void:
	if not ReadingAPI.full_reading_loaded.is_connected(_on_full_reading_loaded):
		ReadingAPI.full_reading_loaded.connect(_on_full_reading_loaded)
	if not ReadingAPI.request_failed.is_connected(_on_request_failed):
		ReadingAPI.request_failed.connect(_on_request_failed)


func _disconnect_api() -> void:
	if ReadingAPI.full_reading_loaded.is_connected(_on_full_reading_loaded):
		ReadingAPI.full_reading_loaded.disconnect(_on_full_reading_loaded)
	if ReadingAPI.request_failed.is_connected(_on_request_failed):
		ReadingAPI.request_failed.disconnect(_on_request_failed)


func _on_full_reading_loaded(data: Dictionary) -> void:
	_disconnect_api()
	current_reading = data

	# Validar que la lectura tiene preguntas
	var questions: Array = data.get("questions", [])
	if questions.is_empty():
		session_failed.emit("La lectura no tiene preguntas asociadas.")
		return

	_prepare_level_questions()
	session_ready.emit()


func _on_request_failed(endpoint: String, error: String) -> void:
	if not is_active:
		return
	_disconnect_api()
	session_failed.emit("Error al cargar lectura: %s" % error)


# ─── Preparación de preguntas ────────────────────────────────────────────────

## Selecciona QUESTIONS_PER_LEVEL preguntas aleatorias del nivel actual.
func _prepare_level_questions() -> void:
	var level := get_current_level()
	var all_questions: Array = current_reading.get("questions", [])

	# Filtrar por nivel de comprensión
	var filtered: Array = all_questions.filter(
		func(q): return str(q.get("comprehension_level", "")) == level
	)

	# Barajar y tomar las primeras QUESTIONS_PER_LEVEL
	filtered.shuffle()
	level_questions = filtered.slice(0, mini(QUESTIONS_PER_LEVEL, filtered.size()))
	current_question_index = 0

	if level_questions.is_empty():
		push_warning("[GameSession] No hay preguntas para el nivel '%s'" % level)
