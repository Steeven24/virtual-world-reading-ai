## Música de ambiente y efectos de sonido del juego.
##
## Suena desde que el alumno entra (Ajustes.sesion_cargada) hasta que sale: el
## login no tiene sonido. Dos reproductores permiten fundir una música con otra
## al cambiarla desde el menú; los efectos usan varios reproductores por turnos
## para poder solaparse.
##
## Los volúmenes se ponen en cada reproductor (volume_linear) y la
## reverberación ya va grabada en los archivos: el export web no usa hilos y
## ahí Godot reproduce en modo «sample», donde los efectos de bus no se aplican.
##
## Registrar como Autoload: Project Settings → Autoload → "Sonido"
extends Node

## Emitida al pedir un efecto, suene o no (para comprobar dónde se piden).
signal efecto_pedido(nombre: String)

const PISTAS := {
	"biblioteca": {"nombre": "Biblioteca", "nota": "predeterminada", "ruta": "res://assets/Audio/Musica/biblioteca.ogg"},
	"bosque": {"nombre": "Bosque", "nota": "pájaros y viento", "ruta": "res://assets/Audio/Musica/bosque.ogg"},
	"lluvia": {"nombre": "Lluvia", "nota": "lluvia suave", "ruta": "res://assets/Audio/Musica/lluvia.ogg"},
	"noche": {"nombre": "Noche estrellada", "nota": "soñadora", "ruta": "res://assets/Audio/Musica/noche.ogg"},
	"aventura": {"nombre": "Aventura", "nota": "más animada", "ruta": "res://assets/Audio/Musica/aventura.ogg"},
}

## Orden en el que se ofrecen en el menú.
const ORDEN_PISTAS: Array[String] = ["biblioteca", "bosque", "lluvia", "noche", "aventura"]

const EFECTOS := {
	"clic": "res://assets/Audio/Efectos/clic.wav",
	"abrir": "res://assets/Audio/Efectos/abrir.wav",
	"cerrar": "res://assets/Audio/Efectos/cerrar.wav",
	"puerta": "res://assets/Audio/Efectos/puerta.wav",
	"pagina": "res://assets/Audio/Efectos/pagina.wav",
	"trazo": "res://assets/Audio/Efectos/trazo.wav",
	"acierto": "res://assets/Audio/Efectos/acierto.wav",
	"error": "res://assets/Audio/Efectos/error.wav",
	"fin_lectura": "res://assets/Audio/Efectos/fin_lectura.wav",
	"aprobada": "res://assets/Audio/Efectos/aprobada.wav",
	"desbloqueo": "res://assets/Audio/Efectos/desbloqueo.wav",
	"logro": "res://assets/Audio/Efectos/logro.wav",
	"no": "res://assets/Audio/Efectos/no.wav",
}

## Segundos que tarda una música en fundirse con otra.
const FUNDIDO_PISTA := 1.5
## Segundos que tarda la música en apagarse.
const FUNDIDO_APAGAR := 0.6

const REPRODUCTORES_EFECTOS := 6

## True desde que el alumno entra hasta que sale.
var activo: bool = false

var _musica: Array[AudioStreamPlayer] = []
## Reproductor de _musica con la pista que suena o está entrando.
var _actual: int = 0
var _pista_actual: String = ""
var _fundido: Tween = null

var _efectos: Array[AudioStreamPlayer] = []
var _turno: int = 0

## Botones recién entrados, pendientes de conectar al clic en diferido.
var _botones_pendientes: Array[BaseButton] = []


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Musica%d" % i
		add_child(p)
		_musica.append(p)
	for i in REPRODUCTORES_EFECTOS:
		var p := AudioStreamPlayer.new()
		p.name = "Efecto%d" % i
		add_child(p)
		_efectos.append(p)
	Ajustes.cambiado.connect(_on_ajuste_cambiado)
	Ajustes.sesion_cargada.connect(activar)
	Ajustes.sesion_cerrada.connect(desactivar)
	get_tree().node_added.connect(_on_nodo_agregado)


# ─── API pública ─────────────────────────────────────────────────────────────

## El alumno entró: suena la música elegida. Volver a llamarlo con la misma
## pista sonando no la reinicia (se llama de nuevo al recargar el progreso).
func activar() -> void:
	activo = true
	if Ajustes.obtener("musica_activa"):
		_poner_pista(Ajustes.obtener("musica_pista"))


