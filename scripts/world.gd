extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const INTERACTABLE_SCRIPT = preload("res://scripts/interactable.gd")
var day_clock := 0.22
var sun: DirectionalLight3D
var clock_label: Label
var cloud_layers: Array[Node3D] = []
var wind_trees: Array[Node3D] = []
var flying_birds: Array[Dictionary] = []
var terrain_material: StandardMaterial3D
var asphalt_material: StandardMaterial3D
var bark_material: StandardMaterial3D
var plaster_material: StandardMaterial3D
var stone_material: StandardMaterial3D
var leaf_shader: Shader

func _ready() -> void:
	_create_environment()
	_create_surface_materials()
	_create_cloud_layers()
	_create_ground()
	_create_roads()
	_create_rolling_hills()
	_create_walkable_staircases()
	_create_city_decor()
	_create_flying_birds()
	_create_town()
	_create_landmarks()
	_create_city_services()
	_create_residents()
	_create_sample_interior()
	_create_player()
	_create_world_hud()

func _process(delta: float) -> void:
	day_clock = fposmod(day_clock + delta * 0.0007, 1.0)
	for cloud in cloud_layers:
		cloud.position.x += delta * float(cloud.get_meta("drift_speed", 0.7))
		if cloud.position.x > 145.0:
			cloud.position.x = -145.0
	var wind_time := Time.get_ticks_msec() * 0.001
	for tree in wind_trees:
		var phase := float(tree.get_meta("wind_phase", 0.0))
		var strength := float(tree.get_meta("wind_strength", 1.0))
		tree.rotation.z = sin(wind_time * 0.72 + phase) * 0.012 * strength
		tree.rotation.x = cos(wind_time * 0.57 + phase * 1.4) * 0.008 * strength
	for bird_data in flying_birds:
		var bird: Node3D = bird_data["root"]
		var phase := float(bird_data["phase"])
		var orbit_time := wind_time * float(bird_data["speed"]) + phase
		var radius := float(bird_data["radius"])
		var center: Vector3 = bird_data["center"]
		bird.position = center + Vector3(cos(orbit_time) * radius, sin(orbit_time * 1.8 + phase) * 0.72, sin(orbit_time) * radius * 0.68)
		var flight_direction := Vector3(-sin(orbit_time), cos(orbit_time * 1.8 + phase) * 0.12, cos(orbit_time) * 0.68).normalized()
		bird.look_at(bird.position + flight_direction, Vector3.UP)
		bird.rotation.z += sin(orbit_time) * 0.045
		var flap := sin(wind_time * 10.5 + phase * 2.0) * 0.62
		(bird_data["left_wing"] as Node3D).rotation.z = -flap
		(bird_data["right_wing"] as Node3D).rotation.z = flap
	if sun:
		var angle := day_clock * TAU
		sun.rotation_degrees.x = -rad_to_deg(angle) + 90.0
		sun.light_energy = lerpf(0.12, 1.25, clampf(sin(angle) * 0.5 + 0.5, 0.0, 1.0))
	if clock_label:
		var hour := int(day_clock * 24.0)
		clock_label.text = "WORLD TIME  %02d:%02d" % [hour, int(fposmod(day_clock * 1440.0, 60.0))]

func _create_surface_materials() -> void:
	terrain_material = _noise_material(Color(0.34, 0.43, 0.29), 0.98, 0.055, 5, 512)
	asphalt_material = _noise_material(Color(0.19, 0.21, 0.23), 0.96, 0.12, 3, 512)
	bark_material = _noise_material(Color(0.34, 0.20, 0.11), 1.0, 0.19, 4, 256)
	plaster_material = _noise_material(Color(0.66, 0.57, 0.43), 0.92, 0.085, 4, 512)
	stone_material = _noise_material(Color(0.43, 0.41, 0.37), 0.94, 0.14, 4, 512)
	leaf_shader = Shader.new()
	leaf_shader.code = """
shader_type spatial;
render_mode cull_back;
uniform vec4 leaf_tint : source_color = vec4(0.13, 0.34, 0.18, 1.0);
uniform float wind_strength = 0.09;
uniform float wind_phase = 0.0;
void vertex() {
	float height_weight = clamp(VERTEX.y * 0.8 + 0.35, 0.0, 1.0);
	float gust = sin(TIME * 1.25 + wind_phase + VERTEX.y * 1.7);
	float cross_gust = cos(TIME * 0.82 + wind_phase * 1.6 + VERTEX.x);
	VERTEX.x += gust * wind_strength * height_weight;
	VERTEX.z += cross_gust * wind_strength * 0.34 * height_weight;
}
void fragment() {
	float leaf_variation = 0.91 + 0.07 * sin(UV.x * 31.0 + UV.y * 17.0) * cos(UV.y * 23.0);
	ALBEDO = leaf_tint.rgb * leaf_variation;
	ROUGHNESS = 0.94;
}
"""

