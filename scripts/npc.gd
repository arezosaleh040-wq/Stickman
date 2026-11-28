extends CharacterBody3D

@export var display_name := "Town Resident"
@export var dialogue := "Welcome to the old town. There is always something to discover."
@export var wander_radius := 105.0
@export var move_speed := 1.65

var home_position := Vector3.ZERO
var target_position := Vector3.ZERO
var wait_time := 0.0
var body_mesh: MeshInstance3D
var arm_pivots: Array[Node3D] = []
var leg_pivots: Array[Node3D] = []
var walk_clock := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var stuck_time := 0.0
var previous_position := Vector3.ZERO
var activity_anchor := Vector3.ZERO
var activity_name := "Exploring the district"
var routine_phase := -1
var steering_direction := Vector3.ZERO
var repath_cooldown := 0.0
var flee_repath_cooldown := 0.0
@export_range(0.0, 1.0) var schedule_offset := 0.0

const ARRIVAL_DISTANCE := 0.72
const PROBE_DISTANCE := 1.75
const STEER_ACCELERATION := 5.5
const STOP_ACCELERATION := 8.5

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("town_npcs")
	floor_snap_length = 0.45
	safe_margin = 0.025
	max_slides = 6
	floor_max_angle = deg_to_rad(48.0)
	home_position = global_position
	previous_position = global_position
	_build_appearance()
	activity_anchor = home_position
	_sync_daily_routine(true)
	_choose_destination()
	# Residents should not physically lock one another in narrow streets.
	for other in get_tree().get_nodes_in_group("town_npcs"):
		if other != self and other is PhysicsBody3D:
			add_collision_exception_with(other)

func _physics_process(delta: float) -> void:
	repath_cooldown = maxf(0.0, repath_cooldown - delta)
	flee_repath_cooldown = maxf(0.0, flee_repath_cooldown - delta)
	_sync_daily_routine()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var player := get_tree().get_first_node_in_group("player") as Node3D
	var fleeing := GameState.wanted_level > 0 and player != null and global_position.distance_to(player.global_position) < 22.0
	if fleeing and flee_repath_cooldown <= 0.0:
		var away := global_position - player.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3.RIGHT
		target_position = global_position + away.normalized() * 13.0
		wait_time = 0.0
		flee_repath_cooldown = 0.55

	var to_target := target_position - global_position
	to_target.y = 0.0
	var distance_to_target := to_target.length()
	var desired_direction := Vector3.ZERO

	if fleeing:
		desired_direction = _steer_around_obstacles(to_target.normalized())
		wait_time = 0.0
	elif wait_time > 0.0:
		wait_time = maxf(0.0, wait_time - delta)
	elif distance_to_target <= ARRIVAL_DISTANCE:
		_choose_destination()
	else:
		desired_direction = _steer_around_obstacles(to_target.normalized())
		if desired_direction == Vector3.ZERO and repath_cooldown <= 0.0:
			_choose_destination()
			repath_cooldown = 0.35

	if desired_direction != Vector3.ZERO:
		steering_direction = steering_direction.lerp(desired_direction, minf(delta * 5.0, 1.0)).normalized()
		var current_speed := move_speed * (1.45 if fleeing else 1.0)
		var target_velocity := steering_direction * current_speed
		velocity.x = move_toward(velocity.x, target_velocity.x, STEER_ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, STEER_ACCELERATION * delta)
		var target_yaw := atan2(-steering_direction.x, -steering_direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 7.0, 1.0))
	else:
		steering_direction = steering_direction.lerp(Vector3.ZERO, minf(delta * 7.0, 1.0))
		velocity.x = move_toward(velocity.x, 0.0, STOP_ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, STOP_ACCELERATION * delta)

	move_and_slide()

	if is_on_wall() and repath_cooldown <= 0.0:
		_choose_destination()
		repath_cooldown = 0.45

	_wrap_world_edges()
	var moved_distance := global_position.distance_to(previous_position)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if moved_distance < 0.008 and distance_to_target > 1.0 and wait_time <= 0.0 and desired_direction != Vector3.ZERO:
		stuck_time += delta
	else:
		stuck_time = maxf(0.0, stuck_time - delta * 1.5)
	if stuck_time > 1.1 and repath_cooldown <= 0.0:
		_choose_destination()
		stuck_time = 0.0
		repath_cooldown = 0.6
	previous_position = global_position

	if horizontal_speed > 0.10:
		walk_clock += delta * (12.0 if fleeing else 9.5) * clampf(horizontal_speed / maxf(move_speed, 0.1), 0.7, 1.5)
	var swing := sin(walk_clock) * clampf(horizontal_speed / maxf(move_speed, 0.1), 0.0, 1.25) * 0.43
	var anim_weight := clampf(horizontal_speed / maxf(move_speed, 0.1), 0.0, 1.0)
	for index in range(arm_pivots.size()):
		var target_swing := swing if index == 0 else -swing
		arm_pivots[index].rotation.x = lerpf(arm_pivots[index].rotation.x, target_swing, minf(delta * 10.0, 1.0))
	for index in range(leg_pivots.size()):
		var target_leg := -swing if index == 0 else swing
		leg_pivots[index].rotation.x = lerpf(leg_pivots[index].rotation.x, target_leg, minf(delta * 10.0, 1.0))

