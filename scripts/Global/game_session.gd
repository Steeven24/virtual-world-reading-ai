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

# ─── Constantes ──────────────────────────────────────────────────────────────

## Niveles de comprensión en orden de progresión.
const LEVELS: Array[String] = ["Literal", "Inferencial", "Critico"]

## Cantidad de preguntas aleatorias por nivel.
const QUESTIONS_PER_LEVEL: int = 2

## Mostrar la respuesta correcta en los desafíos (solo para desarrollo).
const DEBUG_SHOW_ANSWER: bool = true

# ─── Rutas de escenas ────────────────────────────────────────────────────────

## Escena del quiz genérico.
const QUIZ_SCENE: String = "res://scenes/Challenges/Templates/quiz_challenge.tscn"

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
## Retorna un Dictionary con {correct: bool, justification: String, correct_answer: String}
func submit_answer(letter: String) -> Dictionary:
	var question := get_current_question()
	if question.is_empty():
		return {"correct": false, "justification": "", "correct_answer": ""}

	var correct_letter: String = str(question.get("correct_answer", ""))
	var is_correct: bool = letter.to_upper() == correct_letter.to_upper()
	var justification: String = str(question.get("justification", ""))

	# Registrar resultado
	results.append({
		"level": get_current_level(),
		"question_id": question.get("id", 0),
		"correct": is_correct,
		"letter_selected": letter,
		"correct_answer": correct_letter,
	})

	return {
		"correct": is_correct,
		"justification": justification,
		"correct_answer": correct_letter,
	}


## Avanza a la siguiente pregunta o nivel.
## Retorna la ruta de la escena a la que se debe transicionar.
## - Si hay más preguntas en el nivel → QUIZ_SCENE (misma escena, nueva pregunta)
## - Si se completó el nivel → escena del siguiente escenario intermedio
## - Si se completaron todos los niveles → lobby_scene
func advance_to_next() -> String:
	current_question_index += 1

	# ¿Hay más preguntas en este nivel?
	if current_question_index < level_questions.size():
		return QUIZ_SCENE

	# Avanzar al siguiente nivel
	current_level_index += 1
	current_question_index = 0

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

	# Todos los niveles completados
	is_active = false
	return lobby_scene


## Reinicia al nivel 1 (Literal) manteniendo la misma lectura.
## Útil cuando el jugador falla y quiere reintentar.
func restart_from_level1() -> void:
	current_level_index = 0
	current_question_index = 0
	results.clear()
	_prepare_level_questions()


## Retorna la ruta de la escena del Level 1 (lectura + libro).
## Se usa para el reinicio cuando el jugador falla.
func get_level1_scene() -> String:
	return level_scenes.get("Literal", "")


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