func _noise_material(tint: Color, roughness_value: float, frequency: float, octaves: int, resolution: int) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.52
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = resolution
	texture.height = resolution
	texture.seamless = true
	texture.generate_mipmaps = true
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = texture
	material.roughness = roughness_value
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(1.8, 1.8, 1.8)
	return material

func _leaf_material(tint: Color, phase: float, strength: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = leaf_shader
	material.set_shader_parameter("leaf_tint", tint)
	material.set_shader_parameter("wind_phase", phase)
	material.set_shader_parameter("wind_strength", strength)
	return material

func _create_environment() -> void:
	var world_env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.08, 0.15, 0.29)
	sky_material.sky_horizon_color = Color(0.82, 0.49, 0.31)
	sky_material.ground_bottom_color = Color(0.12, 0.13, 0.16)
	sky_material.ground_horizon_color = Color(0.36, 0.32, 0.29)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.75, 0.92)
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.32
	environment.glow_strength = 0.72
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.55, 0.64, 0.78)
	environment.fog_density = 0.0014
	environment.fog_sky_affect = 0.28
	world_env.environment = environment
	world_env.add_to_group("world_environment")
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "DynamicSun"
	sun.add_to_group("world_sun")
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65.0
	add_child(sun)


func _create_cloud_layers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 881204
	var cloud_material := StandardMaterial3D.new()
	cloud_material.albedo_color = Color(0.91, 0.94, 1.0, 0.84)
	cloud_material.roughness = 1.0
	cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for cloud_index in range(12):
		var cloud := Node3D.new()
		cloud.name = "DynamicCloud_%02d" % cloud_index
		cloud.position = Vector3(rng.randf_range(-135.0, 135.0), rng.randf_range(34.0, 48.0), rng.randf_range(-125.0, 125.0))
		cloud.set_meta("drift_speed", rng.randf_range(0.35, 0.95))
		cloud.add_to_group("world_clouds")
		if cloud_index >= 6:
			cloud.add_to_group("world_clouds_cinematic")
		add_child(cloud)
		cloud_layers.append(cloud)
		var puff_count := rng.randi_range(6, 10)
		for puff_index in range(puff_count):
			var puff := MeshInstance3D.new()
			var puff_mesh := SphereMesh.new()
			puff_mesh.radius = 1.0
			puff_mesh.height = 1.7
			puff.mesh = puff_mesh
			puff.position = Vector3(rng.randf_range(-5.0, 5.0), rng.randf_range(-0.65, 0.65), rng.randf_range(-2.4, 2.4))
			puff.scale = Vector3(rng.randf_range(2.1, 4.0), rng.randf_range(0.55, 1.05), rng.randf_range(1.7, 3.1))
			puff.material_override = cloud_material
			cloud.add_child(puff)

func _create_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Terrain"
	add_child(ground)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	mesh.mesh = plane
	mesh.material_override = terrain_material
	ground.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(240, 0.2, 240)
	collision.shape = shape
	collision.position.y = -0.1
	ground.add_child(collision)

func _create_roads() -> void:
	var road_mat: Material = asphalt_material
	var line_mat := _mat(Color(0.88, 0.72, 0.36), 0.8)
	for axis in [-1, 1]:
		var road := MeshInstance3D.new()
		var road_mesh := BoxMesh.new()
		road_mesh.size = Vector3(14, 0.08, 220) if axis == -1 else Vector3(220, 0.08, 14)
		road.mesh = road_mesh
		road.position.y = 0.045
		road.material_override = road_mat
		add_child(road)
		for i in range(-9, 10):
			var stripe := MeshInstance3D.new()
			var stripe_mesh := BoxMesh.new()
			stripe_mesh.size = Vector3(0.18, 0.025, 3.0) if axis == -1 else Vector3(3.0, 0.025, 0.18)
			stripe.mesh = stripe_mesh
			stripe.position = Vector3(0, 0.1, i * 11.0) if axis == -1 else Vector3(i * 11.0, 0.1, 0)
			stripe.material_override = line_mat
			add_child(stripe)

