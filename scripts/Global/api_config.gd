## Configuración centralizada para la conexión con las APIs del proyecto.
## Modificar estos valores según el entorno (desarrollo / producción).
class_name ApiConfig

# ─── API de Lecturas (Virtual-World) ─────────────────────────────────────────

## URL base de la API REST de lecturas (sin barra final).
## Virtual-World corre en el puerto 8001 para coexistir con LecturaIA.
## Puede ser sobreescrito via server_config.json o argumentos CLI (--server-url=...)
static var BASE_URL: String = "http://localhost:8001"

## Tiempo máximo de espera por petición HTTP (en segundos).
const TIMEOUT_SECONDS: float = 10.0

## Número máximo de reintentos ante fallos de red.
const MAX_RETRIES: int = 3

## Factor base para backoff exponencial (en segundos).
## Reintento 1 = 1s, reintento 2 = 2s, reintento 3 = 4s.
const BACKOFF_BASE: float = 1.0

# ─── API de Chat IA (LecturaIA — NPC Tutor) ──────────────────────────────────

## URL base de la API de LecturaIA (chat del NPC).
## Puede ser sobreescrito via server_config.json o argumentos CLI (--npc-url=...)
static var NPC_CHAT_BASE_URL: String = "http://localhost:8000"

## Timeout para peticiones de chat IA (más largo porque la inferencia tarda).
const NPC_CHAT_TIMEOUT: float = 30.0

# ─── Inicialización dinámica de configuración ─────────────────────────────────

static func _static_init() -> void:
	load_config()

## Carga la configuración desde archivos JSON o argumentos de línea de comandos.
static func load_config() -> void:
	# 1. Si corre en navegador Web (HTML5), usar el origen actual del navegador por defecto
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin")
		if origin and typeof(origin) == TYPE_STRING and not origin.is_empty():
			BASE_URL = origin
			NPC_CHAT_BASE_URL = origin

	# 2. Intentar cargar desde res://server_config.json
	_load_from_json_path("res://server_config.json")
	# 3. Intentar cargar desde user://server_config.json (permite override por usuario sin recompilar)
	_load_from_json_path("user://server_config.json")
	# 4. Revisar argumentos de línea de comandos (e.g. --server-url=http://192.168.1.50:8001)
	_load_from_cmdline()

static func _load_from_json_path(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var content := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var err := json.parse(content)
	if err != OK:
		push_warning("ApiConfig: Error al parsear %s: %s" % [path, json.get_error_message()])
		return
		
	var data = json.data
	if typeof(data) == TYPE_DICTIONARY:
		if data.has("base_url") and typeof(data["base_url"]) == TYPE_STRING and not data["base_url"].is_empty():
			BASE_URL = data["base_url"].trim_suffix("/")
		if data.has("npc_chat_base_url") and typeof(data["npc_chat_base_url"]) == TYPE_STRING and not data["npc_chat_base_url"].is_empty():
			NPC_CHAT_BASE_URL = data["npc_chat_base_url"].trim_suffix("/")

static func _load_from_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	for arg in args:
		if arg.begins_with("--server-url="):
			var val := arg.trim_prefix("--server-url=").strip_edges().trim_suffix("/")
			if not val.is_empty():
				BASE_URL = val
		elif arg.begins_with("--npc-url="):
			var val := arg.trim_prefix("--npc-url=").strip_edges().trim_suffix("/")
			if not val.is_empty():
				NPC_CHAT_BASE_URL = val

# ─── Caché ───────────────────────────────────────────────────────────────────

## Tiempo de vida del caché local (en segundos). 3600 = 1 hora.
const CACHE_TTL_SECONDS: int = 3600

## Cantidad máxima de lecturas almacenadas en caché (FIFO).
const MAX_CACHED_READINGS: int = 100

## Ruta del archivo de caché de lecturas.
const CACHE_FILE_PATH: String = "user://cache/readings_cache.json"

## Ruta del archivo de lecturas vistas (no-repetición local).
const SEEN_FILE_PATH: String = "user://cache/seen_readings.json"

# ─── Autenticación (opcional) ────────────────────────────────────────────────

## Token Bearer JWT. Se asigna dinámicamente al hacer login.
## AuthManager lo actualiza automáticamente tras un login exitoso.
static var AUTH_TOKEN: String = ""

# ─── Paginación por defecto ──────────────────────────────────────────────────

## Elementos por página al listar lecturas.
const DEFAULT_PER_PAGE: int = 10

## Tamaño máximo aceptado por la API.
const MAX_PER_PAGE: int = 50
