extends CharacterBody3D

@export var display_name := "Town Resident"
@export var dialogue := "Welcome to the old town. There is always something to discover."
@export var wander_radius := 9.0
@export var move_speed := 1.25

var home_position := Vector3.ZERO
var target_position := Vector3.ZERO
var wait_time := 0.0
var body_mesh: MeshInstance3D
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

func interact() -> String:
	return display_name + ": " + dialogue

func _choose_destination() -> void:
	var angle := randf() * TAU
	var distance := randf_range(2.0, wander_radius)
	target_position = home_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	wait_time = randf_range(1.0, 3.0)

func _build_appearance() -> void:
	body_mesh = MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.28
	body.height = 1.25
	body_mesh.mesh = body
	body_mesh.position.y = 0.85
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(randf_range(0.18,0.85),randf_range(0.2,0.78),randf_range(0.25,0.82))
	material.roughness = 0.75
	body_mesh.material_override = material
	add_child(body_mesh)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	head.mesh = sphere
	head.position.y = 1.62
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.64, 0.5)
	head.material_override = skin
	add_child(head)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)
