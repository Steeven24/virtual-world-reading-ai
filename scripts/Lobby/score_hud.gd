## HUD de puntuación para el Lobby.
## Muestra la puntuación total, botón para ver logros y botón de menú (⚙️)
## con opción de cerrar sesión.
## Se conecta a GameSession.score_changed para actualizarse automáticamente.
extends CanvasLayer

@onready var score_label: Label = %ScoreLabel
@onready var achievements_panel: PanelContainer = %AchievementsPanel
@onready var achievements_list: VBoxContainer = %AchievementsList
@onready var toggle_button: Button = %ToggleButton
@onready var close_button: Button = %CloseButton
@onready var leaderboard_button: Button = %LeaderboardButton
@onready var menu_button: Button = %MenuButton
@onready var menu_panel: PanelContainer = %MenuPanel
@onready var user_name_label: Label = %UserNameLabel
@onready var user_email_label: Label = %UserEmailLabel
@onready var logout_button: Button = %LogoutButton
@onready var close_menu_button: Button = %CloseMenuButton

const FONT_PATH := "res://fonts/PixelifySans-SemiBold.ttf"
const LOGIN_SCENE := "res://scenes/UI/login_screen.tscn"

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
	menu_panel.visible = false
	_update_score(GameSession.get_total_score())
	GameSession.score_changed.connect(_update_score)
	GameSession.achievement_unlocked.connect(_on_achievement_unlocked)
	ProgressionManager.progression_changed.connect(_on_progression_changed)
	toggle_button.pressed.connect(_toggle_achievements)
	close_button.pressed.connect(_toggle_achievements)
	leaderboard_button.pressed.connect(_show_leaderboard)
	menu_button.pressed.connect(_toggle_menu)
	close_menu_button.pressed.connect(_toggle_menu)
	logout_button.pressed.connect(_on_logout_pressed)
	
	# Mostrar datos del usuario autenticado
	_update_user_info()


func _update_score(total: int) -> void:
	score_label.text = "⭐ %d pts" % total


func _update_user_info() -> void:
	var display_name: String = AuthManager.get_display_name()
	var email: String = AuthManager.current_user.get("email", "")
	user_name_label.text = display_name
	user_email_label.text = email


func _toggle_achievements() -> void:
	var panel_scene = load("res://scenes/UI/achievements_medals_panel.tscn")
	if panel_scene:
		var instance = panel_scene.instantiate()
		get_tree().root.add_child(instance)


func _show_leaderboard() -> void:
	var lb_scene = load("res://scenes/UI/leaderboard_panel.tscn")
	if lb_scene:
		var instance = lb_scene.instantiate()
		get_tree().root.add_child(instance)


func _toggle_menu() -> void:
	menu_panel.visible = not menu_panel.visible
	if menu_panel.visible:
		achievements_panel.visible = false  # Cerrar logros si están abiertos
		_update_user_info()


func _on_logout_pressed() -> void:
	# Cerrar sesión en el AuthManager
	AuthManager.logout()
	
	# Resetear estado local del juego
	GameSession.score_data = {
		"total_score": 0,
		"sessions_completed": 0,
		"correct_by_level": {"Literal": 0, "Inferencial": 0, "Critico": 0},
		"incorrect_by_level": {"Literal": 0, "Inferencial": 0, "Critico": 0},
		"typologies_completed": [],
		"perfect_sessions": 0,
		"achievements": [],
		"best_scores_by_typology": {},
	}
	GameSession.set_character("male")
	GameSession.reset_tutorial()
	
	# Resetear progresión
	ProgressionManager.reset_all()
	
	print("[ScoreHUD] Sesión cerrada, volviendo al login")
	get_tree().change_scene_to_file(LOGIN_SCENE)


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
