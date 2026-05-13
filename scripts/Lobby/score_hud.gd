## HUD de puntuación para el Lobby.
## Muestra la puntuación total y botón para ver logros.
## Se conecta a GameSession.score_changed para actualizarse automáticamente.
extends CanvasLayer

@onready var score_label: Label = %ScoreLabel
@onready var achievements_panel: PanelContainer = %AchievementsPanel
@onready var achievements_list: VBoxContainer = %AchievementsList
@onready var toggle_button: Button = %ToggleButton
@onready var close_button: Button = %CloseButton

const FONT_PATH := "res://fonts/PixelifySans-SemiBold.ttf"

## Definición de logros con sus nombres para mostrar.
const ACHIEVEMENT_NAMES: Dictionary = {
	"first_reading": "📖 Primera lectura",
	"explorer": "🏅 Explorador",
	"perfectionist": "🎯 Perfeccionista",
	"avid_reader": "📚 Lector ávido",
	"star_literal": "⭐ Estrella literal",
	"star_inferencial": "⭐⭐ Estrella inferencial",
	"star_critico": "⭐⭐⭐ Estrella crítica",
	"improvement": "📈 En mejora",
	"centurion": "💯 Centurión",
	"half_millennium": "🏆 Medio milenio",
}


func _ready() -> void:
	achievements_panel.visible = false
	_update_score(GameSession.get_total_score())
	GameSession.score_changed.connect(_update_score)
	GameSession.achievement_unlocked.connect(_on_achievement_unlocked)
	ProgressionManager.progression_changed.connect(_on_progression_changed)
	toggle_button.pressed.connect(_toggle_achievements)
	close_button.pressed.connect(_toggle_achievements)


func _update_score(total: int) -> void:
	score_label.text = "⭐ %d pts" % total


func _toggle_achievements() -> void:
	achievements_panel.visible = not achievements_panel.visible
	if achievements_panel.visible:
		_populate_achievements()


func _populate_achievements() -> void:
	# Limpiar lista anterior
	for child in achievements_list.get_children():
		child.queue_free()

	var unlocked: Array = GameSession.get_achievements()
	var font = load(FONT_PATH)

	for achievement_id in ACHIEVEMENT_NAMES:
		var display_name: String = ACHIEVEMENT_NAMES[achievement_id]
		var is_unlocked: bool = achievement_id in unlocked

		var label := Label.new()
		if is_unlocked:
			label.text = "✅ %s" % display_name
			label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8, 1.0))
		else:
			label.text = "🔒 %s" % display_name
			label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))

		if font:
			label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 16)
		achievements_list.add_child(label)

	# Estadísticas
	var separator := HSeparator.new()
	achievements_list.add_child(separator)

	var stats := Label.new()
	var sd = GameSession.score_data
	var unlocked_count: int = ProgressionManager.unlocked.size()
	stats.text = "Sesiones: %d | Perfectas: %d\nTipologías: %d/5 | Desbloqueados: %d/5" % [
		sd.get("sessions_completed", 0),
		sd.get("perfect_sessions", 0),
		sd.get("typologies_completed", []).size(),
		unlocked_count,
	]
	stats.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 1.0))
	if font:
		stats.add_theme_font_override("font", font)
	stats.add_theme_font_size_override("font_size", 14)
	achievements_list.add_child(stats)


func _on_achievement_unlocked(_id: String, _display_name: String) -> void:
	# La notificación visual la gestiona el Autoload AchievementToast.
	# Aquí solo refrescamos la lista si está abierta.
	if achievements_panel.visible:
		_populate_achievements()


func _on_progression_changed() -> void:
	_update_score(ProgressionManager.get_total_score())
	if achievements_panel.visible:
		_populate_achievements()
