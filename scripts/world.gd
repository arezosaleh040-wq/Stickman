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
var traffic_cars: Array[Dictionary] = []
var traffic_lights: Array[Dictionary] = []
var traffic_elapsed := 0.0
var traffic_dim_materials: Array[StandardMaterial3D] = []
var menu_root: Control
var loading_label: Label
var loading_bar: ProgressBar
var skin_preview_container: SubViewportContainer
var skin_preview_root: Node3D
var skin_preview_model: Node3D
var skin_preview_limbs: Array[Node3D] = []
var skin_preview_arms: Array[Node3D] = []
var skin_preview_arm_elbows: Array[Node3D] = []
var skin_preview_legs: Array[Node3D] = []
var skin_preview_leg_knees: Array[Node3D] = []
var skin_preview_parts: Dictionary = {}
var skin_preview_time := 0.0
var skin_preview_dragging := false
var skin_studio_panel: PanelContainer
var skin_name_input: LineEdit
var skin_details_label: Label

func _ready() -> void:
	_create_startup_screen()
	await get_tree().process_frame
	_set_loading_progress(8, "PREPARING CITY ENGINE")
	_create_environment()
	await get_tree().process_frame
	_create_surface_materials()
	_create_cloud_layers()
	_create_ground()
	_create_roads()
	_create_pedestrian_overpasses()
	_create_rolling_hills()
	_set_loading_progress(35, "LOADING TERRAIN AND ROADS")
	await get_tree().process_frame
	_create_walkable_staircases()
	_create_city_decor()
	_create_flying_birds()
	_create_town()
	_set_loading_progress(62, "GENERATING THE CITY")
	await get_tree().process_frame
	_create_landmarks()
	_create_courthouse()
	_create_city_services()
	_create_supermarket()
	_create_residents()
	_create_police_officer()
	_create_sample_interior()
	_create_traffic_system()
	_set_loading_progress(82, "ADDING TRAFFIC AND PEOPLE")
	await get_tree().process_frame
	_create_player()
	_create_world_hud()
	_set_loading_progress(100, "WORLD READY")
	await get_tree().create_timer(0.45).timeout
	_show_main_menu()

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
	_update_traffic(delta)
	_animate_skin_preview(delta)

func _create_surface_materials() -> void:
	terrain_material = _mat(Color(0.36, 0.45, 0.31), 0.98)
	asphalt_material = _mat(Color(0.23, 0.25, 0.27), 0.98)
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
		var road_body := StaticBody3D.new()
		road_body.name = "RoadCollision_%d" % axis
		road_body.position = road.position
		add_child(road_body)
		var road_collision := CollisionShape3D.new()
		var road_shape := BoxShape3D.new()
		road_shape.size = road_mesh.size
		road_collision.shape = road_shape
		road_body.add_child(road_collision)

	var sidewalk := _mat(Color(0.39,0.39,0.37),0.94)
	for side in [-1.0,1.0]:
		_add_road_surface(Vector3(side*8.25,0.055,0),Vector3(2.0,0.11,220),sidewalk,"ArterialSidewalkV")
		_add_road_surface(Vector3(0,0.055,side*8.25),Vector3(220,0.11,2.0),sidewalk,"ArterialSidewalkH")