func _create_town() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4127
	for x in range(-6, 7):
		for z in range(-6, 7):
			if abs(x) <= 1 or abs(z) <= 1:
				continue
			var width := rng.randf_range(6.0, 9.0)
			var depth := rng.randf_range(6.0, 9.0)
			var height := float(rng.randi_range(2, 5)) * rng.randf_range(2.8, 3.2)
			var building := StaticBody3D.new()
			building.name = "Building_%d_%d" % [x, z]
			building.position = Vector3(x * 16.0, height * 0.5, z * 16.0)
			add_child(building)
			var facade := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(width, height, depth)
			facade.mesh = box_mesh
			facade.material_override = plaster_material
			building.add_child(facade)
			var roof := MeshInstance3D.new()
			var roof_mesh := BoxMesh.new()
			roof_mesh.size = Vector3(width + 0.35, 0.22, depth + 0.35)
			roof.mesh = roof_mesh
			roof.position.y = height * 0.5 + 0.12
			roof.material_override = _mat(Color(0.12, 0.14, 0.17), 0.82)
			building.add_child(roof)
			_add_windows(building, width, height, depth)
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(width, height, depth)
			collision.shape = shape
			building.add_child(collision)

func _add_windows(parent: Node3D, width: float, height: float, depth: float) -> void:
	var glass := _mat(Color(0.08, 0.24, 0.32), 0.22)
	for floor_index in range(int(height / 3.0)):
		for side in [-1, 1]:
			for column in range(2):
				var window := MeshInstance3D.new()
				var pane := BoxMesh.new()
				pane.size = Vector3(0.85, 1.15, 0.07)
				window.mesh = pane
				window.position = Vector3((column - 0.5) * width * 0.48, -height * 0.5 + 1.8 + floor_index * 3.0, side * (depth * 0.5 + 0.045))
				window.material_override = glass
				parent.add_child(window)

func _create_landmarks() -> void:
	var plaza := MeshInstance3D.new()
	var plaza_mesh := BoxMesh.new()
	plaza_mesh.size = Vector3(25, 0.18, 25)
	plaza.mesh = plaza_mesh
	plaza.position = Vector3(0, 0.12, 0)
	plaza.material_override = stone_material
	add_child(plaza)
	var tower := StaticBody3D.new()
	tower.name = "OldClockTower"
	tower.position = Vector3(0, 9, -24)
	add_child(tower)
	var tower_mesh := MeshInstance3D.new()
	var tower_box := BoxMesh.new()
	tower_box.size = Vector3(7, 18, 7)
	tower_mesh.mesh = tower_box
	tower_mesh.material_override = stone_material
	tower.add_child(tower_mesh)
	var tower_collision := CollisionShape3D.new()
	var tower_shape := BoxShape3D.new()
	tower_shape.size = Vector3(7, 18, 7)
	tower_collision.shape = tower_shape
	tower.add_child(tower_collision)

func _create_city_services() -> void:
	_spawn_service("Mission Board", "Find your first city mission.", "mission", Vector3(3.5, 0.9, 3.5), Color(0.18, 0.55, 0.78))
	_spawn_service("Work Office", "Take a quick city job.", "job", Vector3(-3.5, 0.9, 3.5), Color(0.78, 0.55, 0.18))
	_spawn_service("Supply Shop", "Buy the animated travel cape for 120 coins, then equip or store it here.", "shop", Vector3(3.5, 0.9, -3.5), Color(0.24, 0.68, 0.42))
	_spawn_service("Small Townhouse", "Purchase your first property.", "property", Vector3(-3.5, 0.9, -3.5), Color(0.64, 0.34, 0.72))

func _spawn_service(title: String, info: String, kind: String, pos: Vector3, tint: Color) -> void:
	var item := StaticBody3D.new()
	item.set_script(INTERACTABLE_SCRIPT)
	item.set("display_name", title)
	item.set("description", info)
	item.set("interaction_type", kind)
	item.position = pos
	add_child(item)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.8, 0.5)
	mesh.mesh = box
	mesh.material_override = _mat(tint, 0.42)
	item.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 1.8, 0.5)
	collision.shape = shape
	item.add_child(collision)

