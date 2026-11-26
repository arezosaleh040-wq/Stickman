extends Area3D

@export var display_name := "Building Entrance"
@export var destination := Vector3(500, 1.0, 500)
@export_multiline var message := "You entered the building."

func _ready() -> void:
	add_to_group("interactables")

func interact() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = destination
		player.velocity = Vector3.ZERO
		return message
	return "No player found."
