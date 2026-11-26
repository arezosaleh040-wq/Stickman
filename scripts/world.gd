extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

func _ready() -> void:
	_create_environment()
	_create_ground()
	_create_town()
	_create_player()

func _create_environment() -> void:
	var world_env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.12, 0.2, 0.34)
	sky_material.sky_horizon_color = Color(0.82, 0.55, 0.34)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.92)
	environment.ambient_light_energy = 0.55
	world_env.environment = environment
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

func _create_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	add_child(ground)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(180, 180)
	mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.24, 0.2)
	material.roughness = 1.0
	mesh.material_override = material
	ground.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(180, 0.2, 180)
	collision.shape = shape
	collision.position.y = -0.1
	ground.add_child(collision)

func _create_town() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4127
	for x in range(-4, 5):
		for z in range(-4, 5):
			if abs(x) < 2 and abs(z) < 2:
				continue
			var width := rng.randf_range(5.0, 8.0)
			var depth := rng.randf_range(5.0, 8.0)
			var height := rng.randf_range(5.0, 13.0)
			var building := StaticBody3D.new()
			building.position = Vector3(x * 15.0, height * 0.5, z * 15.0)
			add_child(building)

			var box := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(width, height, depth)
			box.mesh = box_mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(
				rng.randf_range(0.34, 0.62),
				rng.randf_range(0.27, 0.48),
				rng.randf_range(0.18, 0.34)
			)
			mat.roughness = 0.88
			box.material_override = mat
			building.add_child(box)

			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(width, height, depth)
			collision.shape = shape
			building.add_child(collision)

func _create_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 1.2, 0)
	add_child(player)
