extends CharacterBody3D

@export var display_name := "Town Resident"
@export var dialogue := "Welcome to the old town. There is always something to discover."
@export var wander_radius := 9.0
@export var move_speed := 1.25

var home_position := Vector3.ZERO
var target_position := Vector3.ZERO
var wait_time := 0.0
var body_mesh: MeshInstance3D
var arm_pivots: Array[Node3D] = []
var leg_pivots: Array[Node3D] = []
var walk_clock := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	add_to_group("interactables")
	home_position = global_position
	target_position = home_position
	_build_appearance()
	_choose_destination()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var flat_target := target_position - global_position
	flat_target.y = 0.0
	if wait_time > 0.0:
		wait_time -= delta
		velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
	elif flat_target.length() < 0.7:
		_choose_destination()
	else:
		var direction := flat_target.normalized()
		velocity.x = move_toward(velocity.x, direction.x * move_speed, 3.0 * delta)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, 3.0 * delta)
		if body_mesh:
			look_at(global_position + direction, Vector3.UP)
	move_and_slide()
	var movement_speed := Vector2(velocity.x, velocity.z).length()
	if movement_speed > 0.12:
		walk_clock += delta * 8.0
	var swing := sin(walk_clock) * clampf(movement_speed / maxf(move_speed, 0.1), 0.0, 1.0) * 0.48
	for index in range(arm_pivots.size()):
		arm_pivots[index].rotation.x = swing if index == 0 else -swing
	for index in range(leg_pivots.size()):
		leg_pivots[index].rotation.x = -swing if index == 0 else swing

func interact() -> String:
	return display_name + ": " + dialogue

func _choose_destination() -> void:
	var angle := randf() * TAU
	var distance := randf_range(0.35, maxf(0.4, wander_radius))
	target_position = home_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	wait_time = randf_range(1.0, 3.0)

func _build_appearance() -> void:
	var outfit_colors := [Color(0.12,0.36,0.62),Color(0.56,0.22,0.16),Color(0.18,0.43,0.31),Color(0.42,0.30,0.52),Color(0.68,0.48,0.19)]
	var outfit := StandardMaterial3D.new()
	outfit.albedo_color = outfit_colors[randi_range(0,outfit_colors.size()-1)]
	outfit.roughness = 0.82
	var trousers := StandardMaterial3D.new()
	trousers.albedo_color = Color(0.075,0.09,0.12)
	trousers.roughness = 0.92
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78,0.64,0.52)
	skin.roughness = 0.72
	var shoes := StandardMaterial3D.new()
	shoes.albedo_color = Color(0.035,0.04,0.05)
	shoes.roughness = 0.86

	body_mesh = MeshInstance3D.new()
	body_mesh.name = "Torso"
	var torso := CapsuleMesh.new()
	torso.radius = 0.24
	torso.height = 0.88
	body_mesh.mesh = torso
	body_mesh.position.y = 1.05
	body_mesh.material_override = outfit
	add_child(body_mesh)

	var neck := MeshInstance3D.new()
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.085
	neck_mesh.bottom_radius = 0.095
	neck_mesh.height = 0.18
	neck.mesh = neck_mesh
	neck.position.y = 1.56
	neck.material_override = skin
	add_child(neck)

	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.205
	sphere.height = 0.42
	head.mesh = sphere
	head.position.y = 1.78
	head.material_override = skin
	add_child(head)

	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.208
	hair_mesh.height = 0.22
	hair.mesh = hair_mesh
	hair.position = Vector3(0,1.91,0.015)
	var hair_material := StandardMaterial3D.new()
	hair_material.albedo_color = Color(0.075,0.055,0.045)
	hair_material.roughness = 0.94
	hair.material_override = hair_material
	add_child(hair)

	for side in [-1.0,1.0]:
		var arm_pivot := Node3D.new()
		arm_pivot.position = Vector3(side*0.29,1.38,0)
		add_child(arm_pivot)
		var arm := MeshInstance3D.new()
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.105
		arm_mesh.height = 0.68
		arm.mesh = arm_mesh
		arm.position.y = -0.31
		arm.material_override = outfit
		arm_pivot.add_child(arm)
		var hand := MeshInstance3D.new()
		var hand_mesh := SphereMesh.new()
		hand_mesh.radius = 0.105
		hand_mesh.height = 0.20
		hand.mesh = hand_mesh
		hand.position.y = -0.67
		hand.material_override = skin
		arm_pivot.add_child(hand)
		arm_pivots.append(arm_pivot)

	for side in [-1.0,1.0]:
		var leg_pivot := Node3D.new()
		leg_pivot.position = Vector3(side*0.13,0.68,0)
		add_child(leg_pivot)
		var leg := MeshInstance3D.new()
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.12
		leg_mesh.height = 0.72
		leg.mesh = leg_mesh
		leg.position.y = -0.31
		leg.material_override = trousers
		leg_pivot.add_child(leg)
		var shoe := MeshInstance3D.new()
		var shoe_mesh := BoxMesh.new()
		shoe_mesh.size = Vector3(0.23,0.13,0.34)
		shoe.mesh = shoe_mesh
		shoe.position = Vector3(0,-0.67,-0.07)
		shoe.material_override = shoes
		leg_pivot.add_child(shoe)
		leg_pivots.append(leg_pivot)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.85
	collision.shape = capsule
	collision.position.y = 0.92
	add_child(collision)