func _create_startup_screen() -> void:
	var layer := CanvasLayer.new()
	layer.name = "StartupMenu"
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(menu_root)
	var backdrop := TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.018,0.04,0.085), Color(0.10,0.18,0.29), Color(0.48,0.25,0.19)])
	gradient.offsets = PackedFloat32Array([0.0,0.58,1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1280
	texture.height = 720
	texture.fill_from = Vector2(0,0)
	texture.fill_to = Vector2(0,1)
	backdrop.texture = texture
	menu_root.add_child(backdrop)
	var skyline := Control.new()
	skyline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skyline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(skyline)
	for i in range(20):
		var tower := ColorRect.new()
		var h := 90.0 + float((i * 47) % 190)
		tower.color = Color(0.012,0.026,0.048,0.96)
		tower.anchor_left = float(i) / 20.0
		tower.anchor_right = float(i + 1) / 20.0
		tower.anchor_top = 1.0
		tower.anchor_bottom = 1.0
		tower.offset_left = 1
		tower.offset_right = -1
		tower.offset_top = -h
		tower.offset_bottom = 0
		skyline.add_child(tower)
		for w in range(2):
			var window := ColorRect.new()
			window.color = Color(0.95,0.56,0.25,0.55) if (i+w)%3==0 else Color(0.18,0.55,0.78,0.38)
			window.position = Vector2(8+w*18, -h+25+float((i*13+w*17)%65))
			window.size = Vector2(5,9)
			tower.add_child(window)
	var shade := ColorRect.new()
	shade.color = Color(0.005,0.012,0.025,0.42)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(shade)
	var center := CenterContainer.new()
	center.name = "LoadingCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(center)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(520,210)
	stack.add_theme_constant_override("separation",14)
	center.add_child(stack)
	var title := Label.new()
	title.text = "STICKMAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",56)
	title.add_theme_color_override("font_color",Color(0.88,0.95,1.0))
	stack.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "SHADOW WORLD  •  A LIVING CITY"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size",18)
	subtitle.add_theme_color_override("font_color",Color(0.38,0.82,1.0))
	stack.add_child(subtitle)
	loading_label = Label.new()
	loading_label.text = "INITIALIZING..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(loading_label)
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(380,12)
	loading_bar.show_percentage = false
	stack.add_child(loading_bar)


func _set_loading_progress(value: float, message: String) -> void:
	if loading_bar:
		loading_bar.value = value
	if loading_label:
		loading_label.text = message


func _show_main_menu() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var loading_center := menu_root.get_node_or_null("LoadingCenter")
	if loading_center:
		loading_center.queue_free()
	loading_label.visible = false
	loading_bar.visible = false
	var center := CenterContainer.new()
	center.name = "MainMenuCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.anchor_right = 0.53
	menu_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(390,420)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018,0.04,0.07,0.94)
	panel_style.border_color = Color(0.12,0.63,0.88,0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(18)
	panel_style.content_margin_left = 28
	panel_style.content_margin_right = 28
	panel_style.content_margin_top = 22
	panel_style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel",panel_style)
	center.add_child(panel)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation",12)
	panel.add_child(buttons)
	var heading := Label.new()
	heading.text = "YOUR CITY. YOUR STORY."
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size",20)
	buttons.add_child(heading)
	_add_menu_button(buttons,"▶   PLAY",_start_game)
	var continue_button := _add_menu_button(buttons,"↻   CONTINUE",_start_game)
	continue_button.disabled = not SaveSystem.has_save()
	_add_menu_button(buttons,"⚙   SETTINGS",_show_menu_settings)
	_add_menu_button(buttons,"EXIT",func(): get_tree().quit())
	var footer := Label.new()
	footer.text = "EXPLORE  •  WORK  •  DRIVE  •  BUILD"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size",11)
	footer.add_theme_color_override("font_color",Color(0.48,0.65,0.78))
	buttons.add_child(footer)
	_add_menu_button(buttons, "✦   SKIN STUDIO", _open_skin_studio)
	_create_skin_preview()


func _skin_palettes() -> Array:
	return [
		{"name":"SHADOW RUNNER","detail":"MIDNIGHT ARMOR  •  CYAN ENERGY","dark":Color(0.035,0.045,0.065),"accent":Color(0.0,0.78,1.0),"skin":Color(0.92,0.78,0.62)},
		{"name":"INFERNO","detail":"EMBER CORE  •  CRIMSON GLOW","dark":Color(0.12,0.035,0.025),"accent":Color(1.0,0.24,0.055),"skin":Color(0.78,0.57,0.42)},
		{"name":"TOXIC GHOST","detail":"DARK CAMO  •  NEON LIME","dark":Color(0.045,0.075,0.045),"accent":Color(0.48,0.95,0.23),"skin":Color(0.84,0.68,0.52)},
		{"name":"VOID REAPER","detail":"ABYSS SUIT  •  VIOLET PLASMA","dark":Color(0.035,0.025,0.075),"accent":Color(0.72,0.25,1.0),"skin":Color(0.72,0.63,0.57)},
		{"name":"FROST SENTINEL","detail":"GLACIER PLATE  •  ARCTIC BLUE","dark":Color(0.055,0.11,0.18),"accent":Color(0.32,0.86,1.0),"skin":Color(0.83,0.9,0.96)},
		{"name":"CRIMSON RONIN","detail":"SHOGUN ARMOR  •  SCARLET EDGE","dark":Color(0.16,0.025,0.045),"accent":Color(1.0,0.12,0.18),"skin":Color(0.9,0.69,0.55)},
		{"name":"SOLAR KNIGHT","detail":"ROYAL GOLD  •  SUNFIRE CORE","dark":Color(0.16,0.12,0.045),"accent":Color(1.0,0.72,0.18),"skin":Color(0.92,0.77,0.58)},
		{"name":"PHANTOM CIRCUIT","detail":"STEALTH WEAVE  •  MAGENTA PULSE","dark":Color(0.085,0.025,0.12),"accent":Color(1.0,0.14,0.62),"skin":Color(0.89,0.72,0.68)},
		{"name":"OCEAN WARDEN","detail":"DEEP-SEA ARMOR  •  TURQUOISE","dark":Color(0.02,0.10,0.11),"accent":Color(0.0,0.88,0.78),"skin":Color(0.72,0.82,0.75)},
		{"name":"OBSIDIAN TITAN","detail":"FORGED BLACK  •  AMBER REACTOR","dark":Color(0.08,0.065,0.04),"accent":Color(1.0,0.52,0.1),"skin":Color(0.72,0.60,0.48)}
	]

func _create_skin_preview() -> void:
	var card := PanelContainer.new()
	card.name = "SkinPreviewCard"
	card.anchor_left = 0.55
	card.anchor_top = 0.105
	card.anchor_right = 0.985
	card.anchor_bottom = 0.94
	card.offset_left = 0
	card.offset_top = 0
	card.offset_right = 0
	card.offset_bottom = 0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012,0.026,0.052,0.76)
	style.border_color = Color(0.08,0.68,0.94,0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	card.add_theme_stylebox_override("panel",style)
	menu_root.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",5)
	card.add_child(column)
	var title := Label.new()
	title.name = "SkinPreviewTitle"
	title.text = "3D CHARACTER PREVIEW"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",18)
	title.add_theme_color_override("font_color",Color(0.38,0.86,1.0))
	column.add_child(title)
	skin_preview_container = SubViewportContainer.new()
	skin_preview_container.name = "SkinPreview3D"
	skin_preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skin_preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_preview_container.custom_minimum_size = Vector2(420,440)
	skin_preview_container.stretch = true
	skin_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	skin_preview_container.gui_input.connect(_on_skin_preview_gui_input)
	column.add_child(skin_preview_container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600,620)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	skin_preview_container.add_child(viewport)
	var preview_world := World3D.new()
	viewport.world_3d = preview_world
	var camera := Camera3D.new()
	camera.position = Vector3(0,1.45,5.4)
	camera.fov = 38
	camera.look_at(Vector3(0,1.05,0),Vector3.UP)
	viewport.add_child(camera)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-32,-28,0)
	key_light.light_energy = 1.55
	key_light.shadow_enabled = true
	viewport.add_child(key_light)
	var rim_light := OmniLight3D.new()
	rim_light.position = Vector3(-2.1,2.2,-1.5)
	rim_light.light_color = Color(0.08,0.55,1.0)
	rim_light.light_energy = 2.0
	rim_light.omni_range = 7.0
	viewport.add_child(rim_light)
	var warm_light := OmniLight3D.new()
	warm_light.position = Vector3(2.0,1.7,1.4)
	warm_light.light_color = Color(1.0,0.28,0.08)
	warm_light.light_energy = 1.1
	warm_light.omni_range = 6.0
	viewport.add_child(warm_light)
	skin_preview_root = Node3D.new()
	skin_preview_root.name = "PreviewTurntable"
	viewport.add_child(skin_preview_root)
	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 0.88
	pedestal_mesh.bottom_radius = 1.02
	pedestal_mesh.height = 0.18
	pedestal.mesh = pedestal_mesh
	pedestal.position.y = 0.08
	var pedestal_mat := StandardMaterial3D.new()
	pedestal_mat.albedo_color = Color(0.025,0.065,0.11)
	pedestal_mat.metallic = 0.72
	pedestal_mat.roughness = 0.24
	pedestal.material_override = pedestal_mat
	skin_preview_root.add_child(pedestal)
	skin_preview_model = Node3D.new()
	skin_preview_model.position.y = 0.355
	skin_preview_root.add_child(skin_preview_model)
	_build_skin_preview_model()
	var hint := Label.new()
	hint.text = "DRAG TO ROTATE  •  FULL 3D VIEW"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size",11)
	hint.add_theme_color_override("font_color",Color(0.48,0.78,0.91))
	column.add_child(hint)
	_apply_skin_preview_palette()


