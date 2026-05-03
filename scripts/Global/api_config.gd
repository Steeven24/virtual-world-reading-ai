## Configuración centralizada para la conexión con la API de lecturas.
## Modificar estos valores según el entorno (desarrollo / producción).
class_name ApiConfig

# ─── Conexión ────────────────────────────────────────────────────────────────

## URL base de la API REST (sin barra final).
const BASE_URL: String = "http://localhost:8000"

## Tiempo máximo de espera por petición HTTP (en segundos).
const TIMEOUT_SECONDS: float = 10.0

## Número máximo de reintentos ante fallos de red.
const MAX_RETRIES: int = 3

## Factor base para backoff exponencial (en segundos).
## Reintento 1 = 1s, reintento 2 = 2s, reintento 3 = 4s.
const BACKOFF_BASE: float = 1.0

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

## Token Bearer JWT. Dejar vacío para omitir autenticación.
## En producción, cargar desde un archivo seguro o variable de entorno.
const AUTH_TOKEN: String = ""

# ─── Paginación por defecto ──────────────────────────────────────────────────

## Elementos por página al listar lecturas.
const DEFAULT_PER_PAGE: int = 10

## Tamaño máximo aceptado por la API.
const MAX_PER_PAGE: int = 50
