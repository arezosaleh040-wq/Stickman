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
var stamina := 100.0
var visual_root: Node3D
var limbs: Array[Node3D] = []
var walk_phase := 0.0
var hud_label: Label
var prompt_label: Label
var message_label: Label
var message_timer := 0.0

func _ready() -> void:
	add_to_group("player")
	_add_input_actions()
	_build_character()
	_build_touch_controls()
	_build_hud()
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
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative)
	if event is InputEventScreenDrag and event.position.x > get_viewport().get_visible_rect().size.x * 0.42:
		_rotate_camera(event.relative)

func _rotate_camera(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	camera_pivot.rotate_x(-relative.y * mouse_sensitivity)
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.1, 1.1)

func _physics_process(delta: float) -> void:
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
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	move_and_slide()
	_animate_character(delta, input_vector.length() > 0.1)
	_update_interaction_prompt()
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			message_label.text = ""
	if hud_label:
		hud_label.text = "STICKMAN  •  COINS %d  •  XP %d  •  STAMINA %d%%" % [GameState.money, GameState.experience, int(stamina)]

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
	camera.position = Vector3(0, 0.03, 0.02) if first_person else Vector3(0, 0.55, 4.1)
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
	panel.add_child(movement)
	_add_touch_button(movement, "▲", "move_forward")
	var row := HBoxContainer.new()
	movement.add_child(row)
	_add_touch_button(row, "◀", "move_left")
	_add_touch_button(row, "▼", "move_back")
	_add_touch_button(row, "▶", "move_right")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(spacer)
	var actions := VBoxContainer.new()
	panel.add_child(actions)
	_add_touch_button(actions, "JUMP", "jump")
	_add_touch_button(actions, "SPRINT", "sprint")
	_add_touch_button(actions, "INTERACT", "interact")
	_add_touch_button(actions, "CAMERA", "camera_toggle")

func _add_touch_button(parent: Control, caption: String, action: String) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(76, 50)
	button.focus_mode = Control.FOCUS_NONE
	button.modulate = Color(0.7, 0.9, 1.0, 0.88)
	parent.add_child(button)
	if action == "camera_toggle":
		button.pressed.connect(_toggle_camera)
	elif action == "interact":
		button.pressed.connect(_interact_nearest)
	else:
		button.button_down.connect(func(): Input.action_press(action))
		button.button_up.connect(func(): Input.action_release(action))