func _steer_around_obstacles(desired: Vector3) -> Vector3:
	if desired.length_squared() < 0.001:
		return Vector3.ZERO
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.82
	var right := Vector3(-desired.z, 0.0, desired.x)
	var excluded: Array[RID] = [get_rid()]
	var player := get_tree().get_first_node_in_group("player")
	if player is CollisionObject3D:
		excluded.append(player.get_rid())
	for resident in get_tree().get_nodes_in_group("town_npcs"):
		if resident is CollisionObject3D:
			excluded.append(resident.get_rid())

	var center_clear := _probe_clear(space, origin, desired, excluded, PROBE_DISTANCE)
	if center_clear:
		return desired

	var left := (desired - right * 0.82).normalized()
	var right_dir := (desired + right * 0.82).normalized()
	var left_clear := _probe_clear(space, origin, left, excluded, PROBE_DISTANCE * 0.9)
	var right_clear := _probe_clear(space, origin, right_dir, excluded, PROBE_DISTANCE * 0.9)
	if left_clear and right_clear:
		# Prefer the side that requires the smaller change from the current heading.
		return left if steering_direction.dot(left) >= steering_direction.dot(right_dir) else right_dir
	if left_clear:
		return left
	if right_clear:
		return right_dir
	return Vector3.ZERO

func _probe_clear(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, excluded: Array[RID], distance: float) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance)
	query.exclude = excluded
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	return hit.is_empty()

func _wrap_world_edges() -> void:
	var wrapped := global_position
	var changed := false
	if wrapped.x > 112.0:
		wrapped.x = -112.0
		changed = true
	elif wrapped.x < -112.0:
		wrapped.x = 112.0
		changed = true
	if wrapped.z > 112.0:
		wrapped.z = -112.0
		changed = true
	elif wrapped.z < -112.0:
		wrapped.z = 112.0
		changed = true
	if changed:
		global_position = wrapped
		_choose_destination()

func interact() -> String:
	return display_name + " • " + activity_name + ": " + dialogue

func _sync_daily_routine(force: bool = false) -> void:
	var clock_value := 0.22
	var world := get_parent()
	if world != null:
		var clock_data: Variant = world.get("day_clock")
		if clock_data != null:
			clock_value = float(clock_data)
	var shifted_clock := fposmod(clock_value + schedule_offset, 1.0)
	var hour := int(shifted_clock * 24.0)
	var next_phase := 3
	if hour >= 6 and hour < 10:
		next_phase = 0
	elif hour >= 10 and hour < 17:
		next_phase = 1
	elif hour >= 17 and hour < 22:
		next_phase = 2
	if not force and next_phase == routine_phase:
		return
	routine_phase = next_phase
	match routine_phase:
		0:
			activity_name = "Morning commute"
			activity_anchor = home_position + Vector3(4.0, 0.0, 2.5)
		1:
			activity_name = "At work"
			activity_anchor = home_position + Vector3(-5.0, 0.0, 4.0)
		2:
			activity_name = "Evening walk"
			activity_anchor = home_position + Vector3(3.0, 0.0, -5.0)
		_:
			activity_name = "Heading home"
			activity_anchor = home_position
	target_position = Vector3(activity_anchor.x, global_position.y, activity_anchor.z)
	wait_time = 0.0
	repath_cooldown = 0.0

func _choose_destination() -> void:
	var offset := Vector3(randf_range(-7.5, 7.5), 0.0, randf_range(-7.5, 7.5))
	var candidate := activity_anchor + offset
	if global_position.distance_to(home_position) > minf(wander_radius, 95.0):
		candidate = activity_anchor
	target_position = Vector3(candidate.x, global_position.y, candidate.z)
	wait_time = randf_range(0.25, 0.8)

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
