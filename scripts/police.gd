extends CharacterBody3D

@export var chase_speed := 5.4
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var escape_timer := 0.0
var alert_flash := 0.0
var siren_light: OmniLight3D

func _ready() -> void:
	add_to_group("city_police")
	_build_officer()

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not is_on_floor():
		velocity.y -= gravity * delta
	if player == null or GameState.wanted_level <= 0:
		velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)
		move_and_slide()
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > 48.0:
		escape_timer += delta
		if escape_timer > 16.0:
			GameState.set_wanted(0)
			player.call("_show_message", "POLICE LOST YOUR TRAIL • Wanted level cleared.")
			escape_timer = 0.0
			return
	else:
		escape_timer = 0.0
	if distance > 1.55:
		var direction := to_player.normalized()
		velocity.x = move_toward(velocity.x, direction.x * chase_speed, 12.0 * delta)
		velocity.z = move_toward(velocity.z, direction.z * chase_speed, 12.0 * delta)
		look_at(global_position + direction, Vector3.UP)
	else:
		_arrest_player(player)
	move_and_slide()
	alert_flash += delta
	if siren_light:
		siren_light.light_energy = 0.7 + absf(sin(alert_flash * 5.5)) * 1.8

func _arrest_player(player: CharacterBody3D) -> void:
	var fine := mini(30, GameState.cash_wallet)
	GameState.add_cash(-fine)
	GameState.set_wanted(0)
	player.global_position = Vector3(0, 1.2, 10)
	player.velocity = Vector3.ZERO
	player.call("_show_message", "ARRESTED • $%d fine paid. You are back at the city station." % fine)
	AudioManager.play_alert()
	global_position = Vector3(-12, 0.1, -10)

func _build_officer() -> void:
	var uniform := StandardMaterial3D.new()
	uniform.albedo_color = Color(0.055, 0.14, 0.32)
	uniform.roughness = 0.7
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.025, 0.035, 0.055)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.72, 0.56, 0.43)
	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.25
	torso_mesh.height = 0.9
	torso.mesh = torso_mesh
	torso.position.y = 1.05
	torso.material_override = uniform
	add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.2
	head_mesh.height = 0.4
	head.mesh = head_mesh
	head.position.y = 1.77
	head.material_override = skin
	add_child(head)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.43, 0.12, 0.43)
	cap.mesh = cap_mesh
	cap.position.y = 1.99
	cap.material_override = dark
	add_child(cap)
	var badge := MeshInstance3D.new()
	var badge_mesh := BoxMesh.new()
	badge_mesh.size = Vector3(0.12, 0.16, 0.035)
	badge.mesh = badge_mesh
	badge.position = Vector3(0.12, 1.28, -0.24)
	var badge_material := StandardMaterial3D.new()
	badge_material.albedo_color = Color(0.95, 0.72, 0.22)
	badge.material_override = badge_material
	add_child(badge)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.105
		arm_mesh.height = 0.72
		arm.mesh = arm_mesh
		arm.position = Vector3(side * 0.34, 1.0, 0.0)
		arm.material_override = uniform
		add_child(arm)
		var leg := MeshInstance3D.new()
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.12
		leg_mesh.height = 0.78
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 0.13, 0.38, 0.0)
		leg.material_override = dark
		add_child(leg)
	var collision := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.32
	capsule_shape.height = 1.9
	collision.shape = capsule_shape
	collision.position.y = 0.95
	add_child(collision)
	siren_light = OmniLight3D.new()
	siren_light.position = Vector3(0, 2.25, 0)
	siren_light.light_color = Color(0.18, 0.45, 1.0)
	siren_light.light_energy = 0.0
	siren_light.omni_range = 3.5
	add_child(siren_light)
