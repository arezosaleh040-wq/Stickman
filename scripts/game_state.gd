extends Node

signal economy_changed(money: int, experience: int)
signal mission_changed(title: String, completed: bool)

var money := 250
var experience := 0
var inventory: Dictionary = {"health_potion": 1, "wood": 0, "stone": 0}
var active_mission := "Explore the Old Plaza"
var mission_completed := false
var owned_properties: Array[String] = []

func add_money(amount: int) -> void:
	money = maxi(0, money + amount)
	economy_changed.emit(money, experience)

func add_experience(amount: int) -> void:
	experience = maxi(0, experience + amount)
	economy_changed.emit(money, experience)

func set_mission(title: String) -> void:
	active_mission = title
	mission_completed = false
	mission_changed.emit(active_mission, mission_completed)

func complete_mission(reward: int, xp: int) -> void:
	if mission_completed:
		return
	mission_completed = true
	add_money(reward)
	add_experience(xp)
	mission_changed.emit(active_mission, mission_completed)

func to_dictionary() -> Dictionary:
	return {
		"money": money,
		"experience": experience,
		"inventory": inventory.duplicate(true),
		"active_mission": active_mission,
		"mission_completed": mission_completed,
		"owned_properties": owned_properties.duplicate()
	}

func from_dictionary(data: Dictionary) -> void:
	money = int(data.get("money", 250))
	experience = int(data.get("experience", 0))
	inventory = data.get("inventory", {"health_potion": 1, "wood": 0, "stone": 0})
	active_mission = str(data.get("active_mission", "Explore the Old Plaza"))
	mission_completed = bool(data.get("mission_completed", false))
	owned_properties.clear()
	for item in data.get("owned_properties", []):
		owned_properties.append(str(item))
	economy_changed.emit(money, experience)
	mission_changed.emit(active_mission, mission_completed)