## El alumno salió: la música se apaga y los efectos se cortan.
func desactivar() -> void:
	activo = false
	_apagar_musica(FUNDIDO_APAGAR)
	for p in _efectos:
		p.stop()


func efecto(nombre: String) -> void:
	efecto_pedido.emit(nombre)
	if not activo or not Ajustes.obtener("efectos_activos") or not EFECTOS.has(nombre):
		return
	var volumen := float(Ajustes.obtener("efectos_volumen")) / 100.0
	if volumen <= 0.0:
		return
	var p := _efectos[_turno]
	_turno = (_turno + 1) % _efectos.size()
	p.stream = load(EFECTOS[nombre])
	p.volume_linear = volumen
	p.play()


func pista_sonando() -> String:
	return _pista_actual


# ─── Música ──────────────────────────────────────────────────────────────────

func _on_ajuste_cambiado(clave: String) -> void:
	if not activo:
		return
	match clave:
		"musica_pista", "musica_activa":
			if Ajustes.obtener("musica_activa"):
				_poner_pista(Ajustes.obtener("musica_pista"))
			else:
				_apagar_musica(FUNDIDO_APAGAR)
		"musica_volumen":
			if not _pista_actual.is_empty():
				# Un cambio de volumen termina cualquier fundido en curso.
				_cortar_fundido()
				for i in _musica.size():
					if i != _actual:
						_musica[i].stop()
				_musica[_actual].volume_linear = _volumen_musica()
		"efectos_activos":
			if not Ajustes.obtener("efectos_activos"):
				for p in _efectos:
					p.stop()


func _volumen_musica() -> float:
	return float(Ajustes.obtener("musica_volumen")) / 100.0


## Funde la música que suena con la pista pedida. Si ya suena esa, nada.
func _poner_pista(id: String) -> void:
	if not PISTAS.has(id):
		id = "biblioteca"
	if id == _pista_actual and _musica[_actual].playing:
		return
	_cortar_fundido()
	var saliente := _musica[_actual]
	_actual = 1 - _actual
	var entrante := _musica[_actual]
	var stream: AudioStream = load(PISTAS[id]["ruta"])
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	entrante.stop()
	entrante.stream = stream
	entrante.volume_linear = 0.0
	entrante.play()
	_pista_actual = id

	_fundido = create_tween().set_parallel(true)
	_fundido.tween_property(entrante, "volume_linear", _volumen_musica(), FUNDIDO_PISTA)
	if saliente.playing:
		_fundido.tween_property(saliente, "volume_linear", 0.0, FUNDIDO_PISTA)
		_fundido.chain().tween_callback(saliente.stop)


func _apagar_musica(duracion: float) -> void:
	_cortar_fundido()
	_pista_actual = ""
	var sonando := _musica.filter(func(p): return p.playing)
	if sonando.is_empty():
		return
	_fundido = create_tween().set_parallel(true)
	for p in sonando:
		_fundido.tween_property(p, "volume_linear", 0.0, duracion)
	_fundido.chain().tween_callback(func():
		for p in sonando:
			p.stop()
	)


func _cortar_fundido() -> void:
	if _fundido and _fundido.is_valid():
		_fundido.kill()
	_fundido = null


# ─── Clic de los botones ─────────────────────────────────────────────────────

## Todo botón suena al pulsarlo, salvo los marcados con la meta "sin_clic"
## (las opciones del quiz, que ya suenan a acierto o error). Se conecta en
## diferido para que el script que crea el botón haya puesto ya la marca.
func _on_nodo_agregado(nodo: Node) -> void:
	if not nodo is BaseButton:
		return
	if _botones_pendientes.is_empty():
		_conectar_botones.call_deferred()
	_botones_pendientes.append(nodo)


func _conectar_botones() -> void:
	var lote := _botones_pendientes
	_botones_pendientes = []
	for boton in lote:
		if not is_instance_valid(boton) or boton.has_meta("sin_clic") or boton.has_meta("_clic_conectado"):
			continue
		boton.set_meta("_clic_conectado", true)
		boton.pressed.connect(efecto.bind("clic"))