func _create_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 1.2, 10)
	add_child(player)

func _create_world_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.anchor_left = 0.76
	label.anchor_top = 0.025
	label.anchor_right = 0.98
	label.anchor_bottom = 0.09
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.58))
	label.add_theme_font_size_override("font_size", 16)
	layer.add_child(label)
	clock_label = label

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _create_sample_interior() -> void:
	var room_center := Vector3(500, 0, 500)
	var stone := _mat(Color(0.34, 0.32, 0.29), 0.9)
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(14, 0.35, 12)
	floor_mesh.mesh = floor_box
	floor_mesh.position = room_center
	floor_mesh.material_override = stone
	add_child(floor_mesh)
	_create_interior_furniture(room_center)
	var floor_body := StaticBody3D.new()
	floor_body.position = room_center
	add_child(floor_body)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(14, 0.35, 12)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	for wall_data in [
		[Vector3(0, 2, -6), Vector3(14, 4, 0.35)],
		[Vector3(-7, 2, 0), Vector3(0.35, 4, 12)],
		[Vector3(7, 2, 0), Vector3(0.35, 4, 12)],
		[Vector3(0, 2, 6), Vector3(14, 4, 0.35)]
	]:
		var wall := StaticBody3D.new()
		wall.position = room_center + wall_data[0]
		add_child(wall)
		var wall_mesh := MeshInstance3D.new()
		var wall_box := BoxMesh.new()
		wall_box.size = wall_data[1]
		wall_mesh.mesh = wall_box
		wall_mesh.material_override = stone
		wall.add_child(wall_mesh)
		var wall_collision := CollisionShape3D.new()
		var wall_shape := BoxShape3D.new()
		wall_shape.size = wall_data[1]
		wall_collision.shape = wall_shape
		wall.add_child(wall_collision)
	_spawn_door("Townhouse Door", "Enter the furnished starter townhouse.", Vector3(7, 1, 10), room_center + Vector3(0, 1, 3), "You entered the townhouse.")
	_spawn_door("Exit Townhouse", "Return to the city plaza.", room_center + Vector3(0, 1, 5), Vector3(7, 1, 12), "You returned to the city.")

func _spawn_door(title: String, info: String, pos: Vector3, destination: Vector3, feedback: String) -> void:
	var portal := Area3D.new()
	portal.set_script(load("res://scripts/door_portal.gd"))
	portal.set("display_name", title)
	portal.set("destination", destination)
	portal.set("message", feedback)
	portal.position = pos
	add_child(portal)
	var mesh := MeshInstance3D.new()
	var frame := BoxMesh.new()
	frame.size = Vector3(1.4, 2.3, 0.18)
	mesh.mesh = frame
	mesh.material_override = _mat(Color(0.08, 0.65, 0.86), 0.32)
	portal.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 2.5, 1.3)
	collision.shape = shape
	portal.add_child(collision)

func _create_residents() -> void:
	var residents := [
		["Mira the Merchant", "The supply shop has useful items for long journeys.", Vector3(11, 0.1, 5)],
		["Old Rowan", "The clock tower is the oldest landmark in this district.", Vector3(-11, 0.1, 4)],
		["Kai the Courier", "The town office always has small jobs available.", Vector3(9, 0.1, -10)],
		["Lena the Builder", "Some houses are for sale. Save your coins!", Vector3(-10, 0.1, -9)],
		["Noah the Explorer", "Try jumping near low obstacles to vault across them.", Vector3(15, 0.1, 14)],
		["Ari the Guide", "Explore the plaza, then visit the townhouse entrance.", Vector3(-15, 0.1, 13)]
	]
	for resident in residents:
		var npc := CharacterBody3D.new()
		npc.set_script(load("res://scripts/npc.gd"))
		npc.set("display_name", resident[0])
		npc.set("dialogue", resident[1])
		npc.position = resident[2]
		add_child(npc)

