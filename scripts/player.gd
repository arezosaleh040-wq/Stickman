extends CharacterBody3D

@export var walk_speed := 6.2
@export var sprint_speed := 10.0
@export var jump_velocity := 6.6
@export var mouse_sensitivity := 0.0022
@export var acceleration := 34.0
@export var braking := 15.0
@export var crouch_speed := 2.8
var touch_root: Control
var touch_buttons: Dictionary = {}
var touch_button_positions: Dictionary = {}
var touch_edit_mode := false
var touch_edit_hint: Label
var touch_edit_done: Button

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var body_mesh: MeshInstance3D = $Body

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var first_person := false
var sensitivity_multiplier := 1.0
var invert_look_y := false
var camera_fov := 75.0
var camera_distance := 4.2
var touch_button_scale := 1.0
var graphics_quality := 1
var touch_layout_left := true
var pause_overlay: ColorRect
var settings_panel: PanelContainer
var pause_card: PanelContainer
var settings_config := ConfigFile.new()
var stamina := 100.0
var visual_root: Node3D
var limbs: Array[Node3D] = []
var walk_phase := 0.0
var body_torso: Node3D
var body_hip: Node3D
var body_head: Node3D
var cape_pivot: Node3D
var cape_mesh: MeshInstance3D
var cape_material: ShaderMaterial
var cape_phase := 0.0
var was_on_floor := true
var landing_bounce := 0.0
var locomotion_blend := 0.0
var hud_label: Label
var prompt_label: Label
var message_label: Label
var message_timer := 0.0
var parkour_cooldown := 0.0
var is_vaulting := false
var footstep_clock := 0.0
var inventory_panel: PanelContainer
var hotbar_buttons: Array[Button] = []
var inventory_hotbar_buttons: Array[Button] = []
var storage_buttons: Array[Button] = []

func _ready() -> void:
	floor_snap_length = 0.38
	safe_margin = 0.035
	max_slides = 8
	add_to_group("player")
	_add_input_actions()
	_build_character()
	_build_touch_controls()
	_build_hud()
	_build_pause_and_settings()
	_load_player_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if SaveSystem.has_save():
		SaveSystem.load_game()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_V:
			_toggle_camera()
		elif event.keycode == KEY_E:
			_interact_nearest()
		elif event.keycode == KEY_I:
			_toggle_inventory()
		elif event.keycode == KEY_F5:
			SaveSystem.save_game()
		elif event.keycode == KEY_F9:
			SaveSystem.load_game()
		elif event.keycode == KEY_ESCAPE:
			_toggle_pause_menu()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative)
	if event is InputEventScreenDrag and event.position.x > get_viewport().get_visible_rect().size.x * 0.42:
		_rotate_camera(event.relative)

func _rotate_camera(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity * sensitivity_multiplier)
	var vertical_sign := 1.0 if invert_look_y else -1.0
	camera_pivot.rotate_x(relative.y * mouse_sensitivity * sensitivity_multiplier * vertical_sign)
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.25, 1.25)

func _physics_process(delta: float) -> void:
	parkour_cooldown = maxf(0.0, parkour_cooldown - delta)
	was_on_floor = is_on_floor()
	if not was_on_floor:
		velocity.y -= gravity * delta
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.16)
	var direction := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var crouching := Input.is_action_pressed("crouch")
	var wants_sprint := Input.is_action_pressed("sprint") and not crouching and stamina > 1.0 and input_vector.length() > 0.1
	var target_speed := crouch_speed if crouching else (sprint_speed if wants_sprint else walk_speed)
	stamina = maxf(0.0, stamina - 22.0 * delta) if wants_sprint else minf(100.0, stamina + 13.0 * delta)
	if direction.length() > 0.01:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, braking * delta)
		velocity.z = move_toward(velocity.z, 0.0, braking * delta)
	camera_pivot.position.y = 1.12 if crouching else 1.55
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_velocity
			AudioManager.play_jump()
		else:
			_try_parkour_jump(direction)
	move_and_slide()
	if not was_on_floor and is_on_floor():
		landing_bounce = 0.18
	_animate_character(delta, input_vector.length() > 0.1)
	if is_on_floor() and input_vector.length() > 0.1:
		footstep_clock += delta
		var step_interval := 0.34 if wants_sprint else 0.52
		if footstep_clock >= step_interval:
			AudioManager.play_footstep()
			footstep_clock = 0.0
	else:
		footstep_clock = 0.0
	_sync_cape_equipment()
	_update_interaction_prompt()
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			message_label.text = ""
	if hud_label:
		var wanted_text := "  •  WANTED %d★" % GameState.wanted_level if GameState.wanted_level > 0 else ""
		hud_label.text = "COINS %d  •  CASH $%d  •  BANK $%d  •  XP %d  •  STA %d%%%s" % [GameState.money, GameState.cash_wallet, GameState.bank_balance, GameState.experience, int(stamina), wanted_text]
	_refresh_inventory_ui()