func _build_skin_preview_model() -> void:
	var palette: Dictionary = _skin_palettes()[clampi(GameState.character_skin,0,9)]
	var dark_mat := _skin_material(palette.dark,0.34)
	var accent_mat := _skin_material(palette.accent,0.24)
	var skin_mat := _skin_material(palette.skin,0.48)

	var torso := _skin_mesh("PreviewTorso",CapsuleMesh.new(),Vector3(0,1.15,0),accent_mat)
	(torso.mesh as CapsuleMesh).radius = 0.22
	(torso.mesh as CapsuleMesh).height = 0.82
	skin_preview_model.add_child(torso)
	var head := _skin_mesh("PreviewHead",SphereMesh.new(),Vector3(0,1.82,0),skin_mat)
	(head.mesh as SphereMesh).radius = 0.28
	(head.mesh as SphereMesh).height = 0.56
	skin_preview_model.add_child(head)
	skin_preview_parts["Head"] = head
	skin_preview_parts["Torso"] = torso

	var visor := _skin_mesh("EnergyVisor",BoxMesh.new(),Vector3(0,1.88,-0.245),accent_mat)
	(visor.mesh as BoxMesh).size = Vector3(0.40,0.085,0.06)
	skin_preview_model.add_child(visor)
	skin_preview_parts["Visor"] = visor
	var chest_core := _skin_mesh("ChestReactor",CylinderMesh.new(),Vector3(0,1.20,-0.215),accent_mat)
	(chest_core.mesh as CylinderMesh).top_radius = 0.105
	(chest_core.mesh as CylinderMesh).bottom_radius = 0.105
	(chest_core.mesh as CylinderMesh).height = 0.055
	chest_core.rotation.x = PI * 0.5
	skin_preview_model.add_child(chest_core)
	skin_preview_parts["ChestCore"] = chest_core

	var hip := _skin_mesh("PreviewHip",CapsuleMesh.new(),Vector3(0,0.72,0),dark_mat)
	(hip.mesh as CapsuleMesh).radius = 0.19
	(hip.mesh as CapsuleMesh).height = 0.3
	skin_preview_model.add_child(hip)
	for side in [-1.0,1.0]:
		var shoulder := _skin_mesh("ShoulderArmor",SphereMesh.new(),Vector3(side*0.29,1.48,0),accent_mat)
		(shoulder.mesh as SphereMesh).radius = 0.19
		(shoulder.mesh as SphereMesh).height = 0.22
		shoulder.scale = Vector3(1.0,0.75,0.85)
		skin_preview_model.add_child(shoulder)
		skin_preview_parts["ShoulderArmor"] = shoulder

		var arm_pivot := Node3D.new()
		arm_pivot.position = Vector3(side*0.29,1.43,0)
		skin_preview_model.add_child(arm_pivot)
		var upper_arm := _skin_mesh("UpperArm",CapsuleMesh.new(),Vector3(0,-0.19,0),dark_mat)
		(upper_arm.mesh as CapsuleMesh).radius = 0.105
		(upper_arm.mesh as CapsuleMesh).height = 0.40
		arm_pivot.add_child(upper_arm)
		var elbow := Node3D.new()
		elbow.position.y = -0.37
		arm_pivot.add_child(elbow)
		var forearm := _skin_mesh("Forearm",CapsuleMesh.new(),Vector3(0,-0.16,0),dark_mat)
		(forearm.mesh as CapsuleMesh).radius = 0.09
		(forearm.mesh as CapsuleMesh).height = 0.34
		elbow.add_child(forearm)
		var glove := _skin_mesh("Glove",SphereMesh.new(),Vector3(0,-0.34,-0.015),accent_mat)
		(glove.mesh as SphereMesh).radius = 0.095
		(glove.mesh as SphereMesh).height = 0.15
		elbow.add_child(glove)
		skin_preview_arms.append(arm_pivot)
		skin_preview_arm_elbows.append(elbow)

		var leg_pivot := Node3D.new()
		leg_pivot.position = Vector3(side*0.12,0.66,0)
		skin_preview_model.add_child(leg_pivot)
		var upper_leg := _skin_mesh("UpperLeg",CapsuleMesh.new(),Vector3(0,-0.19,0),dark_mat)
		(upper_leg.mesh as CapsuleMesh).radius = 0.115
		(upper_leg.mesh as CapsuleMesh).height = 0.40
		leg_pivot.add_child(upper_leg)
		var knee := Node3D.new()
		knee.position.y = -0.38
		leg_pivot.add_child(knee)
		var knee_guard := _skin_mesh("KneeGuard",SphereMesh.new(),Vector3(0,0,-0.085),accent_mat)
		(knee_guard.mesh as SphereMesh).radius = 0.12
		(knee_guard.mesh as SphereMesh).height = 0.14
		knee.add_child(knee_guard)
		var lower_leg := _skin_mesh("LowerLeg",CapsuleMesh.new(),Vector3(0,-0.19,0),dark_mat)
		(lower_leg.mesh as CapsuleMesh).radius = 0.10
		(lower_leg.mesh as CapsuleMesh).height = 0.39
		knee.add_child(lower_leg)
		var boot := _skin_mesh("Boot",BoxMesh.new(),Vector3(0,-0.39,-0.10),accent_mat)
		(boot.mesh as BoxMesh).size = Vector3(0.25,0.15,0.38)
		knee.add_child(boot)
		skin_preview_legs.append(leg_pivot)
		skin_preview_leg_knees.append(knee)

	var shoulder_line := _skin_mesh("ChestArmorTrim",BoxMesh.new(),Vector3(0,1.48,-0.205),accent_mat)
	(shoulder_line.mesh as BoxMesh).size = Vector3(0.38,0.065,0.05)
	skin_preview_model.add_child(shoulder_line)
	var cape := _skin_mesh("PreviewCape",BoxMesh.new(),Vector3(0,1.12,0.19),dark_mat)
	(cape.mesh as BoxMesh).size = Vector3(0.72,1.02,0.075)
	cape.rotation.x = -0.12
	skin_preview_model.add_child(cape)
	skin_preview_parts["Cape"] = cape