func _create_city_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 70261
	for i in range(-5, 6):
		for side in [-1, 1]:
			var tree_position := Vector3(float(i) * 18.0, 0.0, float(side) * 32.0)
			var tree := Node3D.new()
			tree.name = "WindTree_%02d_%d" % [i + 5, side]
			tree.position = tree_position
			tree.set_meta("wind_phase", rng.randf_range(0.0, TAU))
			tree.set_meta("wind_strength", rng.randf_range(0.72, 1.28))
			tree.add_to_group("wind_trees")
			add_child(tree)
			wind_trees.append(tree)

			var trunk := MeshInstance3D.new()
			var trunk_mesh := CylinderMesh.new()
			trunk_mesh.top_radius = 0.19
			trunk_mesh.bottom_radius = 0.31
			trunk_mesh.height = 2.25
			trunk_mesh.radial_segments = 10
			trunk.mesh = trunk_mesh
			trunk.position.y = 1.12
			trunk.material_override = bark_material
			tree.add_child(trunk)

			for branch_side in [-1, 1]:
				var branch := MeshInstance3D.new()
				var branch_mesh := CylinderMesh.new()
				branch_mesh.top_radius = 0.065
				branch_mesh.bottom_radius = 0.12
				branch_mesh.height = 1.05
				branch.mesh = branch_mesh
				branch.position = Vector3(float(branch_side) * 0.34, 1.85, 0.0)
				branch.rotation.z = -float(branch_side) * 0.72
				branch.material_override = bark_material
				tree.add_child(branch)

			var crown_specs := [
				[Vector3(0.0, 2.95, 0.0), 1.22, 2.25, Color(0.13, 0.34, 0.18)],
				[Vector3(-0.72, 2.72, 0.08), 0.78, 1.48, Color(0.16, 0.39, 0.20)],
				[Vector3(0.72, 2.76, -0.06), 0.82, 1.52, Color(0.11, 0.30, 0.16)],
				[Vector3(0.0, 3.48, -0.22), 0.76, 1.42, Color(0.19, 0.40, 0.21)]
			]
			for crown_index in range(crown_specs.size()):
				var spec: Array = crown_specs[crown_index]
				var crown := MeshInstance3D.new()
				var crown_mesh := SphereMesh.new()
				crown_mesh.radius = float(spec[1])
				crown_mesh.height = float(spec[2])
				crown_mesh.radial_segments = 12
				crown_mesh.rings = 8
				crown.mesh = crown_mesh
				crown.position = spec[0]
				crown.material_override = _leaf_material(spec[3], rng.randf_range(0.0, TAU), rng.randf_range(0.055, 0.105))
				tree.add_child(crown)
	for i in range(-4, 5):
		for side in [-1, 1]:
			var lamp := MeshInstance3D.new()
			var pole := CylinderMesh.new()
			pole.top_radius = 0.07
			pole.bottom_radius = 0.1
			pole.height = 4.2
			lamp.mesh = pole
			lamp.position = Vector3(float(i) * 22.0 + 9.0, 2.1, float(side) * 10.5)
			lamp.material_override = _mat(Color(0.12, 0.14, 0.17), 0.48)
			add_child(lamp)
			var lantern := MeshInstance3D.new()
			var globe := SphereMesh.new()
			globe.radius = 0.24
			globe.height = 0.48
			lantern.mesh = globe
			lantern.position = lamp.position + Vector3.UP * 2.0
			lantern.material_override = _mat(Color(0.95, 0.72, 0.36), 0.22)
			add_child(lantern)