func _try_parkour_jump(direction: Vector3) -> void:
	if parkour_cooldown > 0.0 or stamina < 12.0:
		return
	var space := get_world_3d().direct_space_state
	var forward := -global_transform.basis.z
	var wall_query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.95, global_position + Vector3.UP * 0.95 + forward * 1.15)
	wall_query.exclude = [self]
	var wall_hit := space.intersect_ray(wall_query)
	if wall_hit.is_empty():
		return
	var top_query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 2.0 + forward * 0.85, global_position + Vector3.UP * 0.35 + forward * 0.85)
	top_query.exclude = [self]
	var top_hit := space.intersect_ray(top_query)
	if not top_hit.is_empty():
		# A wall jump pushes the character away from the obstacle.
		velocity.y = 6.4
		velocity += wall_hit.normal * 3.0
		_show_message("WALL JUMP")
	else:
		# A clear ledge lets the character vault over low obstacles.
		velocity.y = 5.2
		velocity += forward * 3.2
		_show_message("PARKOUR VAULT")
	stamina = maxf(0.0, stamina - 12.0)
	parkour_cooldown = 0.55

func _animate_character(delta: float, moving: bool) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var sprinting := Input.is_action_pressed("sprint") and moving and stamina > 0.0
	var target_blend := clampf(horizontal_speed / maxf(sprint_speed, 0.1), 0.0, 1.0)
	locomotion_blend = move_toward(locomotion_blend, target_blend, delta * 5.5)
	if moving:
		walk_phase += delta * (15.0 if sprinting else 9.0) * lerpf(0.45, 1.0, locomotion_blend)
	else:
		walk_phase = move_toward(walk_phase, 0.0, delta * 6.0)
	var airborne := not is_on_floor()
	var run_amount := 1.0 if sprinting else 0.0
	for i in range(limbs.size()):
		var phase_offset := PI if i == 1 or i == 3 else 0.0
		var stride := sin(walk_phase + phase_offset)
		var amount := stride * lerpf(0.42, 0.78, run_amount) * locomotion_blend
		if i < 2:
			amount = -amount * 0.82
			limbs[i].rotation.z = lerpf(limbs[i].rotation.z, (-0.12 if i == 0 else 0.12) * locomotion_blend, delta * 7.0)
		else:
			limbs[i].rotation.z = lerpf(limbs[i].rotation.z, 0.0, delta * 8.0)
		if airborne:
			amount = -0.38 if i >= 2 else 0.32
		limbs[i].rotation.x = lerpf(limbs[i].rotation.x, amount, delta * (10.0 if airborne else 13.0))
	landing_bounce = move_toward(landing_bounce, 0.0, delta * 1.8)
	if body_torso:
		var lean := -0.10 * locomotion_blend if sprinting else -0.035 * locomotion_blend
		body_torso.rotation.x = lerpf(body_torso.rotation.x, lean + (0.12 if airborne else 0.0), delta * 7.0)
		body_torso.position.y = lerpf(body_torso.position.y, 1.12 + (sin(walk_phase * 2.0) * 0.035 * locomotion_blend if not airborne else -landing_bounce), delta * 10.0)
	if body_hip:
		body_hip.rotation.x = lerpf(body_hip.rotation.x, 0.08 if airborne else 0.0, delta * 8.0)
	if body_head:
		body_head.rotation.x = lerpf(body_head.rotation.x, -0.025 * locomotion_blend, delta * 5.0)
	_update_cape_motion(delta, horizontal_speed, sprinting, airborne)


func _assist_stair_step(direction: Vector3) -> void:
	var horizontal_motion := direction.normalized() * 0.25
	if not test_move(global_transform, horizontal_motion):
		return
	var raised_transform := global_transform
	raised_transform.origin.y += 0.16
	if not test_move(raised_transform, horizontal_motion):
		global_position.y += 0.16


func _build_cape() -> void:
	cape_pivot = Node3D.new()
	cape_pivot.name = "ClothCapePivot"
	cape_pivot.position = Vector3(0, 1.43, 0.14)
	visual_root.add_child(cape_pivot)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := 10
	var rows := 14
	for row in range(rows + 1):
		for column in range(columns + 1):
			var u := float(column) / float(columns)
			var v := float(row) / float(rows)
			surface.set_uv(Vector2(u, v))
			var width := lerpf(0.38, 0.48, v)
			surface.add_vertex(Vector3((u - 0.5) * width * 2.0, 0.16 - v * 1.08, 0.0))
	for row in range(rows):
		for column in range(columns):
			var a := row * (columns + 1) + column
			var b := a + 1
			var c := a + columns + 1
			var d := c + 1
			surface.add_index(a)
			surface.add_index(c)
			surface.add_index(b)
			surface.add_index(b)
			surface.add_index(c)
			surface.add_index(d)
	surface.generate_normals()
	cape_mesh = MeshInstance3D.new()
	cape_mesh.name = "AnimatedFabric"
	cape_mesh.mesh = surface.commit()
	cape_material = ShaderMaterial.new()
	var cape_shader := Shader.new()
	cape_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 cape_color : source_color = vec4(0.035, 0.105, 0.19, 1.0);