func _skin_mesh(label: String, mesh: Mesh, position_value: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = position_value
	node.material_override = material
	return node


func _skin_material(color: Color, roughness_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness_value
	material.metallic = 0.42
	return material


func _apply_skin_preview_palette() -> void:
	if skin_preview_parts.is_empty():
		return
	var palette: Dictionary = _skin_palettes()[clampi(GameState.character_skin,0,9)]
	var preview_title := menu_root.find_child("SkinPreviewTitle",true,false) as Label
	if preview_title:
		preview_title.text = str(palette.name) + "  •  3D SKIN PREVIEW"
	for part_name in skin_preview_parts:
		var node: MeshInstance3D = skin_preview_parts[part_name]
		var tint: Color
		if part_name == "Head":
			tint = palette.skin
		elif part_name in ["Torso","Visor","ChestCore","ShoulderArmor"]:
			tint = palette.accent
		else:
			tint = palette.dark
		var material := _skin_material(tint,0.3)
		if part_name in ["Visor","ChestCore"]:
			material.emission_enabled = true
			material.emission = palette.accent
			material.emission_energy_multiplier = 0.9
		node.material_override = material


func _animate_skin_preview(delta: float) -> void:
	if skin_preview_model == null or not is_instance_valid(skin_preview_model):
		return
	skin_preview_time += delta
	var pulse := sin(skin_preview_time*2.8)
	skin_preview_model.position.y = 0.18 + sin(skin_preview_time*1.7)*0.045
	skin_preview_model.rotation.y += delta*0.13
	for i in range(skin_preview_arms.size()):
		var arm_phase := skin_preview_time*1.55 + (PI if i == 1 else 0.0)
		skin_preview_arms[i].rotation.x = sin(arm_phase)*0.075
		skin_preview_arms[i].rotation.z = (-0.035 if i == 0 else 0.035) + sin(arm_phase*0.5)*0.018
		if i < skin_preview_arm_elbows.size():
			skin_preview_arm_elbows[i].rotation.x = 0.12 + maxf(0.0,sin(arm_phase))*0.05
	for i in range(skin_preview_legs.size()):
		var leg_phase := skin_preview_time*1.55 + (PI if i == 1 else 0.0)
		skin_preview_legs[i].rotation.x = sin(leg_phase)*0.045
		if i < skin_preview_leg_knees.size():
			skin_preview_leg_knees[i].rotation.x = maxf(0.0,-cos(leg_phase))*0.07
	var palette: Dictionary = _skin_palettes()[clampi(GameState.character_skin,0,9)]
	if skin_preview_parts.has("Visor"):
		var visor: MeshInstance3D = skin_preview_parts["Visor"]
		var material := visor.material_override as StandardMaterial3D
		if material:
			material.emission_enabled = true
			material.emission = palette.accent
			material.emission_energy_multiplier = 0.7 + absf(pulse)*1.4
	if skin_preview_parts.has("ChestCore"):
		var reactor: MeshInstance3D = skin_preview_parts["ChestCore"]
		var reactor_material := reactor.material_override as StandardMaterial3D
		if reactor_material:
			reactor_material.emission_energy_multiplier = 0.65 + absf(pulse)*1.55

func _on_skin_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		skin_preview_root.rotation.y += event.relative.x*0.012
	elif event is InputEventMouseButton:
		skin_preview_dragging = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventMouseMotion and skin_preview_dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		skin_preview_root.rotation.y += event.relative.x*0.012


func _open_skin_studio() -> void:
	var old := menu_root.get_node_or_null("SkinStudioPanel")
	if old:
		old.queue_free()
	var menu_center := menu_root.get_node_or_null("MainMenuCenter")
	if menu_center:
		menu_center.visible = false
	var panel := PanelContainer.new()
	panel.name = "SkinStudioPanel"
	panel.anchor_left = 0.035
	panel.anchor_top = 0.13
	panel.anchor_right = 0.52
	panel.anchor_bottom = 0.88
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012,0.028,0.055,0.97)
	style.border_color = Color(0.1,0.72,0.98,0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel",style)
	menu_root.add_child(panel)
	skin_studio_panel = panel
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "✦  SHADOW SKIN LAB"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",25)
	title.add_theme_color_override("font_color",Color(0.3,0.85,1.0))
	column.add_child(title)
	var instruction := Label.new()
	instruction.text = "CHOOSE YOUR 3D IDENTITY"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size",13)
	column.add_child(instruction)
	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override("separation",10)
	column.add_child(skin_row)
	var previous := Button.new()
	previous.text = "◀"
	previous.custom_minimum_size = Vector2(54,58)
	previous.pressed.connect(func(): _change_preview_skin(-1))
	skin_row.add_child(previous)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_row.add_child(info)
	var skin_name := Label.new()
	skin_name.name = "SelectedSkinName"
	skin_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skin_name.add_theme_font_size_override("font_size",19)
	info.add_child(skin_name)
	skin_details_label = Label.new()
	skin_details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skin_details_label.add_theme_font_size_override("font_size",11)
	skin_details_label.add_theme_color_override("font_color",Color(0.55,0.73,0.85))
	info.add_child(skin_details_label)
	var next := Button.new()
	next.text = "▶"
	next.custom_minimum_size = Vector2(54,58)
	next.pressed.connect(func(): _change_preview_skin(1))
	skin_row.add_child(next)
	var name_title := Label.new()
	name_title.text = "CHARACTER NAME"
	column.add_child(name_title)
	skin_name_input = LineEdit.new()
	skin_name_input.placeholder_text = "Enter your character name"
	skin_name_input.text = GameState.character_name
	skin_name_input.max_length = 22
	column.add_child(skin_name_input)
	var animation_label := Label.new()
	animation_label.text = "SPECIAL ANIMATION  •  SHADOW SURGE"
	animation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	animation_label.add_theme_color_override("font_color",Color(0.1,0.85,1.0))
	column.add_child(animation_label)
	var animation_info := Label.new()
	animation_info.text = "A dramatic 3D idle loop with energy pulse, floating motion and moving armor."
	animation_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	animation_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	animation_info.add_theme_font_size_override("font_size",12)
	column.add_child(animation_info)
	var save := Button.new()
	save.text = "SAVE MY SKIN"
	save.custom_minimum_size.y = 48
	save.pressed.connect(func():
		GameState.character_name = skin_name_input.text.strip_edges()
		if GameState.character_name.is_empty():
			GameState.character_name = "SHADOW RUNNER"
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			players[0].apply_selected_skin()
		SaveSystem.save_game()
		_refresh_skin_name_display()
	)
	column.add_child(save)
	var back := Button.new()
	back.text = "BACK TO MAIN MENU"
	back.custom_minimum_size.y = 42
	back.pressed.connect(func():
		panel.queue_free()
		var main := menu_root.get_node_or_null("MainMenuCenter")
		if main:
			main.visible = true
	)
	column.add_child(back)
	_refresh_skin_name_display()


func _change_preview_skin(step: int) -> void:
	GameState.character_skin = posmod(GameState.character_skin + step, _skin_palettes().size())
	_apply_skin_preview_palette()
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		players[0].apply_selected_skin()
	_refresh_skin_name_display()


func _refresh_skin_name_display() -> void:
	if skin_studio_panel == null or not is_instance_valid(skin_studio_panel):
		return
	var name_label := skin_studio_panel.find_child("SelectedSkinName",true,false) as Label
	var palette: Dictionary = _skin_palettes()[clampi(GameState.character_skin,0,9)]
	if name_label:
		name_label.text = str(palette.name)
	if skin_details_label:
		skin_details_label.text = str(palette.detail)


func _add_menu_button(parent: Control, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(320,48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06,0.16,0.24,0.98)
	style.border_color = Color(0.12,0.55,0.76,0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	button.add_theme_stylebox_override("normal",style)
	button.add_theme_color_override("font_color",Color(0.9,0.97,1.0))
	button.add_theme_font_size_override("font_size",18)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _show_menu_settings() -> void:
	var old := menu_root.get_node_or_null("MenuSettings")
	if old:
		old.queue_free()
	var panel := PanelContainer.new()
	panel.name = "MenuSettings"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-175,155)
	panel.custom_minimum_size = Vector2(350,180)
	menu_root.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "GRAPHICS QUALITY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for option in [["PERFORMANCE",0],["BALANCED",1],["HIGH",2],["CINEMATIC",3]]:
		var button := Button.new()
		button.text = option[0]
		button.pressed.connect(func():
			var players := get_tree().get_nodes_in_group("player")
			if not players.is_empty():
				players[0]._apply_graphics_quality(int(option[1]))
			panel.queue_free()
		)
		column.add_child(button)
	var close := Button.new()
	close.text = "CLOSE"
	close.pressed.connect(func(): panel.queue_free())
	column.add_child(close)


func _start_game() -> void:
	get_tree().paused = false
	menu_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _create_traffic_system() -> void:
	_create_city_streets()
	for index in range(8):
		_create_traffic_car("x", 1, 0.0, index)
		var car_data: Dictionary = traffic_cars[traffic_cars.size() - 1]
		var angle := TAU * float(index) / 8.0
		car_data["axis"] = "circle"
		car_data["radius"] = 8.85
		car_data["angle"] = angle
		var car: Node3D = car_data["root"]
		car.position = Vector3(cos(angle) * 8.85, 0.0, sin(angle) * 8.85)
		car.look_at(car.position + Vector3(-sin(angle), 0.0, cos(angle)), Vector3.UP)


func _create_city_streets() -> void:
	var sidewalk := _mat(Color(0.43,0.43,0.41),0.96)
	var curb := _mat(Color(0.57,0.54,0.48),0.9)
	for index in range(-5,6):
		var offset := float(index)*16.0+8.0
		_add_road_surface(Vector3(offset,0.035,0),Vector3(5.2,0.07,220),asphalt_material,"StreetV_%d"%index)
		_add_road_surface(Vector3(0,0.035,offset),Vector3(220,0.07,5.2),asphalt_material,"StreetH_%d"%index)
		var side := 1.0 if index % 2 == 0 else -1.0
		_add_road_surface(Vector3(offset+side*3.25,0.055,0),Vector3(1.35,0.11,220),sidewalk,"WalkV_%d"%index)
		_add_road_surface(Vector3(0,0.055,offset+side*3.25),Vector3(220,0.11,1.35),sidewalk,"WalkH_%d"%index)
		_add_road_surface(Vector3(offset+side*2.58,0.075,0),Vector3(0.12,0.15,220),curb,"CurbV_%d"%index)
		_add_road_surface(Vector3(0,0.075,offset+side*2.58),Vector3(220,0.15,0.12),curb,"CurbH_%d"%index)


func _add_road_surface(pos: Vector3, dimensions: Vector3, material: Material, label: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = label
	var box := BoxMesh.new()
	box.size = dimensions
	mesh_instance.mesh = box
	mesh_instance.position = pos
	mesh_instance.material_override = material
	add_child(mesh_instance)
	if label == "ArterialSidewalkV" or label == "ArterialSidewalkH":
		var sidewalk_body := StaticBody3D.new()
		sidewalk_body.name = label + "Collision"
		sidewalk_body.position = pos
		add_child(sidewalk_body)
		var sidewalk_collision := CollisionShape3D.new()
		var sidewalk_shape := BoxShape3D.new()
		sidewalk_shape.size = dimensions
		sidewalk_collision.shape = sidewalk_shape
		sidewalk_body.add_child(sidewalk_collision)


func _glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.5
	material.roughness = 0.25
	return material


func _create_crosswalks() -> void:
	var paint := _mat(Color(0.88,0.89,0.86),0.78)
	for side in [-1.0,1.0]:
		for stripe_index in range(7):
			var offset := -4.2+float(stripe_index)*1.4
			_add_road_surface(Vector3(offset,0.105,side*7.0),Vector3(0.82,0.025,2.6),paint,"CrosswalkX_%d_%d"%[int(side),stripe_index])
			_add_road_surface(Vector3(side*7.0,0.105,offset),Vector3(2.6,0.025,0.82),paint,"CrosswalkZ_%d_%d"%[int(side),stripe_index])


func _create_traffic_lights() -> void:
	var red := _glow_material(Color(0.95,0.025,0.015))
	var yellow := _glow_material(Color(1.0,0.56,0.015))
	var green := _glow_material(Color(0.025,0.95,0.18))
	var housing := _mat(Color(0.025,0.035,0.045),0.4)
	var pole_mat := _mat(Color(0.12,0.14,0.16),0.5)
	var placements := [[Vector3(-9.2,0,-9.2),"x"],[Vector3(9.2,0,-9.2),"z"],[Vector3(9.2,0,9.2),"x"],[Vector3(-9.2,0,9.2),"z"]]
	for i in range(placements.size()):
		var item: Array = placements[i]
		var root := Node3D.new()
		root.name = "TrafficSignal_%d"%i
		root.position = item[0]
		add_child(root)
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.06
		pole_mesh.bottom_radius = 0.09
		pole_mesh.height = 4.8
		pole.mesh = pole_mesh
		pole.position.y = 2.4
		pole.material_override = pole_mat
		root.add_child(pole)
		var case := MeshInstance3D.new()
		var case_mesh := BoxMesh.new()
		case_mesh.size = Vector3(0.52,1.45,0.38)
		case.mesh = case_mesh
		case.position = Vector3(0,4.05,0)
		case.material_override = housing
		root.add_child(case)
		var bulbs: Array[MeshInstance3D] = []
		for bulb_index in range(3):
			var bulb := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.145
			sphere.height = 0.29
			bulb.mesh = sphere
			bulb.position = Vector3(0,4.55-float(bulb_index)*0.48,0.205)
			bulb.material_override = _dim_traffic_material(bulb_index)
			root.add_child(bulb)
			bulbs.append(bulb)
		traffic_lights.append({"axis":str(item[1]),"bulbs":bulbs,"materials":[red,yellow,green]})


func _dim_traffic_material(index: int) -> StandardMaterial3D:
	if traffic_dim_materials.is_empty():
		var colors := [Color(0.12,0.018,0.012),Color(0.12,0.065,0.008),Color(0.008,0.10,0.025)]
		for color in colors:
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 0.35
			traffic_dim_materials.append(material)
	return traffic_dim_materials[index]


func _create_traffic_car(axis: String, direction: int, start: float, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331+index*31+(1 if axis=="x" else 0)+direction*7
	var paints := [Color(0.72,0.12,0.09),Color(0.08,0.34,0.62),Color(0.72,0.69,0.59),Color(0.12,0.16,0.19),Color(0.63,0.48,0.22)]
	var paint := _mat(paints[rng.randi_range(0,paints.size()-1)],0.25)
	var glass := _mat(Color(0.025,0.085,0.12),0.16)
	var rubber := _mat(Color(0.018,0.02,0.023),0.95)
	var chrome := _mat(Color(0.48,0.53,0.57),0.24)
	var headlamp := _glow_material(Color(1.0,0.82,0.53))
	var taillamp := _glow_material(Color(0.92,0.035,0.025))
	var car := AnimatableBody3D.new()
	car.name = "TrafficCar_%s_%d_%d"%[axis,direction,index]
	car.sync_to_physics = true
	var lane := -float(direction)*2.1
	if axis=="x":
		car.position = Vector3(start,0,lane)
		car.rotation.y = -PI*0.5 if direction>0 else PI*0.5
	else:
		car.position = Vector3(lane,0,start)
		car.rotation.y = PI if direction>0 else 0.0
	add_child(car)
	_add_car_box(car,"Chassis",Vector3(1.9,0.4,3.55),Vector3(0,0.65,0),rubber)
	_add_car_box(car,"Body",Vector3(2.05,0.62,3.8),Vector3(0,0.92,0),paint)
	_add_car_box(car,"Hood",Vector3(1.92,0.18,1.02),Vector3(0,1.28,-1.32),paint)
	_add_car_box(car,"Cabin",Vector3(1.62,0.72,1.85),Vector3(0,1.49,0.05),glass)
	_add_car_box(car,"Roof",Vector3(1.52,0.12,1.65),Vector3(0,1.88,0.05),paint)
	var vehicle_collision := CollisionShape3D.new()
	var vehicle_shape := BoxShape3D.new()
	vehicle_shape.size = Vector3(2.1,1.55,3.9)
	vehicle_collision.shape = vehicle_shape
	vehicle_collision.position.y = 1.0
	car.add_child(vehicle_collision)
	for side in [-1.0,1.0]:
		for axle in [-1.0,1.0]:
			var wheel := MeshInstance3D.new()
			wheel.name = "Wheel"
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.37
			wheel_mesh.bottom_radius = 0.37
			wheel_mesh.height = 0.22
			wheel.mesh = wheel_mesh
			wheel.position = Vector3(side,0.48,axle*1.22)
			wheel.rotation.z = PI*0.5
			wheel.material_override = rubber
			car.add_child(wheel)
			var hub := MeshInstance3D.new()
			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius = 0.15
			hub_mesh.bottom_radius = 0.15
			hub_mesh.height = 0.23
			hub.mesh = hub_mesh
			hub.position = wheel.position
			hub.rotation.z = PI*0.5
			hub.material_override = chrome
			car.add_child(hub)
		_add_car_box(car,"Headlight",Vector3(0.42,0.16,0.06),Vector3(side*0.66,0.98,-1.94),headlamp)
		_add_car_box(car,"TailLight",Vector3(0.34,0.18,0.06),Vector3(side*0.69,0.98,1.94),taillamp)
	traffic_cars.append({"root":car,"axis":axis,"direction":direction,"position":start,"speed":rng.randf_range(5.0,7.0),"lane":lane})


func _add_car_box(parent: Node3D, label: String, dimensions: Vector3, pos: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = label
	var box := BoxMesh.new()
	box.size = dimensions
	mesh_instance.mesh = box
	mesh_instance.position = pos
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _update_traffic(delta: float) -> void:
	if traffic_cars.is_empty():
		return
	traffic_elapsed += delta
	var phase := fposmod(traffic_elapsed,24.0)
	var x_state := "GREEN" if phase<10.0 else ("YELLOW" if phase<12.0 else "RED")
	var z_state := "RED" if phase<10.0 else ("YELLOW" if phase<12.0 else ("GREEN" if phase<22.0 else "YELLOW"))
	if phase>=22.0:
		x_state = "RED"
	for signal_data in traffic_lights:
		var state := x_state if signal_data["axis"]=="x" else z_state
		for i in range(3):
			var active := (i==0 and state=="RED") or (i==1 and state=="YELLOW") or (i==2 and state=="GREEN")
			var bulbs: Array = signal_data["bulbs"]
			var materials: Array = signal_data["materials"]
			(bulbs[i] as MeshInstance3D).material_override = materials[i] if active else _dim_traffic_material(i)
	for car_data in traffic_cars:
		var direction := int(car_data["direction"])
		var car: Node3D = car_data["root"]
		if car_data["axis"] == "circle":
			var radius := float(car_data["radius"])
			var angle := float(car_data["angle"]) + float(car_data["speed"]) * delta / radius
			car_data["angle"] = fposmod(angle, TAU)
			car.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			car.look_at(car.position + Vector3(-sin(angle), 0.0, cos(angle)), Vector3.UP)
			for child in car.get_children():
				if child is MeshInstance3D and child.name == "Wheel":
					child.rotate_x(delta * 7.0)
			continue
		var position_value := float(car_data["position"])
		var state := x_state if car_data["axis"]=="x" else z_state
		var near_line := position_value>-12.0 and position_value< -7.5 if direction>0 else position_value<12.0 and position_value>7.5
		if near_line and state!="GREEN":
			position_value = -8.0 if direction>0 else 8.0
		else:
			position_value += float(direction)*float(car_data["speed"])*delta
		if direction>0 and position_value>108.0:
			position_value = -108.0
		elif direction<0 and position_value< -108.0:
			position_value = 108.0
		car_data["position"] = position_value
		if car_data["axis"]=="x":
			car.position = Vector3(position_value,0,float(car_data["lane"]))
		else:
			car.position = Vector3(float(car_data["lane"]),0,position_value)
		for child in car.get_children():
			if child is MeshInstance3D and child.name=="Wheel":
				child.rotate_x(delta*float(direction)*7.0)

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

func _create_roundabout() -> void:
	var plaza := StaticBody3D.new()
	plaza.name = "CentralRoundabout"
	add_child(plaza)
	var asphalt_disc := MeshInstance3D.new()
	asphalt_disc.name = "RoundaboutPavedApron"
	var disc := CylinderMesh.new()
	disc.top_radius = 11.7
	disc.bottom_radius = 11.7
	disc.height = 0.12
	disc.radial_segments = 96
	asphalt_disc.mesh = disc
	asphalt_disc.position.y = 0.055
	asphalt_disc.material_override = asphalt_material
	plaza.add_child(asphalt_disc)

	var ring := MeshInstance3D.new()
	ring.name = "CircularDrivingLane"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(96):
		var a0 := TAU * float(i) / 96.0
		var a1 := TAU * float(i + 1) / 96.0
		var i0 := Vector3(cos(a0) * 7.15, 0.135, sin(a0) * 7.15)
		var i1 := Vector3(cos(a1) * 7.15, 0.135, sin(a1) * 7.15)
		var o0 := Vector3(cos(a0) * 10.25, 0.135, sin(a0) * 10.25)
		var o1 := Vector3(cos(a1) * 10.25, 0.135, sin(a1) * 10.25)
		surface.add_vertex(i0)
		surface.add_vertex(o0)
		surface.add_vertex(i1)
		surface.add_vertex(i1)
		surface.add_vertex(o0)
		surface.add_vertex(o1)
	surface.generate_normals()
	ring.mesh = surface.commit()
	ring.material_override = _mat(Color(0.19, 0.21, 0.22), 0.88)
	plaza.add_child(ring)

	var island := MeshInstance3D.new()
	island.name = "LandscapedCenterIsland"
	var island_mesh := CylinderMesh.new()
	island_mesh.top_radius = 6.85
	island_mesh.bottom_radius = 6.85
	island_mesh.height = 0.34
	island_mesh.radial_segments = 96
	island.mesh = island_mesh
	island.position.y = 0.17
	island.material_override = stone_material
	plaza.add_child(island)
	var island_collision := CollisionShape3D.new()
	var island_shape := CylinderShape3D.new()
	island_shape.radius = 6.85
	island_shape.height = 0.36
	island_collision.shape = island_shape
	island_collision.position.y = 0.17
	plaza.add_child(island_collision)

	var lawn := MeshInstance3D.new()
	lawn.name = "RoundaboutGarden"
	var lawn_mesh := CylinderMesh.new()
	lawn_mesh.top_radius = 5.95
	lawn_mesh.bottom_radius = 5.95
	lawn_mesh.height = 0.10
	lawn_mesh.radial_segments = 96
	lawn.mesh = lawn_mesh
	lawn.position.y = 0.39
	lawn.material_override = _mat(Color(0.20, 0.38, 0.22), 0.98)
	plaza.add_child(lawn)

	var fountain_base := MeshInstance3D.new()
	var fountain_mesh := CylinderMesh.new()
	fountain_mesh.top_radius = 1.25
	fountain_mesh.bottom_radius = 1.42
	fountain_mesh.height = 0.42
	fountain_base.mesh = fountain_mesh
	fountain_base.position.y = 0.65
	fountain_base.material_override = _mat(Color(0.48, 0.52, 0.53), 0.48)
	plaza.add_child(fountain_base)
	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 1.05
	water_mesh.bottom_radius = 1.05
	water_mesh.height = 0.08
	water.mesh = water_mesh
	water.position.y = 0.90
	water.material_override = _glow_material(Color(0.035, 0.36, 0.52))
	plaza.add_child(water)
	var spire := MeshInstance3D.new()
	var spire_mesh := CylinderMesh.new()
	spire_mesh.top_radius = 0.12
	spire_mesh.bottom_radius = 0.27
	spire_mesh.height = 1.25
	spire.mesh = spire_mesh
	spire.position.y = 1.38
	spire.material_override = _mat(Color(0.68, 0.72, 0.72), 0.3)
	plaza.add_child(spire)


func _create_pedestrian_overpasses() -> void:
	var deck_mat := _mat(Color(0.22, 0.29, 0.34), 0.48)
	var rail_mat := _mat(Color(0.10, 0.17, 0.21), 0.38)
	var light_mat := _glow_material(Color(0.04, 0.58, 0.78))
	_create_overpass("NorthOverpass", Vector3(0, 0, -40), "z", deck_mat, rail_mat, light_mat)
	_create_overpass("EastOverpass", Vector3(40, 0, 0), "x", deck_mat, rail_mat, light_mat)


func _create_overpass(label: String, center: Vector3, axis: String, deck_mat: Material, rail_mat: Material, light_mat: Material) -> void:
	var bridge := Node3D.new()
	bridge.name = label
	bridge.position = center
	add_child(bridge)
	var deck_body := StaticBody3D.new()
	bridge.add_child(deck_body)
	var deck := MeshInstance3D.new()
	var deck_box := BoxMesh.new()
	deck_box.size = Vector3(19.0, 0.34, 2.8) if axis == "z" else Vector3(2.8, 0.34, 19.0)
	deck.mesh = deck_box
	deck.position.y = 4.45
	deck.material_override = deck_mat
	deck_body.add_child(deck)
	var deck_collision := CollisionShape3D.new()
	var deck_shape := BoxShape3D.new()
	deck_shape.size = deck_box.size
	deck_collision.shape = deck_shape
	deck_collision.position = deck.position
	deck_body.add_child(deck_collision)
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rail_box := BoxMesh.new()
		rail_box.size = Vector3(19.0, 0.16, 0.16) if axis == "z" else Vector3(0.16, 0.16, 19.0)
		rail.mesh = rail_box
		rail.position = Vector3(0, 5.25, side * 1.28) if axis == "z" else Vector3(side * 1.28, 5.25, 0)
		rail.material_override = rail_mat
		bridge.add_child(rail)
		var glow := MeshInstance3D.new()
		var glow_box := BoxMesh.new()
		glow_box.size = Vector3(18.6, 0.035, 0.035) if axis == "z" else Vector3(0.035, 0.035, 18.6)
		glow.mesh = glow_box
		glow.position = rail.position + Vector3(0, -0.35, 0)
		glow.material_override = light_mat
		bridge.add_child(glow)
	for side in [-1.0, 1.0]:
		_add_overpass_stairs(bridge, axis, side, deck_mat, rail_mat)


func _add_overpass_stairs(bridge: Node3D, axis: String, side: float, step_mat: Material, rail_mat: Material) -> void:
	var rise := 0.42
	var run := 0.68
	for i in range(10):
		var top := 4.45 - float(i + 1) * rise
		var body := StaticBody3D.new()
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.4, rise, run) if axis == "z" else Vector3(run, rise, 3.4)
		mesh.mesh = box
		body.position = Vector3(0, top - rise * 0.5, side * (1.7 + (float(i) + 0.5) * run)) if axis == "z" else Vector3(side * (1.7 + (float(i) + 0.5) * run), top - rise * 0.5, 0)
		mesh.material_override = step_mat
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		collision.shape = shape
		body.add_child(collision)
		bridge.add_child(body)
	for rail_side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.14, 0.14, 7.8) if axis == "z" else Vector3(7.8, 0.14, 0.14)
		rail.mesh = box
		rail.position = Vector3(rail_side * 1.78, 2.45, side * 5.05) if axis == "z" else Vector3(side * 5.05, 2.45, rail_side * 1.78)
		if axis == "z":
			rail.rotation.x = side * atan(4.2 / 6.8)
		else:
			rail.rotation.z = -side * atan(4.2 / 6.8)
		rail.material_override = rail_mat
		bridge.add_child(rail)


func _create_landmarks() -> void:
	_create_roundabout()
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

func _create_courthouse() -> void:
	var court := StaticBody3D.new()
	court.name = "CityCourthouse"
	court.position = Vector3(34.0, 0.0, -2.0)
	add_child(court)
	var stone := _mat(Color(0.67, 0.65, 0.59), 0.88)
	var dark_stone := _mat(Color(0.28, 0.31, 0.34), 0.72)
	var facade := MeshInstance3D.new()
	var facade_mesh := BoxMesh.new()
	facade_mesh.size = Vector3(18.0, 8.0, 3.0)
	facade.mesh = facade_mesh
	facade.position = Vector3(0, 4.0, 0)
	facade.material_override = stone
	court.add_child(facade)
	var facade_collision := CollisionShape3D.new()
	var facade_shape := BoxShape3D.new()
	facade_shape.size = facade_mesh.size
	facade_collision.shape = facade_shape
	facade_collision.position = facade.position
	court.add_child(facade_collision)
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(19.0, 0.55, 3.8)
	roof.mesh = roof_mesh
	roof.position = Vector3(0, 8.25, 0)
	roof.material_override = dark_stone
	court.add_child(roof)
	for x in [-7.0, -3.5, 3.5, 7.0]:
		var column := MeshInstance3D.new()
		var column_mesh := CylinderMesh.new()
		column_mesh.top_radius = 0.42
		column_mesh.bottom_radius = 0.52
		column_mesh.height = 6.8
		column.mesh = column_mesh
		column.position = Vector3(x, 3.45, 1.8)
		column.material_override = stone
		court.add_child(column)
	var sign := Label3D.new()
	sign.text = "CITY COURTHOUSE"
	sign.font_size = 64
	sign.pixel_size = 0.012
	sign.position = Vector3(0, 6.4, 1.62)
	sign.modulate = Color(0.08, 0.18, 0.25)
	court.add_child(sign)
	var entrance := StaticBody3D.new()
	entrance.name = "CourthouseReleasePoint"
	entrance.set_script(INTERACTABLE_SCRIPT)
	entrance.set("display_name", "Courthouse Entrance")
	entrance.set("description", "The courthouse is where the police bring you after an arrest.")
	entrance.set("interaction_type", "courthouse")
	entrance.position = Vector3(34.0, 0.9, 7.0)
	add_child(entrance)
	var marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(2.4, 0.08, 1.0)
	marker.mesh = marker_mesh
	marker.position.y = -0.82
	marker.material_override = _mat(Color(0.08, 0.55, 0.72), 0.35)
	entrance.add_child(marker)
	var entrance_collision := CollisionShape3D.new()
	var entrance_shape := BoxShape3D.new()
	entrance_shape.size = Vector3(2.8, 2.0, 2.0)
	entrance_collision.shape = entrance_shape
	entrance.add_child(entrance_collision)

func _create_city_services() -> void:
	_spawn_service("Mission Board", "Find your first city mission.", "mission", Vector3(3.5, 0.9, 3.5), Color(0.18, 0.55, 0.78))
	_spawn_service("Work Office", "Take a quick city job.", "job", Vector3(-3.5, 0.9, 3.5), Color(0.78, 0.55, 0.18))
	_spawn_service("Supply Shop", "Buy the animated travel cape for 120 coins, then equip or store it here.", "shop", Vector3(3.5, 0.9, -3.5), Color(0.24, 0.68, 0.42))
	_spawn_service("Small Townhouse", "Purchase your first property.", "property", Vector3(-3.5, 0.9, -3.5), Color(0.64, 0.34, 0.72))
	_create_card_terminal(Vector3(11.1, 0.0, -4.2))

func _create_card_terminal(pos: Vector3) -> void:
	var terminal := StaticBody3D.new()
	terminal.name = "CityCardReader"
	terminal.set_script(INTERACTABLE_SCRIPT)
	terminal.set("display_name", "Card Reader")
	terminal.set("description", "Transfer all your wallet cash to your bank card.")
	terminal.set("interaction_type", "card_terminal")
	terminal.position = pos
	add_child(terminal)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.76, 1.35, 0.48)
	body.mesh = body_mesh
	body.position.y = 0.68
	body.material_override = _mat(Color(0.045, 0.075, 0.095), 0.42)
	terminal.add_child(body)
	var screen := MeshInstance3D.new()
	var screen_mesh := BoxMesh.new()
	screen_mesh.size = Vector3(0.48, 0.34, 0.035)
	screen.mesh = screen_mesh
	screen.position = Vector3(0, 1.02, 0.255)
	screen.material_override = _glow_material(Color(0.05, 0.72, 0.95))
	terminal.add_child(screen)
	var slot := MeshInstance3D.new()
	var slot_mesh := BoxMesh.new()
	slot_mesh.size = Vector3(0.34, 0.045, 0.04)
	slot.mesh = slot_mesh
	slot.position = Vector3(0, 0.68, 0.26)
	slot.material_override = _mat(Color(0.01, 0.015, 0.02), 0.3)
	terminal.add_child(slot)
	var keypad := MeshInstance3D.new()
	var keypad_mesh := BoxMesh.new()
	keypad_mesh.size = Vector3(0.38, 0.22, 0.05)
	keypad.mesh = keypad_mesh
	keypad.position = Vector3(0, 0.38, 0.26)
	keypad.material_override = _mat(Color(0.16, 0.21, 0.25), 0.55)
	terminal.add_child(keypad)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.82, 1.45, 0.55)
	collision.shape = shape
	collision.position.y = 0.72
	terminal.add_child(collision)

func _create_supermarket() -> void:
	var center := Vector3(16.0, 0.0, -16.0)
	var store := Node3D.new()
	store.name = "Supermarket"
	store.position = center
	add_child(store)
	var wall_mat := _mat(Color(0.64, 0.67, 0.65), 0.88)
	var floor_mat := _mat(Color(0.34, 0.36, 0.35), 0.92)
	_add_market_wall(store, Vector3(0, 0.12, 0), Vector3(9.4, 0.24, 8.2), floor_mat, "MarketFloor")
	_add_market_wall(store, Vector3(0, 2.1, -4.0), Vector3(9.4, 4.2, 0.3), wall_mat, "MarketBackWall")
	_add_market_wall(store, Vector3(-4.55, 2.1, 0), Vector3(0.3, 4.2, 8.2), wall_mat, "MarketLeftWall")
	_add_market_wall(store, Vector3(4.55, 2.1, 0), Vector3(0.3, 4.2, 8.2), wall_mat, "MarketRightWall")
	_add_market_wall(store, Vector3(-3.45, 2.1, 4.0), Vector3(2.5, 4.2, 0.3), wall_mat, "MarketFrontLeft")
	_add_market_wall(store, Vector3(3.45, 2.1, 4.0), Vector3(2.5, 4.2, 0.3), wall_mat, "MarketFrontRight")
	_add_market_wall(store, Vector3(0, 3.85, 4.0), Vector3(4.6, 0.7, 0.3), wall_mat, "MarketFrontHeader")
	_add_market_wall(store, Vector3(0, 4.25, 0), Vector3(9.5, 0.2, 8.3), _mat(Color(0.12, 0.17, 0.19), 0.68), "MarketRoof")
	var sign_label := Label3D.new()
	sign_label.text = "SUPERMARKET"
	sign_label.position = Vector3(0, 3.65, 4.22)
	sign_label.font_size = 52
	sign_label.modulate = Color(0.18, 0.88, 0.95)
	sign_label.outline_size = 8
	store.add_child(sign_label)
	for shelf_z in [-2.6, -0.2]:
		for shelf_x in [-2.6, 0.0, 2.6]:
			_add_market_wall(store, Vector3(shelf_x, 0.9, shelf_z), Vector3(1.35, 1.8, 0.48), _mat(Color(0.36, 0.25, 0.16), 0.85), "MarketShelf")
			for level in range(3):
				var product_color: Color = [Color(0.18, 0.58, 0.34), Color(0.88, 0.58, 0.15), Color(0.22, 0.52, 0.82)][level]
				_add_market_wall(store, Vector3(shelf_x, 0.45 + float(level) * 0.48, shelf_z + 0.27), Vector3(1.1, 0.22, 0.14), _mat(product_color, 0.72), "ProductRow")
	_add_market_wall(store, Vector3(2.8, 0.72, 2.6), Vector3(2.8, 1.2, 0.8), _mat(Color(0.24, 0.27, 0.29), 0.55), "CheckoutCounter")
	_spawn_service("Supermarket Shift", "Work one store shift and earn $45 cash.", "market_job", Vector3(16.0, 0.9, -12.6), Color(0.17, 0.63, 0.46))
	_spawn_service("Store Shelf", "Take a snack pack from the shelf. This raises your wanted level.", "market_shelf", Vector3(13.1, 0.9, -16.0), Color(0.82, 0.42, 0.18))

func _add_market_wall(parent: Node3D, local_pos: Vector3, dimensions: Vector3, material: Material, node_name: String) -> void:
	var wall_body := StaticBody3D.new()
	wall_body.name = node_name
	wall_body.position = local_pos
	parent.add_child(wall_body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.material_override = material
	wall_body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	wall_body.add_child(collision)

func _create_police_officer() -> void:
	var officer := CharacterBody3D.new()
	officer.name = "CityPoliceOfficer"
	officer.set_script(load("res://scripts/police.gd"))
	officer.position = Vector3(-12.0, 0.1, -10.0)
	add_child(officer)

func _spawn_service(title: String, info: String, kind: String, pos: Vector3, tint: Color) -> void:
	var item := StaticBody3D.new()
	item.name = "ServiceKiosk_" + kind
	item.set_script(INTERACTABLE_SCRIPT)
	item.set("display_name", title)
	item.set("description", info)
	item.set("interaction_type", kind)
	item.position = pos
	add_child(item)
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.48
	base_mesh.bottom_radius = 0.56
	base_mesh.height = 0.20
	base.mesh = base_mesh
	base.position.y = -0.68
	base.material_override = _mat(Color(0.16, 0.20, 0.23), 0.48)
	item.add_child(base)
	var panel := MeshInstance3D.new()
	panel.name = "KioskBody"
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(0.82, 1.22, 0.18)
	panel.mesh = panel_mesh
	panel.position.y = 0.02
	panel.material_override = _mat(tint.lerp(Color(0.12, 0.16, 0.19), 0.62), 0.48)
	item.add_child(panel)
	var screen := MeshInstance3D.new()
	var screen_mesh := BoxMesh.new()
	screen_mesh.size = Vector3(0.60, 0.42, 0.035)
	screen.mesh = screen_mesh
	screen.position = Vector3(0, 0.20, -0.11)
	screen.material_override = _glow_material(tint.lerp(Color(0.28, 0.58, 0.72), 0.35))
	item.add_child(screen)
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(0.62, 0.055, 0.04)
	strip.mesh = strip_mesh
	strip.position = Vector3(0, -0.30, -0.12)
	strip.material_override = _mat(tint.lerp(Color(0.22, 0.26, 0.28), 0.48), 0.38)
	item.add_child(strip)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.92, 1.62, 0.70)
	collision.shape = shape
	collision.position.y = -0.02
	item.add_child(collision)

func _create_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.14, 10)
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
	_create_storage_chest(room_center)
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

func _create_storage_chest(room_center: Vector3) -> void:
	var chest := StaticBody3D.new()
	chest.name = "HomeStorageChest"
	chest.set_script(INTERACTABLE_SCRIPT)
	chest.set("display_name", "Storage Chest")
	chest.set("description", "Open your stored items.")
	chest.set("interaction_type", "storage_chest")
	chest.position = room_center + Vector3(-4.2, 0.43, -3.6)
	add_child(chest)
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.35, 0.82, 0.9)
	base.mesh = base_mesh
	base.material_override = _mat(Color(0.35, 0.19, 0.075), 0.78)
	chest.add_child(base)
	var lid := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.4, 0.2, 0.95)
	lid.mesh = lid_mesh
	lid.position.y = 0.5
	lid.material_override = _mat(Color(0.48, 0.27, 0.11), 0.68)
	chest.add_child(lid)
	var latch := MeshInstance3D.new()
	var latch_mesh := BoxMesh.new()
	latch_mesh.size = Vector3(0.16, 0.28, 0.08)
	latch.mesh = latch_mesh
	latch.position = Vector3(0, 0.18, -0.49)
	latch.material_override = _mat(Color(0.82, 0.65, 0.25), 0.35)
	chest.add_child(latch)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.45, 1.1, 1.0)
	collision.shape = shape
	collision.position.y = 0.05
	chest.add_child(collision)


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
		["Mira the Merchant", "The supply shop has useful items for long journeys.", Vector3(8.25, 0.1, 5.5)],
		["Old Rowan", "The clock tower is the oldest landmark in this district.", Vector3(-8.25, 0.1, 5.0)],
		["Kai the Courier", "The town office always has small jobs available.", Vector3(8.25, 0.1, -10.0)],
		["Lena the Builder", "Some houses are for sale. Save your coins!", Vector3(-8.25, 0.1, -9.5)],
		["Noah the Explorer", "Try jumping near low obstacles to vault across them.", Vector3(14.0, 0.1, 8.25)],
		["Ari the Guide", "Explore the plaza, then visit the townhouse entrance.", Vector3(-14.0, 0.1, -8.25)],
		["Milo the Student", "The crosswalk lights change automatically. Wait for green.", Vector3(8.25, 0.1, 13.0)],
		["Nora the Photographer", "The old district looks beautiful at sunset.", Vector3(-8.25, 0.1, -14.0)],
		["Evan the Musician", "You can explore the side streets beyond the plaza.", Vector3(27.25, 0.1, 8.0)],
		["Sana the Gardener", "The small parks are tucked between the city blocks.", Vector3(-27.25, 0.1, -8.0)]
	]
	for resident_index in range(residents.size()):
		var resident: Array = residents[resident_index]
		var npc := CharacterBody3D.new()
		npc.set_script(load("res://scripts/npc.gd"))
		npc.set("display_name", resident[0])
		npc.set("dialogue", resident[1])
		npc.set("wander_radius", 105.0)
		npc.set("move_speed", 1.42 + float(resident_index % 4) * 0.13)
		npc.set("schedule_offset", float(resident_index) * 0.087)
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
		var beak_mesh := CylinderMesh.new()
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
