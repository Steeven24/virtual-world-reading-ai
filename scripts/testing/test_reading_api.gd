## Script de prueba de integración con la API de lecturas.
## Ejecuta una serie de verificaciones automáticas al entrar a la escena
## e imprime resultados en la consola (Output) de Godot.
##
## Uso: Asignar este script a un nodo Node en una escena de prueba
##       y ejecutar la escena (F6 o F5 con escena configurada).
extends Node

# ─── Estado de las pruebas ──────────────────────────────────────────────────────

var _tests_passed: int = 0
var _tests_failed: int = 0
var _tests_total: int = 0

# ─── Ciclo de vida ──────────────────────────────────────────────────────────────

func _ready() -> void:
	print("\n" + "=".repeat(60))
	print("  PRUEBAS DE INTEGRACIÓN — ReadingAPI")
	print("  API: %s" % ApiConfig.BASE_URL)
	print("=".repeat(60) + "\n")

	# Ejecutar pruebas secuencialmente
	await _test_health_check()
	await _test_list_typologies()
	await _test_random_reading()
	await _test_random_reading_with_typology()
	await _test_list_readings_paginated()
	await _test_get_reading_by_id()
	await _test_cache_persistence()
	await _test_seen_ids()

	_print_summary()


# ─── Test 1: Health Check ───────────────────────────────────────────────────────

func _test_health_check() -> void:
	_tests_total += 1
	print("► Test 1: Health Check...")

	var state = [false, {}]
	var cb := func(data):
		state[1] = data if data is Dictionary else {}
		state[0] = true
	
	ReadingAPI.check_health(cb)

	# Esperar respuesta (máx 5 segundos)
	var elapsed := 0.0
	while not state[0] and elapsed < 5.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	if state[0] and state[1].get("status", "") == "ok":
		_pass("Health OK — DB: %s" % state[1].get("database", "?"))
	elif state[0]:
		_fail("Health respondió pero con estado: %s" % str(state[1]))
	else:
		_fail("Health no respondió en 5s")


# ─── Test 2: Listar tipologías ──────────────────────────────────────────────────

func _test_list_typologies() -> void:
	_tests_total += 1
	print("► Test 2: Listar tipologías...")

	var result: Array = []
	var received := false

	var cb := func(data: Array):
		result = data
		received = true
	ReadingAPI.typologies_loaded.connect(cb)
	ReadingAPI.list_typologies()

	var elapsed := 0.0
	while not received and elapsed < 5.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	ReadingAPI.typologies_loaded.disconnect(cb)

	if received and result.size() > 0:
		var names: PackedStringArray = []
		for t in result:
			if t is Dictionary:
				names.append("%s(%d)" % [t.get("name", "?"), t.get("count", 0)])
		_pass("Tipologías: %s" % ", ".join(names))
	elif received:
		_fail("Tipologías vacías")
	else:
		_fail("Tipologías no respondió en 5s")


# ─── Test 3: Lectura aleatoria (sin filtro) ─────────────────────────────────────

func _test_random_reading() -> void:
	_tests_total += 1
	print("► Test 3: Lectura aleatoria (sin filtro)...")

	var result: Dictionary = {}
	var received := false

	var cb := func(data: Dictionary):
		result = data
		received = true
	ReadingAPI.random_reading_loaded.connect(cb)
	ReadingAPI.get_random_reading()

	var elapsed := 0.0
	while not received and elapsed < 5.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	ReadingAPI.random_reading_loaded.disconnect(cb)

	if received and result.has("id"):
		_pass("[%s] \"%s\" — %d caracteres" % [
			result.get("typology", "?"),
			result.get("title", "?"),
			str(result.get("content", "")).length()
		])
	elif received:
		_fail("Respuesta inesperada: %s" % str(result).left(100))
	else:
		_fail("No respondió en 5s")


# ─── Test 4: Lectura aleatoria con tipología ────────────────────────────────────

