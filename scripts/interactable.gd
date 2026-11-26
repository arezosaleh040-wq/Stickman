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
			var owns_cape := bool(GameState.inventory.get("cape_owned", false))
			if not owns_cape:
				if GameState.money < 120:
					return "The travel cape costs 120 coins."
				GameState.add_money(-120)
				GameState.inventory["cape_owned"] = true
				GameState.inventory["cape_equipped"] = true
				return "CAPE PURCHASED AND EQUIPPED • Its cloth reacts to wind, running and jumps."
			var cape_is_equipped := bool(GameState.inventory.get("cape_equipped", false))
			GameState.inventory["cape_equipped"] = not cape_is_equipped
			return "Travel cape equipped." if not cape_is_equipped else "Travel cape stored in your inventory."
		"property":
			if GameState.owned_properties.has(display_name):
				return "You already own this property."
			if GameState.money >= 200:
				GameState.add_money(-200)
				GameState.owned_properties.append(display_name)
				return "Property acquired: " + display_name
			return "This property costs 200 coins."
	return description