uniform float motion_amount = 0.0;
uniform float wind_amount = 0.35;
uniform float phase = 0.0;
void vertex() {
	float edge_weight = pow(UV.y, 1.55);
	float wave = sin(TIME * 4.8 + UV.y * 10.0 + UV.x * 3.6 + phase);
	float cross_wave = cos(TIME * 3.1 + UV.y * 7.0 + phase * 1.7);
	VERTEX.z += edge_weight * (0.035 + motion_amount * 0.16 + wind_amount * 0.045) * wave;
	VERTEX.x += edge_weight * (0.025 + motion_amount * 0.055) * cross_wave;
	VERTEX.y -= edge_weight * (0.018 + motion_amount * 0.025) * abs(wave);
}
void fragment() {
	float fabric_shade = 0.91 + 0.09 * sin(UV.y * 18.0 + UV.x * 8.0);
	ALBEDO = cape_color.rgb * fabric_shade;
	ROUGHNESS = 0.78;
	METALLIC = 0.04;
}
"""
	cape_material.shader = cape_shader
	cape_material.set_shader_parameter("cape_color", Color(0.035, 0.105, 0.19, 1.0))
	cape_material.set_shader_parameter("phase", 0.73)
	cape_mesh.material_override = cape_material
	cape_pivot.add_child(cape_mesh)
	var collar := MeshInstance3D.new()
	collar.name = "CapeCollar"
	var collar_mesh := BoxMesh.new()
	collar_mesh.size = Vector3(0.55, 0.105, 0.13)
	collar.mesh = collar_mesh
	collar.position = Vector3(0, 0.115, -0.012)
	collar.material_override = _material(Color(0.12, 0.17, 0.21), 0.54)
	cape_pivot.add_child(collar)
	cape_pivot.visible = false


func _sync_cape_equipment() -> void:
	if cape_pivot == null:
		return
	var inventory: Dictionary = GameState.inventory
	var should_show := bool(inventory.get("cape_owned", false)) and bool(inventory.get("cape_equipped", false))
	if cape_pivot.visible != should_show:
		cape_pivot.visible = should_show


func _update_cape_motion(delta: float, horizontal_speed: float, sprinting: bool, airborne: bool) -> void:
	if cape_material == null:
		return
	var speed_ratio := clampf(horizontal_speed / maxf(sprint_speed, 0.1), 0.0, 1.0)
	var target_motion := speed_ratio * (1.3 if sprinting else 0.72) + (0.38 if airborne else 0.0)
	cape_phase += delta * (1.1 + speed_ratio * 2.4)
	cape_material.set_shader_parameter("motion_amount", lerpf(float(cape_material.get_shader_parameter("motion_amount")), target_motion, delta * 4.5))
	cape_material.set_shader_parameter("wind_amount", 0.28 + 0.12 * sin(Time.get_ticks_msec() * 0.0007))
	cape_material.set_shader_parameter("phase", cape_phase)


func _build_character() -> void:
	body_mesh.visible = false
	visual_root = Node3D.new()
	visual_root.name = "StickmanVisual"
	add_child(visual_root)
	var dark := _material(Color(0.045, 0.055, 0.075), 0.38)
	var accent := _material(Color(0.05, 0.72, 0.95), 0.3)
	var skin := _material(Color(0.92, 0.78, 0.62), 0.55)
	body_head = _add_sphere("Head", Vector3(0, 1.66, 0), Vector3(0.27, 0.27, 0.27), skin)
	body_torso = _add_capsule("Torso", Vector3(0, 1.12, 0), 0.16, 0.72, accent)
	body_hip = _add_capsule("Hip", Vector3(0, 0.72, 0), 0.17, 0.22, dark)
	_add_limb("LeftArm", Vector3(-0.19, 1.39, 0), 0.075, 0.58, dark)
	_add_limb("RightArm", Vector3(0.19, 1.39, 0), 0.075, 0.58, dark)
	_add_limb("LeftLeg", Vector3(-0.1, 0.48, 0), 0.09, 0.7, dark)
	_add_limb("RightLeg", Vector3(0.1, 0.48, 0), 0.09, 0.7, dark)
	_build_cape()

func _material(color: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat

func _add_sphere(label: String, pos: Vector3, scale_value: Vector3, mat: Material) -> Node3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	node.mesh = mesh
	node.position = pos
	node.scale = scale_value
	node.material_override = mat
	visual_root.add_child(node)
	return node

func _add_capsule(label: String, pos: Vector3, radius: float, height: float, mat: Material) -> Node3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	visual_root.add_child(node)
	return node

func _add_limb(label: String, pos: Vector3, radius: float, length: float, mat: Material) -> void:
	var pivot := Node3D.new()
	pivot.name = label + "Pivot"
	pivot.position = pos
	visual_root.add_child(pivot)
	var limb_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius * 0.82
	cylinder.height = length
	limb_mesh.mesh = cylinder
	limb_mesh.position.y = -length * 0.38
	limb_mesh.material_override = mat
	pivot.add_child(limb_mesh)
	if label.ends_with("Leg"):
		var shoe := MeshInstance3D.new()
		shoe.name = label + "Shoe"
		var shoe_mesh := BoxMesh.new()
		shoe_mesh.size = Vector3(0.20, 0.13, 0.34)
		shoe.mesh = shoe_mesh
		shoe.position = Vector3(0, -length * 0.69, -0.075)
		shoe.material_override = _material(Color(0.05, 0.72, 0.95), 0.38)
		pivot.add_child(shoe)
	limbs.append(pivot)

func _add_box(label: String, pos: Vector3, size_value: Vector3, mat: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size_value
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	visual_root.add_child(node)

func _toggle_camera() -> void:
	first_person = not first_person
	var target_position := Vector3(0, 0.03, 0.02) if first_person else Vector3(0, 0.55, camera_distance)
	camera.position = target_position
	camera.fov = camera_fov
	visual_root.visible = not first_person
	camera_pivot.position.y = 1.55 if first_person else 1.55

func _interact_nearest() -> void:
	var nearest: Node3D
	var best_distance := 3.4
	for item in get_tree().get_nodes_in_group("interactables"):
		if item is Node3D:
			var distance := global_position.distance_to(item.global_position)
			if distance < best_distance:
				best_distance = distance
				nearest = item
	if nearest and nearest.has_method("interact"):
		var interaction_type := str(nearest.get("interaction_type"))
		var was_mission_active := GameState.active_mission == "The First Errand" and not GameState.mission_completed
		_show_message(nearest.interact())
		if interaction_type == "storage_chest":
			inventory_panel.visible = true
			AudioManager.play_card_beep()
		if was_mission_active and interaction_type == "mission":
			GameState.complete_mission(120, 35)
			_show_message("Mission complete! +120 coins • +35 XP")
		_refresh_inventory_ui()

func _update_interaction_prompt() -> void:
	var found := false
	for item in get_tree().get_nodes_in_group("interactables"):
		if item is Node3D and global_position.distance_to(item.global_position) < 3.4:
			prompt_label.text = "E / INTERACT  •  " + str(item.get("display_name"))
			found = true
			break
	if not found:
		prompt_label.text = "F5 SAVE  •  F9 LOAD" if not SaveSystem.has_save() else ""

func _show_message(value: String) -> void:
	message_label.text = value
	message_timer = 4.0

func _add_input_actions() -> void:
	var keys := {"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"move_forward":[KEY_W,KEY_UP],"move_back":[KEY_S,KEY_DOWN],"jump":[KEY_SPACE],"sprint":[KEY_SHIFT],"crouch":[KEY_CTRL,KEY_C]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in keys[action]:
			var event := InputEventKey.new()
			event.keycode = keycode
			InputMap.action_add_event(action, event)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GameHUD"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.02
	panel.anchor_top = 0.025
	panel.anchor_right = 0.78
	panel.anchor_bottom = 0.105
	layer.add_child(panel)
	hud_label = Label.new()
	hud_label.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	hud_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(hud_label)
	prompt_label = Label.new()
	prompt_label.anchor_left = 0.28
	prompt_label.anchor_top = 0.78
	prompt_label.anchor_right = 0.72
	prompt_label.anchor_bottom = 0.84
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.48))
	layer.add_child(prompt_label)
	message_label = Label.new()
	message_label.anchor_left = 0.15
	message_label.anchor_top = 0.14
	message_label.anchor_right = 0.85
	message_label.anchor_bottom = 0.23
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.78))
	layer.add_child(message_label)
	_build_inventory_ui(layer)

func _build_inventory_ui(layer: CanvasLayer) -> void:
	var hotbar_panel := PanelContainer.new()
	hotbar_panel.name = "MinecraftHotbar"
	hotbar_panel.anchor_left = 0.5
	hotbar_panel.anchor_right = 0.5
	hotbar_panel.anchor_top = 0.855
	hotbar_panel.anchor_bottom = 0.985
	hotbar_panel.offset_left = -315
	hotbar_panel.offset_right = 315
	hotbar_panel.offset_top = 0
	hotbar_panel.offset_bottom = 0
	layer.add_child(hotbar_panel)
	var hotbar_row := HBoxContainer.new()
	hotbar_row.add_theme_constant_override("separation", 4)
	hotbar_panel.add_child(hotbar_row)
	for slot_index in range(9):
		var slot_button := Button.new()
		slot_button.custom_minimum_size = Vector2(65, 52)
		slot_button.focus_mode = Control.FOCUS_NONE
		slot_button.add_theme_font_size_override("font_size", 11)
		slot_button.pressed.connect(_select_hotbar_slot.bind(slot_index))
		hotbar_row.add_child(slot_button)
		hotbar_buttons.append(slot_button)
	inventory_panel = PanelContainer.new()
	inventory_panel.name = "InventoryAndChest"
	inventory_panel.set_anchors_preset(Control.PRESET_CENTER)
	inventory_panel.position = Vector2(-335, -245)
	inventory_panel.custom_minimum_size = Vector2(670, 490)
	inventory_panel.visible = false
	inventory_panel.z_index = 20
	layer.add_child(inventory_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	inventory_panel.add_child(root)
	var heading_row := HBoxContainer.new()
	root.add_child(heading_row)
	var heading := Label.new()
	heading.text = "PLAYER INVENTORY  •  BANK CARD"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 19)
	heading_row.add_child(heading)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.pressed.connect(_toggle_inventory)
	heading_row.add_child(close_button)
	var wallet_label := Label.new()
	wallet_label.name = "WalletSummary"
	root.add_child(wallet_label)
	var hotbar_title := Label.new()
	hotbar_title.text = "HOTBAR  •  9 QUICK SLOTS"
	root.add_child(hotbar_title)
	var hotbar_grid := GridContainer.new()
	hotbar_grid.columns = 9
	hotbar_grid.add_theme_constant_override("h_separation", 5)
	root.add_child(hotbar_grid)
	for slot_index in range(9):
		var slot_button := Button.new()
		slot_button.custom_minimum_size = Vector2(62, 50)
		slot_button.add_theme_font_size_override("font_size", 10)
		slot_button.pressed.connect(_select_hotbar_slot.bind(slot_index))
		hotbar_grid.add_child(slot_button)
		inventory_hotbar_buttons.append(slot_button)
	var storage_title := Label.new()
	storage_title.text = "BACKPACK / CHEST STORAGE  •  18 SLOTS"
	root.add_child(storage_title)
	var storage_grid := GridContainer.new()
	storage_grid.columns = 9
	storage_grid.add_theme_constant_override("h_separation", 5)
	storage_grid.add_theme_constant_override("v_separation", 5)
	root.add_child(storage_grid)
	for slot_index in range(18):
		var slot_button := Button.new()
		slot_button.custom_minimum_size = Vector2(62, 48)
		slot_button.add_theme_font_size_override("font_size", 10)
		slot_button.pressed.connect(_swap_storage_slot.bind(slot_index))
		storage_grid.add_child(slot_button)
		storage_buttons.append(slot_button)
	_refresh_inventory_ui()

func _toggle_inventory() -> void:
	if inventory_panel == null:
		return
	inventory_panel.visible = not inventory_panel.visible
	_refresh_inventory_ui()

func _select_hotbar_slot(slot_index: int) -> void:
	GameState.selected_hotbar = clampi(slot_index, 0, 8)
	_refresh_inventory_ui()

func _swap_storage_slot(slot_index: int) -> void:
	var selected := GameState.selected_hotbar
	var item = GameState.hotbar_slots[selected]
	GameState.hotbar_slots[selected] = GameState.backpack_slots[slot_index]
	GameState.backpack_slots[slot_index] = item
	_refresh_inventory_ui()

func _refresh_inventory_ui() -> void:
	for slot_index in range(mini(hotbar_buttons.size(), GameState.hotbar_slots.size())):
		var item_text := str(GameState.hotbar_slots[slot_index])
		hotbar_buttons[slot_index].text = "%d\n%s" % [slot_index + 1, item_text if not item_text.is_empty() else "—"]
		hotbar_buttons[slot_index].modulate = Color(0.35, 0.86, 1.0, 1.0) if slot_index == GameState.selected_hotbar else Color(0.83, 0.9, 0.96, 0.88)
	if inventory_panel and inventory_panel.visible:
		for slot_index in range(mini(inventory_hotbar_buttons.size(), GameState.hotbar_slots.size())):
			var hotbar_item := str(GameState.hotbar_slots[slot_index])
			inventory_hotbar_buttons[slot_index].text = "%d\n%s" % [slot_index + 1, hotbar_item if not hotbar_item.is_empty() else "—"]
			inventory_hotbar_buttons[slot_index].modulate = Color(0.35, 0.86, 1.0, 1.0) if slot_index == GameState.selected_hotbar else Color(0.83, 0.9, 0.96, 0.88)
		for slot_index in range(mini(storage_buttons.size(), GameState.backpack_slots.size())):
			var item_text := str(GameState.backpack_slots[slot_index])
			storage_buttons[slot_index].text = "%d\n%s" % [slot_index + 1, item_text if not item_text.is_empty() else "—"]
		var wallet_label := inventory_panel.find_child("WalletSummary", true, false) as Label
		if wallet_label:
			wallet_label.text = "CASH $%d     BANK CARD $%d     COINS %d" % [GameState.cash_wallet, GameState.bank_balance, GameState.money]

func _build_touch_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MobileControls"
	layer.layer = 8
	add_child(layer)
	touch_root = Control.new()
	touch_root.name = "TouchLayoutRoot"
	touch_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_root.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(touch_root)
	var defaults := {
		"move_forward": Vector2(0.09, 0.70), "move_left": Vector2(0.025, 0.82),
		"move_back": Vector2(0.09, 0.82), "move_right": Vector2(0.155, 0.82),
		"jump": Vector2(0.84, 0.69), "crouch": Vector2(0.84, 0.81),
		"sprint": Vector2(0.73, 0.81), "interact": Vector2(0.91, 0.81),
		"camera_toggle": Vector2(0.73, 0.92), "inventory_toggle": Vector2(0.84, 0.92),
		"menu": Vector2(0.91, 0.92)
	}
	for action in defaults:
		if not touch_button_positions.has(action):
			touch_button_positions[action] = defaults[action]
	var captions := {
		"move_forward":"▲", "move_left":"◀", "move_back":"▼", "move_right":"▶",
		"jump":"JUMP", "crouch":"SIT", "sprint":"RUN", "interact":"USE",
		"camera_toggle":"CAM", "inventory_toggle":"BAG", "menu":"MENU"
	}
	for action in defaults:
		var button := Button.new()
		button.name = "Touch_" + action
		button.text = captions[action]
		button.custom_minimum_size = Vector2(70, 54) * touch_button_scale
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.modulate = Color(0.72, 0.9, 1.0, 0.82)
		button.add_to_group("touch_game_buttons")
		touch_root.add_child(button)
		touch_buttons[action] = button
		button.button_down.connect(_on_touch_action_down.bind(action))
		button.button_up.connect(_on_touch_action_up.bind(action))
		button.gui_input.connect(_on_touch_button_gui_input.bind(action))
	touch_edit_hint = Label.new()
	touch_edit_hint.text = "EDIT CONTROLS: DRAG BUTTONS TO MOVE"
	touch_edit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	touch_edit_hint.anchor_left = 0.2
	touch_edit_hint.anchor_right = 0.8
	touch_edit_hint.anchor_top = 0.04
	touch_edit_hint.anchor_bottom = 0.10
	touch_edit_hint.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	touch_edit_hint.visible = false
	touch_root.add_child(touch_edit_hint)
	touch_edit_done = Button.new()
	touch_edit_done.text = "DONE"
	touch_edit_done.anchor_left = 0.82
	touch_edit_done.anchor_right = 0.98
	touch_edit_done.anchor_top = 0.04
	touch_edit_done.anchor_bottom = 0.12
	touch_edit_done.visible = false
	touch_edit_done.pressed.connect(_toggle_touch_edit_mode)
	touch_root.add_child(touch_edit_done)
	touch_root.resized.connect(_position_touch_buttons)
	_position_touch_buttons()

func _position_touch_buttons() -> void:
	if touch_root == null:
		return
	for action in touch_buttons:
		var button: Button = touch_buttons[action]
		var normalized: Vector2 = touch_button_positions.get(action, Vector2(0.5, 0.5))
		button.position = Vector2(normalized.x * touch_root.size.x, normalized.y * touch_root.size.y)
		button.custom_minimum_size = Vector2(70, 54) * touch_button_scale

func _on_touch_action_down(action: String) -> void:
	if touch_edit_mode:
		return
	match action:
		"camera_toggle": _toggle_camera()
		"interact": _interact_nearest()
		"inventory_toggle": _toggle_inventory()
		"menu": _toggle_pause_menu()
		_: Input.action_press(action)

func _on_touch_action_up(action: String) -> void:
	if action in ["move_left", "move_right", "move_forward", "move_back", "jump", "sprint", "crouch"]:
		Input.action_release(action)

func _on_touch_button_gui_input(event: InputEvent, action: String) -> void:
	if not touch_edit_mode:
		return
	var button: Button = touch_buttons.get(action)
	if button == null:
		return
	if event is InputEventScreenDrag:
		button.position += event.relative
		_save_touch_button_position(action, button)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		button.position += event.relative
		_save_touch_button_position(action, button)

func _save_touch_button_position(action: String, button: Button) -> void:
	var max_x := maxf(1.0, touch_root.size.x - button.size.x)
	var max_y := maxf(1.0, touch_root.size.y - button.size.y)
	button.position.x = clampf(button.position.x, 0.0, max_x)
	button.position.y = clampf(button.position.y, 0.0, max_y)
	touch_button_positions[action] = Vector2(button.position.x / max_x, button.position.y / max_y)
	_save_player_settings()

func _toggle_touch_edit_mode() -> void:
	touch_edit_mode = not touch_edit_mode
	if touch_edit_mode:
		_release_touch_actions()
		touch_edit_hint.visible = true
		touch_edit_done.visible = true
		for button in touch_buttons.values():
			button.modulate = Color(1.0, 0.78, 0.34, 0.95)
		_show_message("DRAG EACH BUTTON TO MOVE IT")
	else:
		touch_edit_hint.visible = false
		touch_edit_done.visible = false
		for button in touch_buttons.values():
			button.modulate = Color(0.72, 0.9, 1.0, 0.82)
		_save_player_settings()

func _release_touch_actions() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back", "jump", "sprint", "crouch"]:
		Input.action_release(action)

func _build_pause_and_settings() -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.color = Color(0.015, 0.025, 0.045, 0.88)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.visible = false
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var layer := get_node_or_null("GameHUD") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "GameHUD"
		add_child(layer)
	layer.add_child(pause_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)
	var card := PanelContainer.new()
	pause_card = card
	card.custom_minimum_size = Vector2(320, 0)
	center.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	card.add_child(stack)
	var heading := Label.new()
	heading.text = "SHADOW WORLD  •  PAUSED"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	stack.add_child(heading)
	var resume := Button.new()
	resume.text = "RESUME GAME"
	resume.pressed.connect(_close_pause_menu)
	stack.add_child(resume)
	var settings := Button.new()
	settings.text = "GAME SETTINGS"
	settings.pressed.connect(_open_settings)
	stack.add_child(settings)
	var save_button := Button.new()
	save_button.text = "SAVE GAME"
	save_button.pressed.connect(func():
		SaveSystem.save_game()
		_show_message("GAME SAVED")
	)
	stack.add_child(save_button)
	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.custom_minimum_size = Vector2(340, 0)
	settings_panel.visible = false
	center.add_child(settings_panel)
	var settings_stack := VBoxContainer.new()
	settings_stack.add_theme_constant_override("separation", 9)
	settings_panel.add_child(settings_stack)
	var title := Label.new()
	title.text = "CONTROL & DISPLAY SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	settings_stack.add_child(title)
	_add_setting_slider(settings_stack, "LOOK SENSITIVITY", 0.4, 3.0, 0.05, sensitivity_multiplier, func(v: float):
		sensitivity_multiplier = v
		_save_player_settings()
	)
	_add_setting_slider(settings_stack, "FIELD OF VIEW", 55.0, 100.0, 1.0, camera_fov, func(v: float):
		camera_fov = v
		camera.fov = camera_fov
		_save_player_settings()
	)
	_add_setting_slider(settings_stack, "THIRD PERSON DISTANCE", 2.5, 8.0, 0.1, camera_distance, func(v: float):
		camera_distance = v
		if not first_person:
			camera.position.z = camera_distance
		_save_player_settings()
	)
	_add_setting_slider(settings_stack, "TOUCH BUTTON SIZE", 0.75, 1.5, 0.05, touch_button_scale, func(v: float):
		touch_button_scale = v
		_apply_touch_button_scale()
		_save_player_settings()
	)
	var invert := CheckBox.new()
	invert.text = "INVERT VERTICAL CAMERA"
	invert.button_pressed = invert_look_y
	invert.toggled.connect(func(v: bool):
		invert_look_y = v
		_save_player_settings()
	)
	settings_stack.add_child(invert)
	var quality := OptionButton.new()
	quality.add_item("LOW  •  PERFORMANCE", 0)
	quality.add_item("MEDIUM  •  BALANCED", 1)
	quality.add_item("HIGH  •  VISUAL", 2)
	quality.add_item("CINEMATIC  •  MAX", 3)
	quality.select(graphics_quality)
	quality.item_selected.connect(_apply_graphics_quality)
	settings_stack.add_child(quality)
	var layout := OptionButton.new()
	layout.add_item("TOUCH BUTTONS: LEFT-HAND MOVE", 0)
	layout.add_item("TOUCH BUTTONS: RIGHT-HAND MOVE", 1)
	layout.select(0 if touch_layout_left else 1)
	layout.item_selected.connect(func(index: int):
		touch_layout_left = index == 0
		_rebuild_touch_controls()
		_save_player_settings()
	)
	settings_stack.add_child(layout)
	var edit_layout := Button.new()
	edit_layout.text = "CUSTOMIZE TOUCH BUTTON POSITIONS"
	edit_layout.pressed.connect(_toggle_touch_edit_mode)
	settings_stack.add_child(edit_layout)
	var back := Button.new()
	back.text = "BACK TO PAUSE MENU"
	back.pressed.connect(func():
		settings_panel.visible = false
		pause_card.visible = true
	)
	settings_stack.add_child(back)

func _add_setting_slider(parent: VBoxContainer, caption: String, minimum: float, maximum: float, step: float, initial: float, callback: Callable) -> void:
	var label := Label.new()
	label.text = "%s  •  %s" % [caption, str(initial)]
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(280, 24)
	slider.value_changed.connect(func(value: float):
		label.text = "%s  •  %s" % [caption, str(snappedf(value, step))]
		callback.call(value)
	)
	parent.add_child(slider)

func _toggle_pause_menu() -> void:
	if pause_overlay == null:
		return
	pause_overlay.visible = not pause_overlay.visible
	if pause_overlay.visible:
		_release_touch_actions()
		touch_edit_mode = false
		touch_edit_hint.visible = false
		touch_edit_done.visible = false
	settings_panel.visible = false
	pause_card.visible = true
	get_tree().paused = pause_overlay.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_overlay.visible else Input.MOUSE_MODE_CAPTURED

func _close_pause_menu() -> void:
	pause_overlay.visible = false
	settings_panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_settings() -> void:
	pause_card.visible = false
	settings_panel.visible = true

func _apply_graphics_quality(index: int) -> void:
	graphics_quality = index
	match index:
		0:
			camera.far = 110.0
			Engine.max_fps = 30
		1:
			camera.far = 180.0
			Engine.max_fps = 60
		2:
			camera.far = 260.0
			Engine.max_fps = 60
		3:
			camera.far = 360.0
			Engine.max_fps = 60
	for cloud in get_tree().get_nodes_in_group("world_clouds"):
		cloud.visible = index > 0
	for cloud in get_tree().get_nodes_in_group("world_clouds_cinematic"):
		cloud.visible = index >= 2
	for world_env_node in get_tree().get_nodes_in_group("world_environment"):
		var env: Environment = world_env_node.environment
		env.glow_enabled = index >= 2
		env.glow_intensity = 0.32 if index >= 2 else 0.0
	for light in get_tree().get_nodes_in_group("world_sun"):
		light.directional_shadow_max_distance = 45.0 if index == 0 else (85.0 if index == 1 else 130.0)
	_save_player_settings()

func _apply_touch_button_scale() -> void:
	for button in get_tree().get_nodes_in_group("touch_game_buttons"):
		if button is Button:
			button.custom_minimum_size = Vector2(70, 54) * touch_button_scale
	_position_touch_buttons()

func _rebuild_touch_controls() -> void:
	var old := get_node_or_null("MobileControls")
	if old:
		old.queue_free()
	touch_buttons.clear()
	touch_root = null
	_build_touch_controls()
	_apply_saved_touch_positions()

func _apply_saved_touch_positions() -> void:
	if touch_root == null:
		return
	_position_touch_buttons()

func _save_player_settings() -> void:
	settings_config.set_value("camera", "sensitivity", sensitivity_multiplier)
	settings_config.set_value("camera", "invert_y", invert_look_y)
	settings_config.set_value("camera", "fov", camera_fov)
	settings_config.set_value("camera", "distance", camera_distance)
	settings_config.set_value("controls", "button_scale", touch_button_scale)
	settings_config.set_value("controls", "left_hand_move", touch_layout_left)
	for action in touch_button_positions:
		settings_config.set_value("touch_layout", action, touch_button_positions[action])
	settings_config.set_value("graphics", "quality", graphics_quality)
	settings_config.save("user://stickman_settings.cfg")

func _load_player_settings() -> void:
	if settings_config.load("user://stickman_settings.cfg") != OK:
		return
	sensitivity_multiplier = float(settings_config.get_value("camera", "sensitivity", 1.0))
	invert_look_y = bool(settings_config.get_value("camera", "invert_y", false))
	camera_fov = float(settings_config.get_value("camera", "fov", 75.0))
	camera_distance = float(settings_config.get_value("camera", "distance", 4.2))
	touch_button_scale = float(settings_config.get_value("controls", "button_scale", 1.0))
	touch_layout_left = bool(settings_config.get_value("controls", "left_hand_move", true))
	for action in touch_button_positions:
		touch_button_positions[action] = settings_config.get_value("touch_layout", action, touch_button_positions[action])
	graphics_quality = int(settings_config.get_value("graphics", "quality", 1))
	camera.fov = camera_fov
	camera.position.z = camera_distance
	_apply_saved_touch_positions()
	_apply_touch_button_scale()
	_apply_graphics_quality(graphics_quality)