func _create_flying_birds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 93417
	var feather_material := _mat(Color(0.105, 0.12, 0.14), 0.82)
	var belly_material := _mat(Color(0.42, 0.39, 0.34), 0.9)
	var beak_material := _mat(Color(0.78, 0.48, 0.16), 0.68)
	for index in range(7):
		var bird := Node3D.new()
		bird.name = "SkyBird_%02d" % index
		add_child(bird)
		var body := MeshInstance3D.new()
		var body_mesh := SphereMesh.new()
		body_mesh.radius = 0.13
		body_mesh.height = 0.22
		body.mesh = body_mesh
		body.scale = Vector3(0.72, 0.72, 1.55)
		body.material_override = feather_material
		bird.add_child(body)
		var belly := MeshInstance3D.new()
		var belly_mesh := SphereMesh.new()
		belly_mesh.radius = 0.105
		belly_mesh.height = 0.15
		belly.mesh = belly_mesh
		belly.position = Vector3(0, -0.055, -0.005)
		belly.scale = Vector3(0.7, 0.44, 1.2)
		belly.material_override = belly_material
		bird.add_child(belly)
		var head := MeshInstance3D.new()
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.085
		head_mesh.height = 0.16
		head.mesh = head_mesh
		head.position = Vector3(0, 0.035, -0.145)
		head.material_override = feather_material
		bird.add_child(head)
		var beak := MeshInstance3D.new()
		var beak_mesh := ConeMesh.new()
		beak_mesh.top_radius = 0.0
		beak_mesh.bottom_radius = 0.035
		beak_mesh.height = 0.12
		beak.mesh = beak_mesh
		beak.position = Vector3(0, 0.015, -0.245)
		beak.rotation.x = -PI * 0.5
		beak.material_override = beak_material
		bird.add_child(beak)
		var left_wing := Node3D.new()
		left_wing.position = Vector3(-0.085, 0.025, 0.015)
		bird.add_child(left_wing)
		var left_wing_mesh := MeshInstance3D.new()
		var left_shape := SphereMesh.new()
		left_shape.radius = 0.12
		left_shape.height = 0.12
		left_wing_mesh.mesh = left_shape
		left_wing_mesh.position.x = -0.205
		left_wing_mesh.scale = Vector3(2.15, 0.18, 0.78)
		left_wing_mesh.material_override = feather_material
		left_wing.add_child(left_wing_mesh)
		var right_wing := Node3D.new()
		right_wing.position = Vector3(0.085, 0.025, 0.015)
		bird.add_child(right_wing)
		var right_wing_mesh := MeshInstance3D.new()
		var right_shape := SphereMesh.new()
		right_shape.radius = 0.12
		right_shape.height = 0.12
		right_wing_mesh.mesh = right_shape
		right_wing_mesh.position.x = 0.205
		right_wing_mesh.scale = Vector3(2.15, 0.18, 0.78)
		right_wing_mesh.material_override = feather_material
		right_wing.add_child(right_wing_mesh)
		flying_birds.append({
			"root": bird,
			"left_wing": left_wing,
			"right_wing": right_wing,
			"center": Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(10.0, 16.0), rng.randf_range(-8.0, 8.0)),
			"radius": rng.randf_range(5.0, 10.0),
			"speed": rng.randf_range(0.12, 0.22),
			"phase": rng.randf_range(0.0, TAU)
		})



func _create_rolling_hills() -> void:
	_create_hill_mound("NorthwestRollingRise", Vector3(-44.0, 0.0, -18.0), 13.0, 3.1, 507)
	_create_hill_mound("SoutheastRollingRise", Vector3(44.0, 0.0, 18.0), 13.0, 2.7, 814)


func _create_hill_mound(label: String, center: Vector3, radius: float, peak_height: float, seed_value: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.22
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.48
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 28
	for z_index in range(segments + 1):
		for x_index in range(segments + 1):
			var local_x := -radius + (2.0 * radius * float(x_index) / float(segments))
			var local_z := -radius + (2.0 * radius * float(z_index) / float(segments))
			var local_y := _hill_height(local_x, local_z, radius, peak_height, noise)
			surface.set_uv(Vector2((local_x / radius + 1.0) * 0.5, (local_z / radius + 1.0) * 0.5))
			surface.add_vertex(Vector3(local_x, local_y, local_z))
	for z_index in range(segments):
		for x_index in range(segments):
			var a := z_index * (segments + 1) + x_index
			var b := a + 1
			var c := a + segments + 1
			var d := c + 1
			surface.add_index(a)
			surface.add_index(c)
			surface.add_index(b)
			surface.add_index(b)
			surface.add_index(c)
			surface.add_index(d)
	surface.generate_normals()
	var hill_mesh := surface.commit()
	var hill_body := StaticBody3D.new()
	hill_body.name = label
	hill_body.position = center
	add_child(hill_body)
	var hill_visual := MeshInstance3D.new()
	hill_visual.mesh = hill_mesh
	hill_visual.material_override = terrain_material
	hill_body.add_child(hill_visual)
	var hill_collision := CollisionShape3D.new()
	hill_collision.shape = hill_mesh.create_trimesh_shape()
	hill_body.add_child(hill_collision)

	var rock_material := _mat(Color(0.35, 0.34, 0.31), 0.98)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 44
	for rock_index in range(16):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(radius * 0.38, radius * 0.91)
		var rock_x := cos(angle) * distance
		var rock_z := sin(angle) * distance
		var rock := MeshInstance3D.new()
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = 0.5
		rock_mesh.height = 0.85
		rock.mesh = rock_mesh
		rock.position = Vector3(rock_x, _hill_height(rock_x, rock_z, radius, peak_height, noise) + 0.16, rock_z)
		rock.scale = Vector3(rng.randf_range(0.25, 0.72), rng.randf_range(0.18, 0.48), rng.randf_range(0.22, 0.62))
		rock.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, TAU), rng.randf_range(-0.2, 0.2))
		rock.material_override = rock_material
		hill_body.add_child(rock)

