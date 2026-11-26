extends CharacterBody3D

@export var walk_speed := 5.2
@export var sprint_speed := 8.4
@export var jump_velocity := 5.6
@export var mouse_sensitivity := 0.0022
@export var acceleration := 18.0

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
var hud_label: Label
var prompt_label: Label
var message_label: Label
var message_timer := 0.0
var parkour_cooldown := 0.0
var is_vaulting := false

func _ready() -> void:
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
	if not is_on_floor():
		velocity.y -= gravity * delta
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_vector.x, 0, input_vector.y)).normalized()
	var wants_sprint := Input.is_action_pressed("sprint") and stamina > 1.0 and input_vector.length() > 0.1
	var target_speed := sprint_speed if wants_sprint else walk_speed
	stamina = maxf(0.0, stamina - 22.0 * delta) if wants_sprint else minf(100.0, stamina + 13.0 * delta)
	if direction.length() > 0.01:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_velocity
		else:
			_try_parkour_jump(direction)
	move_and_slide()
	_animate_character(delta, input_vector.length() > 0.1)
	_update_interaction_prompt()
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			message_label.text = ""
	if hud_label:
		hud_label.text = "STICKMAN  •  COINS %d  •  XP %d  •  STAMINA %d%%" % [GameState.money, GameState.experience, int(stamina)]

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
	if moving:
		walk_phase += delta * (13.0 if Input.is_action_pressed("sprint") else 8.0)
	else:
		walk_phase = move_toward(walk_phase, 0.0, delta * 5.0)
	for i in range(limbs.size()):
		var amount := sin(walk_phase + (PI if i % 2 == 1 else 0.0)) * 0.62 if moving else 0.0
		limbs[i].rotation.x = lerpf(limbs[i].rotation.x, amount, delta * 12.0)

func _build_character() -> void:
	body_mesh.visible = false
	visual_root = Node3D.new()
	visual_root.name = "StickmanVisual"
	add_child(visual_root)
	var dark := _material(Color(0.045, 0.055, 0.075), 0.38)
	var accent := _material(Color(0.05, 0.72, 0.95), 0.3)
	var skin := _material(Color(0.92, 0.78, 0.62), 0.55)
	_add_sphere("Head", Vector3(0, 1.66, 0), Vector3(0.27, 0.27, 0.27), skin)
	_add_capsule("Torso", Vector3(0, 1.12, 0), 0.16, 0.72, accent)
	_add_capsule("Hip", Vector3(0, 0.72, 0), 0.17, 0.22, dark)
	_add_limb("LeftArm", Vector3(-0.19, 1.39, 0), 0.075, 0.58, dark)
	_add_limb("RightArm", Vector3(0.19, 1.39, 0), 0.075, 0.58, dark)
	_add_limb("LeftLeg", Vector3(-0.1, 0.48, 0), 0.09, 0.7, dark)
	_add_limb("RightLeg", Vector3(0.1, 0.48, 0), 0.09, 0.7, dark)
	_add_box("LeftFoot", Vector3(-0.1, 0.09, -0.07), Vector3(0.18, 0.13, 0.34), accent)
	_add_box("RightFoot", Vector3(0.1, 0.09, -0.07), Vector3(0.18, 0.13, 0.34), accent)

func _material(color: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat

func _add_sphere(label: String, pos: Vector3, scale_value: Vector3, mat: Material) -> void:
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

func _add_capsule(label: String, pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	visual_root.add_child(node)

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
	camera.position = Vector3(0, 0.03, 0.02) if first_person else Vector3(0, 0.55, camera_distance)
	camera.fov = camera_fov
	visual_root.visible = not first_person

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
		var was_mission_active := GameState.active_mission == "The First Errand" and not GameState.mission_completed
		_show_message(nearest.interact())
		if was_mission_active and str(nearest.get("interaction_type")) == "mission":
			GameState.complete_mission(120, 35)
			_show_message("Mission complete! +120 coins • +35 XP")

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
	var keys := {"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"move_forward":[KEY_W,KEY_UP],"move_back":[KEY_S,KEY_DOWN],"jump":[KEY_SPACE],"sprint":[KEY_SHIFT]}
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

func _build_touch_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MobileControls"
	add_child(layer)
	var panel := HBoxContainer.new()
	panel.anchor_left = 0.02
	panel.anchor_top = 0.68
	panel.anchor_right = 0.98
	panel.anchor_bottom = 0.98
	panel.add_theme_constant_override("separation", 10)
	layer.add_child(panel)
	var movement := VBoxContainer.new()
	_add_touch_button(movement, "▲", "move_forward")
	var row := HBoxContainer.new()
	movement.add_child(row)
	_add_touch_button(row, "◀", "move_left")
	_add_touch_button(row, "▼", "move_back")
	_add_touch_button(row, "▶", "move_right")
	var actions := VBoxContainer.new()
	_add_touch_button(actions, "JUMP", "jump")
	_add_touch_button(actions, "SPRINT", "sprint")
	_add_touch_button(actions, "INTERACT", "interact")
	_add_touch_button(actions, "CAMERA", "camera_toggle")
	var menu_button := Button.new()
	menu_button.text = "MENU"
	menu_button.custom_minimum_size = Vector2(76, 42) * touch_button_scale
	menu_button.add_to_group("touch_game_buttons")
	menu_button.pressed.connect(_toggle_pause_menu)
	actions.add_child(menu_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if touch_layout_left:
		panel.add_child(movement)
		panel.add_child(spacer)
		panel.add_child(actions)
	else:
		panel.add_child(actions)
		panel.add_child(spacer)
		panel.add_child(movement)

func _add_touch_button(parent: Control, caption: String, action: String) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(76, 50) * touch_button_scale
	button.focus_mode = Control.FOCUS_NONE
	button.modulate = Color(0.7, 0.9, 1.0, 0.88)
	parent.add_child(button)
	button.add_to_group("touch_game_buttons")
	if action == "camera_toggle":
		button.pressed.connect(_toggle_camera)
	elif action == "interact":
		button.pressed.connect(_interact_nearest)
	else:
		button.button_down.connect(func(): Input.action_press(action))
		button.button_up.connect(func(): Input.action_release(action))


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
			button.custom_minimum_size = Vector2(76, 50) * touch_button_scale

func _rebuild_touch_controls() -> void:
	var old := get_node_or_null("MobileControls")
	if old:
		old.queue_free()
	_build_touch_controls()

func _save_player_settings() -> void:
	settings_config.set_value("camera", "sensitivity", sensitivity_multiplier)
	settings_config.set_value("camera", "invert_y", invert_look_y)
	settings_config.set_value("camera", "fov", camera_fov)
	settings_config.set_value("camera", "distance", camera_distance)
	settings_config.set_value("controls", "button_scale", touch_button_scale)
	settings_config.set_value("controls", "left_hand_move", touch_layout_left)
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
	graphics_quality = int(settings_config.get_value("graphics", "quality", 1))
	camera.fov = camera_fov
	camera.position.z = camera_distance
	_apply_touch_button_scale()
	_apply_graphics_quality(graphics_quality)
