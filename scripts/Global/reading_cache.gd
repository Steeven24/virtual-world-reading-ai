## Caché local de lecturas en user://cache/.
## Permite reducir llamadas a la API y proporcionar datos offline.
## Gestiona también la lista local de lecturas vistas (no-repetición).
class_name ReadingCache

# ─── Estructura interna ─────────────────────────────────────────────────────

var _cache_data: Dictionary = {
	"version": 1,
	"readings": {},        # id (String) → Dictionary con datos de la lectura
	"full_readings": {},   # id (String) → Dictionary con lectura + preguntas + respuestas
	"pages": {},           # clave compuesta → Dictionary con respuesta paginada
	"timestamps": {},      # misma clave → timestamp ISO 8601
}
var _seen_data: Dictionary = {
	"seen_ids": [],   # Array de int con IDs de lecturas vistas
}
var _loaded: bool = false


# ─── Inicialización ─────────────────────────────────────────────────────────

func _init() -> void:
	_ensure_cache_dir()
	_load_from_disk()


## Crea el directorio de caché si no existe.
func _ensure_cache_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("cache"):
		dir.make_dir("cache")


## Carga los archivos de caché y de lecturas vistas desde disco.
func _load_from_disk() -> void:
	# Cargar caché de lecturas
	if FileAccess.file_exists(ApiConfig.CACHE_FILE_PATH):
		var file := FileAccess.open(ApiConfig.CACHE_FILE_PATH, FileAccess.READ)
		if file:
			var json := JSON.new()
			var err := json.parse(file.get_as_text())
			if err == OK and json.data is Dictionary:
				_cache_data = json.data
			file.close()

	# Cargar lecturas vistas
	if FileAccess.file_exists(ApiConfig.SEEN_FILE_PATH):
		var file := FileAccess.open(ApiConfig.SEEN_FILE_PATH, FileAccess.READ)
		if file:
			var json := JSON.new()
			var err := json.parse(file.get_as_text())
			if err == OK and json.data is Dictionary:
				_seen_data = json.data
			file.close()

	_loaded = true


# ─── Persistencia ───────────────────────────────────────────────────────────

## Guarda el caché de lecturas en disco.
func _save_cache() -> void:
	var file := FileAccess.open(ApiConfig.CACHE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_cache_data, "\t"))
		file.close()


## Guarda la lista de lecturas vistas en disco.
func _save_seen() -> void:
	var file := FileAccess.open(ApiConfig.SEEN_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_seen_data, "\t"))
		file.close()


# ─── Lecturas individuales ──────────────────────────────────────────────────

## Retorna la lectura cacheada o un Dictionary vacío si no existe / está expirada.
## Si allow_expired es true, retorna datos expirados (útil para fallback).
func get_cached_reading(id: int, allow_expired: bool = false) -> Dictionary:
	var key := str(id)
	if not _cache_data["readings"].has(key):
		return {}
	if not allow_expired and _is_expired("reading_%s" % key):
		return {}
	return _cache_data["readings"][key]


## Almacena una lectura individual en caché.
func cache_reading(id: int, data: Dictionary) -> void:
	var key := str(id)
	_cache_data["readings"][key] = data
	_cache_data["timestamps"]["reading_%s" % key] = Time.get_datetime_string_from_system(true)
	_enforce_cache_limit()
	_save_cache()


# ── Lecturas completas (con preguntas y respuestas) ───────────────────────────

## Retorna la lectura completa cacheada o un Dictionary vacío.
func get_cached_full_reading(id: int, allow_expired: bool = false) -> Dictionary:
	var key := str(id)
	if not _cache_data.get("full_readings", {}).has(key):
		return {}
	if not allow_expired and _is_expired("full_reading_%s" % key):
		return {}
	return _cache_data["full_readings"][key]


## Almacena una lectura completa (con preguntas) en caché.
func cache_full_reading(id: int, data: Dictionary) -> void:
	var key := str(id)
	if not _cache_data.has("full_readings"):
		_cache_data["full_readings"] = {}
	_cache_data["full_readings"][key] = data
	_cache_data["timestamps"]["full_reading_%s" % key] = Time.get_datetime_string_from_system(true)
	_save_cache()


# ─── Páginas (respuestas paginadas) ─────────────────────────────────────────

## Genera una clave única para una consulta paginada.
static func make_page_key(typology: String, page: int, per_page: int, q: String = "") -> String:
	return "%s_%d_%d_%s" % [typology if typology else "all", page, per_page, q]


## Retorna la página cacheada o un Dictionary vacío.
func get_cached_page(key: String, allow_expired: bool = false) -> Dictionary:
	if not _cache_data["pages"].has(key):
		return {}
	if not allow_expired and _is_expired("page_%s" % key):
		return {}
	return _cache_data["pages"][key]


## Almacena una respuesta paginada en caché.
func cache_page(key: String, data: Dictionary) -> void:
	_cache_data["pages"][key] = data
	_cache_data["timestamps"]["page_%s" % key] = Time.get_datetime_string_from_system(true)
	_save_cache()


# ─── Lecturas vistas (no-repetición) ────────────────────────────────────────

## Retorna la lista de IDs de lecturas marcadas como vistas localmente.
func get_seen_ids() -> Array:
	return _seen_data.get("seen_ids", [])


## Agrega un ID a la lista de lecturas vistas si no está ya.
func add_seen_id(id: int) -> void:
	var seen: Array = _seen_data.get("seen_ids", [])
	if id not in seen:
		seen.append(id)
		_seen_data["seen_ids"] = seen
		_save_seen()


## Verifica si una lectura ya fue vista.
func is_seen(id: int) -> bool:
	return id in get_seen_ids()


# ─── Utilidades internas ────────────────────────────────────────────────────

## Verifica si una entrada de caché ha expirado según el TTL configurado.
func _is_expired(timestamp_key: String) -> bool:
	if not _cache_data["timestamps"].has(timestamp_key):
		return true
	var cached_at: String = _cache_data["timestamps"][timestamp_key]
	var cached_dict := Time.get_datetime_dict_from_datetime_string(cached_at, true)
	var now_dict := Time.get_datetime_dict_from_system(true)

	var cached_unix := Time.get_unix_time_from_datetime_dict(cached_dict)
	var now_unix := Time.get_unix_time_from_datetime_dict(now_dict)

	return (now_unix - cached_unix) > ApiConfig.CACHE_TTL_SECONDS


## Limita el número de lecturas en caché eliminando las más antiguas (FIFO).
func _enforce_cache_limit() -> void:
	var readings: Dictionary = _cache_data["readings"]
	if readings.size() <= ApiConfig.MAX_CACHED_READINGS:
		return

	# Recopilar timestamps y ordenar
	var entries: Array = []
	for key in readings.keys():
		var ts_key := "reading_%s" % key
		var ts: String = _cache_data["timestamps"].get(ts_key, "")
		entries.append({"key": key, "ts": ts})

	entries.sort_custom(func(a, b): return a["ts"] < b["ts"])

	# Eliminar las más antiguas hasta estar dentro del límite
	var to_remove: int = readings.size() - ApiConfig.MAX_CACHED_READINGS
	for i in range(to_remove):
		var key: String = entries[i]["key"]
		readings.erase(key)
		_cache_data["timestamps"].erase("reading_%s" % key)


## Invalida todo el caché (útil al actualizar la versión de la API).
func invalidate_all() -> void:
	_cache_data = {"version": 1, "readings": {}, "full_readings": {}, "pages": {}, "timestamps": {}}
	_save_cache()