func _test_random_reading_with_typology() -> void:
	_tests_total += 1
	print("► Test 4: Lectura aleatoria (Descriptivo)...")

	var result: Dictionary = {}
	var received := false

	var cb := func(data: Dictionary):
		result = data
		received = true
	ReadingAPI.random_reading_loaded.connect(cb)
	ReadingAPI.get_random_reading("Descriptivo")

	var elapsed := 0.0
	while not received and elapsed < 5.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	ReadingAPI.random_reading_loaded.disconnect(cb)

	if received and result.get("typology", "") == "Descriptivo":
		_pass("Tipología correcta: \"%s\"" % result.get("title", "?"))
	elif received:
		_fail("Tipología incorrecta: %s" % result.get("typology", "?"))
	else:
		_fail("No respondió en 5s")


# ─── Test 5: Listado paginado ───────────────────────────────────────────────────

func _test_list_readings_paginated() -> void:
	_tests_total += 1
	print("► Test 5: Listado paginado (pág 1, 5 items)...")

	var result: Dictionary = {}
	var received := false

	var cb := func(data: Dictionary):
		result = data
		received = true
	ReadingAPI.readings_loaded.connect(cb)
	ReadingAPI.list_readings(1, 5)

	var elapsed := 0.0
	while not received and elapsed < 5.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	ReadingAPI.readings_loaded.disconnect(cb)

	if received and result.has("items"):
		var items: Array = result.get("items", [])
		_pass("Total: %d, Página: %d/%d, Items: %d" % [
			result.get("total", 0), result.get("page", 0),
			result.get("pages", 0), items.size()
		])
	elif received:
		_fail("Respuesta sin 'items': %s" % str(result).left(100))
	else:
		_fail("No respondió en 5s")


# ─── Test 6: Obtener lectura por ID ─────────────────────────────────────────────

func _test_get_reading_by_id() -> void:
	_tests_total += 1
	print("► Test 6: Obtener lectura ID=1...")

	var result: Dictionary = {}
	var received := false

	var cb := func(data: Dictionary):
		result = data
		received = true
	ReadingAPI.reading_loaded.connect(cb)
	ReadingAPI.get_reading(1)

	var elapsed := 0.0
	while not received and elapsed < 5.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	ReadingAPI.reading_loaded.disconnect(cb)

	if received and result.get("id", 0) == 1:
		_pass("\"%s\" [%s]" % [result.get("title", "?"), result.get("typology", "?")])
	elif received:
		_fail("ID incorrecto o respuesta inesperada")
	else:
		_fail("No respondió en 5s (¿lectura ID=1 existe?)")


# ─── Test 7: Persistencia de caché ──────────────────────────────────────────────

func _test_cache_persistence() -> void:
	_tests_total += 1
	print("► Test 7: Persistencia de caché...")

	var cache_exists := FileAccess.file_exists(ApiConfig.CACHE_FILE_PATH)
	if cache_exists:
		_pass("Archivo de caché existe: %s" % ApiConfig.CACHE_FILE_PATH)
	else:
		_fail("Archivo de caché no encontrado (puede ser normal en primera ejecución)")


# ─── Test 8: Sistema de lecturas vistas ─────────────────────────────────────────

func _test_seen_ids() -> void:
	_tests_total += 1
	print("► Test 8: Registro de lecturas vistas...")

	var seen_before: Array = ReadingAPI.get_seen_ids()
	ReadingAPI.mark_seen("test_user", 9999)
	var seen_after: Array = ReadingAPI.get_seen_ids()

	if 9999 in seen_after and seen_after.size() == seen_before.size() + 1:
		_pass("ID 9999 registrado. Total vistos: %d" % seen_after.size())
	elif 9999 in seen_before:
		_pass("ID 9999 ya estaba registrado (idempotente). Total: %d" % seen_after.size())
	else:
		_fail("No se registró el ID 9999")


# ─── Utilidades ─────────────────────────────────────────────────────────────────

func _pass(msg: String) -> void:
	_tests_passed += 1
	print("  ✓ PASS: %s\n" % msg)


func _fail(msg: String) -> void:
	_tests_failed += 1
	print("  ✗ FAIL: %s\n" % msg)


func _print_summary() -> void:
	print("=".repeat(60))
	print("  RESUMEN: %d/%d pasaron, %d fallaron" % [
		_tests_passed, _tests_total, _tests_failed
	])
	if _tests_failed == 0:
		print("  ✓ TODAS LAS PRUEBAS PASARON")
	else:
		print("  ⚠ HAY PRUEBAS FALLIDAS — Revisa la salida anterior")
	print("=".repeat(60) + "\n")
