## Preferencias del jugador: fuente, música y efectos de sonido.
##
## Se guardan en user://progress.cfg (el archivo que ya comparten el tutorial,
## las guías, el alias y los objetivos), en la sección "ajustes", con una clave
## por cuenta igual que el alias: en un mismo equipo juegan varios alumnos y
## ninguno debe heredar los ajustes del anterior.
##
## Se cargan al entrar (progreso cargado) y vuelven a los iniciales al salir:
## así el login usa siempre la fuente predeterminada y no suena nada.
##
## Registrar como Autoload: Project Settings → Autoload → "Ajustes"
extends Node

## Emitida al cambiar un ajuste. Al cargar una cuenta se emite por cada clave,
## aunque el valor no cambie: quien escucha debe ser idempotente.
signal cambiado(clave: String)

## Emitida tras cargar los ajustes de la cuenta que acaba de entrar.
signal sesion_cargada

## Emitida al salir, antes de volver a los valores iniciales.
signal sesion_cerrada

const SECCION := "ajustes"

const VALORES_INICIALES := {
	"fuente": "adventor",
	"musica_activa": true,
	"musica_pista": "biblioteca",
	"musica_volumen": 40,
	"efectos_activos": true,
	"efectos_volumen": 70,
	"comics_vista": "expositor",
}

## Archivo de preferencias. Las pruebas lo cambian para no tocar el real.
var ruta_archivo: String = "user://progress.cfg"

## Cuenta cuyos ajustes están cargados; -1 si no hay nadie dentro.
var usuario: int = -1

var _valores: Dictionary = VALORES_INICIALES.duplicate()


func _ready() -> void:
	AuthManager.progress_loaded.connect(_on_progreso_listo)
	AuthManager.progress_load_failed.connect(_on_progreso_listo)
	AuthManager.logged_out.connect(_on_sesion_terminada)
	AuthManager.session_invalidated.connect(_on_sesion_terminada)


# ─── API pública ─────────────────────────────────────────────────────────────

func obtener(clave: String) -> Variant:
	return _valores.get(clave, VALORES_INICIALES.get(clave))


## Cambia un ajuste. Solo se guarda si hay una cuenta dentro.
func fijar(clave: String, valor: Variant) -> void:
	if _valores.get(clave) == valor:
		return
	_valores[clave] = valor
	if usuario >= 0:
		var cfg := ConfigFile.new()
		# Se carga antes de escribir para no pisar las demás secciones.
		cfg.load(ruta_archivo)
		cfg.set_value(SECCION, _clave(clave), valor)
		cfg.save(ruta_archivo)
	cambiado.emit(clave)


## Carga los ajustes de una cuenta; lo que no tenga guardado toma el valor
## inicial.
func cargar_usuario(id_usuario: int) -> void:
	usuario = id_usuario
	var cfg := ConfigFile.new()
	cfg.load(ruta_archivo)
	for clave in VALORES_INICIALES:
		var inicial = VALORES_INICIALES[clave]
		var valor = cfg.get_value(SECCION, _clave(clave), inicial)
		# Un valor de otro tipo (archivo editado a mano) no se acepta.
		_valores[clave] = valor if typeof(valor) == typeof(inicial) else inicial
	for clave in VALORES_INICIALES:
		cambiado.emit(clave)
	sesion_cargada.emit()


## Vuelve a los valores iniciales sin nadie dentro. sesion_cerrada va primero:
## así Sonido ya está inactivo cuando le llegan los valores iniciales.
func restablecer() -> void:
	usuario = -1
	_valores = VALORES_INICIALES.duplicate()
	sesion_cerrada.emit()
	for clave in VALORES_INICIALES:
		cambiado.emit(clave)


# ─── Inicio y fin de sesión ──────────────────────────────────────────────────

## Conectada a progress_loaded y a progress_load_failed (por eso el parámetro
## no tiene tipo): en los dos casos el alumno entra al juego.
func _on_progreso_listo(_dato: Variant = null) -> void:
	if AuthManager.is_authenticated:
		cargar_usuario(AuthManager.get_user_id())


func _on_sesion_terminada() -> void:
	restablecer()


func _clave(nombre: String) -> String:
	return "%s_%d" % [nombre, usuario]