func _hill_height(local_x: float, local_z: float, radius: float, peak_height: float, noise: FastNoiseLite) -> float:
	var distance := Vector2(local_x, local_z).length()
	var edge := clampf(1.0 - distance / radius, 0.0, 1.0)
	var natural_variation := noise.get_noise_2d(local_x + radius * 2.0, local_z - radius) * 0.10 * edge
	return maxf(0.0, peak_height * pow(edge, 1.62) + natural_variation)


func _create_walkable_staircases() -> void:
	var stone_tread := _mat(Color(0.49, 0.46, 0.40), 0.93)
	var riser_stone := _mat(Color(0.31, 0.32, 0.31), 0.96)
	var rail_material := _mat(Color(0.105, 0.13, 0.15), 0.48)
	_create_staircase("WestTerraceStairs", Vector3(-17.0, 0.0, 14.0), Vector3(1, 0, 0), 12, 0.36, 0.14, 3.5, stone_tread, riser_stone, rail_material)
	_create_staircase("EastTerraceStairs", Vector3(17.0, 0.0, -14.0), Vector3(-1, 0, 0), 12, 0.36, 0.14, 3.5, stone_tread, riser_stone, rail_material)


func _create_staircase(label: String, start: Vector3, forward: Vector3, step_count: int, tread_depth: float, step_height: float, width: float, tread_material: Material, riser_material: Material, rail_material: Material) -> void:
	var stair_root := Node3D.new()
	stair_root.name = label
	stair_root.position = start
	add_child(stair_root)
	stair_root.look_at(start + forward.normalized(), Vector3.UP)
	var total_run := float(step_count) * tread_depth
	var total_rise := float(step_count) * step_height
	var slope_angle := atan2(total_rise, total_run)

	for step_index in range(step_count):
		var tread_body := StaticBody3D.new()
		tread_body.name = "StoneTread_%02d" % step_index
		stair_root.add_child(tread_body)
		var tread_box := BoxMesh.new()
		tread_box.size = Vector3(width, step_height, tread_depth + 0.06)
		var tread_mesh := MeshInstance3D.new()
		tread_mesh.mesh = tread_box
		tread_mesh.position = Vector3(0, (step_index + 1) * step_height - step_height * 0.5, -(step_index * tread_depth + tread_depth * 0.5))
		tread_mesh.material_override = tread_material
		tread_body.add_child(tread_mesh)
		var tread_collision := CollisionShape3D.new()
		var tread_shape := BoxShape3D.new()
		tread_shape.size = tread_box.size
		tread_collision.shape = tread_shape
		tread_collision.position = tread_mesh.position
		tread_body.add_child(tread_collision)

		var riser := MeshInstance3D.new()
		var riser_box := BoxMesh.new()
		riser_box.size = Vector3(width, step_height + 0.025, 0.09)
		riser.mesh = riser_box
		riser.position = Vector3(0, (step_index + 0.5) * step_height, -((step_index + 1) * tread_depth))
		riser.material_override = riser_material
		tread_body.add_child(riser)

		var edge_strip := MeshInstance3D.new()
		var strip_box := BoxMesh.new()
		strip_box.size = Vector3(width - 0.08, 0.035, 0.055)
		edge_strip.mesh = strip_box
		edge_strip.position = tread_mesh.position + Vector3(0, step_height * 0.5 + 0.008, -tread_depth * 0.5 + 0.012)
		edge_strip.material_override = _mat(Color(0.68, 0.61, 0.48), 0.86)
		tread_body.add_child(edge_strip)

	for side in [-1.0, 1.0]:
		for post_index in range(step_count + 1):
			var post := MeshInstance3D.new()
			var post_mesh := CylinderMesh.new()
			post_mesh.top_radius = 0.055
			post_mesh.bottom_radius = 0.075
			post_mesh.height = 0.92
			post.mesh = post_mesh
			post.position = Vector3(side * (width * 0.5 + 0.10), post_index * step_height + 0.46, -(post_index * tread_depth))
			post.material_override = rail_material
			stair_root.add_child(post)
		var rail := MeshInstance3D.new()
		var rail_box := BoxMesh.new()
		rail_box.size = Vector3(0.13, 0.13, sqrt(total_run * total_run + total_rise * total_rise))
		rail.mesh = rail_box
		rail.position = Vector3(side * (width * 0.5 + 0.10), total_rise * 0.5 + 0.88, -total_run * 0.5)
		rail.rotation.x = slope_angle
		rail.material_override = rail_material
		stair_root.add_child(rail)

	var ramp_body := StaticBody3D.new()
	ramp_body.name = "AccessibleSideRamp"
	ramp_body.position = Vector3(width * 0.5 + 1.15, total_rise * 0.5, -total_run * 0.5)
	ramp_body.rotation.x = slope_angle
	stair_root.add_child(ramp_body)
	var ramp_box := BoxMesh.new()
	ramp_box.size = Vector3(1.65, 0.18, sqrt(total_run * total_run + total_rise * total_rise))
	var ramp_mesh := MeshInstance3D.new()
	ramp_mesh.mesh = ramp_box
	ramp_mesh.material_override = riser_material
	ramp_body.add_child(ramp_mesh)
	var ramp_collision := CollisionShape3D.new()
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = ramp_box.size
	ramp_collision.shape = ramp_shape
	ramp_body.add_child(ramp_collision)

	var top_landing := StaticBody3D.new()
	top_landing.name = "UpperLanding"
	top_landing.position = Vector3(0, total_rise - 0.1, -(total_run + 0.72))
	stair_root.add_child(top_landing)
	var landing_box := BoxMesh.new()
	landing_box.size = Vector3(width + 0.6, 0.2, 1.5)
	var landing_mesh := MeshInstance3D.new()
	landing_mesh.mesh = landing_box
	landing_mesh.material_override = stone_material
	top_landing.add_child(landing_mesh)
	var landing_collision := CollisionShape3D.new()
	var landing_shape := BoxShape3D.new()
	landing_shape.size = landing_box.size
	landing_collision.shape = landing_shape
	top_landing.add_child(landing_collision)


