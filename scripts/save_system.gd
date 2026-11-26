extends Node

const SAVE_PATH := "user://stickman_save.cfg"
signal save_finished(success: bool)

var autosave_elapsed := 0.0
var autosave_interval := 20.0

func _process(delta: float) -> void:
	autosave_elapsed += delta
	if autosave_elapsed >= autosave_interval:
		autosave_elapsed = 0.0
		save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_PREDELETE:
		save_game()

func save_game() -> bool:
	var config := ConfigFile.new()
	config.set_value("player", "position", _player_position())
	var player := get_tree().get_first_node_in_group("player")
	if player:
		config.set_value("player", "rotation", player.global_rotation)
	config.set_value("game", "state", GameState.to_dictionary())
	var result := config.save(SAVE_PATH)
	save_finished.emit(result == OK)
	return result == OK

func load_game() -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	GameState.from_dictionary(config.get_value("game", "state", {}))
	var player := get_tree().get_first_node_in_group("player")
	if player and config.has_section_key("player", "position"):
		player.global_position = config.get_value("player", "position")
		if config.has_section_key("player", "rotation"):
			player.global_rotation = config.get_value("player", "rotation")
		player.velocity = Vector3.ZERO
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func _player_position() -> Vector3:
	var player := get_tree().get_first_node_in_group("player")
	return player.global_position if player else Vector3.ZERO
