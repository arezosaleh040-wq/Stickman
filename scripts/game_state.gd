extends Node

signal economy_changed(money: int, experience: int)
signal mission_changed(title: String, completed: bool)
signal finances_changed(cash: int, bank: int)
signal inventory_changed()

var money := 250
var experience := 0
var character_skin := 0
var character_name := "SHADOW RUNNER"
var cash_wallet := 85
var bank_balance := 0
var wanted_level := 0
var market_shift_done := false
var selected_hotbar := 0
var hotbar_slots: Array = ["Bank Card", "Phone", "Apple", "Health Kit", "", "", "", "", ""]
var backpack_slots: Array = ["Wood x3", "Stone x2", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
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

func add_cash(amount: int) -> void:
	cash_wallet = maxi(0, cash_wallet + amount)
	finances_changed.emit(cash_wallet, bank_balance)

func deposit_cash(amount: int = -1) -> int:
	var moved := cash_wallet if amount < 0 else mini(cash_wallet, maxi(0, amount))
	if moved <= 0:
		return 0
	cash_wallet -= moved
	bank_balance += moved
	finances_changed.emit(cash_wallet, bank_balance)
	return moved

func set_wanted(value: int) -> void:
	wanted_level = clampi(value, 0, 3)

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
		"character_skin": character_skin,
		"character_name": character_name,
		"cash_wallet": cash_wallet,
		"bank_balance": bank_balance,
		"wanted_level": wanted_level,
		"market_shift_done": market_shift_done,
		"selected_hotbar": selected_hotbar,
		"hotbar_slots": hotbar_slots.duplicate(true),
		"backpack_slots": backpack_slots.duplicate(true),
		"inventory": inventory.duplicate(true),
		"active_mission": active_mission,
		"mission_completed": mission_completed,
		"owned_properties": owned_properties.duplicate()
	}

func from_dictionary(data: Dictionary) -> void:
	money = int(data.get("money", 250))
	experience = int(data.get("experience", 0))
	character_skin = clampi(int(data.get("character_skin", 0)), 0, 9)
	character_name = str(data.get("character_name", "SHADOW RUNNER"))
	cash_wallet = int(data.get("cash_wallet", 85))
	bank_balance = int(data.get("bank_balance", 0))
	wanted_level = int(data.get("wanted_level", 0))
	market_shift_done = bool(data.get("market_shift_done", false))
	selected_hotbar = clampi(int(data.get("selected_hotbar", 0)), 0, 8)
	hotbar_slots = data.get("hotbar_slots", ["Bank Card", "Phone", "Apple", "Health Kit", "", "", "", "", ""]).duplicate(true)
	backpack_slots = data.get("backpack_slots", ["Wood x3", "Stone x2", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]).duplicate(true)
	while hotbar_slots.size() < 9:
		hotbar_slots.append("")
	while backpack_slots.size() < 18:
		backpack_slots.append("")
	inventory = data.get("inventory", {"health_potion": 1, "wood": 0, "stone": 0}).duplicate(true)
	active_mission = str(data.get("active_mission", "Explore the Old Plaza"))
	mission_completed = bool(data.get("mission_completed", false))
	owned_properties.clear()
	for item in data.get("owned_properties", []):
		owned_properties.append(str(item))
	economy_changed.emit(money, experience)
	finances_changed.emit(cash_wallet, bank_balance)
	inventory_changed.emit()
	mission_changed.emit(active_mission, mission_completed)