func _create_interior_furniture(center: Vector3) -> void:
	var wood := _mat(Color(0.28, 0.14, 0.075), 0.72)
	var fabric := _mat(Color(0.12, 0.3, 0.42), 0.86)
	var cream := _mat(Color(0.72, 0.63, 0.47), 0.9)
	_add_room_box("BedBase", center + Vector3(-3.8, 0.65, -2.2), Vector3(2.5, 0.55, 3.2), wood)
	_add_room_box("BedMattress", center + Vector3(-3.8, 1.05, -2.2), Vector3(2.4, 0.3, 3.1), cream)
	_add_room_box("BedPillow", center + Vector3(-3.8, 1.28, -3.35), Vector3(1.3, 0.2, 0.65), fabric)
	_add_room_box("DiningTable", center + Vector3(2.6, 1.0, -2.1), Vector3(2.5, 0.18, 1.5), wood)
	for leg_x in [-1.0, 1.0]:
		for leg_z in [-0.55, 0.55]:
			_add_room_box("TableLeg", center + Vector3(2.6 + leg_x, 0.5, -2.1 + leg_z), Vector3(0.16, 0.9, 0.16), wood)
	_add_room_box("SofaSeat", center + Vector3(2.5, 0.65, 2.0), Vector3(3.0, 0.45, 1.0), fabric)
	_add_room_box("SofaBack", center + Vector3(2.5, 1.2, 2.45), Vector3(3.0, 0.9, 0.25), fabric)
	_add_room_box("Bookshelf", center + Vector3(-5.7, 1.4, 2.0), Vector3(0.7, 2.8, 2.2), wood)
	_add_room_box("KitchenCounter", center + Vector3(0.0, 0.85, -5.0), Vector3(3.0, 1.6, 0.8), cream)

func _add_room_box(label: String, pos: Vector3, dimensions: Vector3, material: Material) -> void:
	var furniture := MeshInstance3D.new()
	furniture.name = label
	var box := BoxMesh.new()
	box.size = dimensions
	furniture.mesh = box
	furniture.position = pos
	furniture.material_override = material
	add_child(furniture)
