extends StaticBody3D

@export var display_name := "City Notice Board"
@export_multiline var description := "A place to find work and local stories."
@export_enum("mission", "job", "shop", "property") var interaction_type := "mission"
@export var reward := 120
@export var experience_reward := 35

func _ready() -> void:
	add_to_group("interactables")

func interact() -> String:
	match interaction_type:
		"mission":
			GameState.set_mission("The First Errand")
			return "New mission: The First Errand. Explore the plaza and return here."
		"job":
			GameState.add_money(25)
			GameState.add_experience(5)
			return "You completed a quick city task: +25 coins."
		"shop":
			if GameState.money >= 50:
				GameState.add_money(-50)
				GameState.inventory["health_potion"] = int(GameState.inventory.get("health_potion", 0)) + 1
				return "Purchased a supply item for 50 coins."
			return "Not enough coins. You need 50."
		"property":
			if GameState.owned_properties.has(display_name):
				return "You already own this property."
			if GameState.money >= 200:
				GameState.add_money(-200)
				GameState.owned_properties.append(display_name)
				return "Property acquired: " + display_name
			return "This property costs 200 coins."
	return description
