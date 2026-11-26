extends CharacterBody3D

@export var move_speed: float = 5.5
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.0025
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var body_mesh: MeshInstance3D = $Body

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var first_person := false
var touch_actions: Dictionary = {}

func _ready() -> void:
	_add_input_actions()
	_build_touch_controls()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		_toggle_camera()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.15, 1.15)
	if event is InputEventScreenDrag:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.15, 1.15)
	if event is InputEventScreenTouch and event.pressed:
		pass

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_vector.x, 0, input_vector.y)).normalized()
	if direction.length() > 0.01:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * 5.0 * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	move_and_slide()

func _add_input_actions() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE]
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in keys[action]:
			var key_event := InputEventKey.new()
			key_event.keycode = keycode
			InputMap.action_add_event(action, key_event)

func _toggle_camera() -> void:
	first_person = not first_person
	camera.position = Vector3(0, 0.05, 0) if first_person else Vector3(0, 1.2, 4.2)
	body_mesh.visible = not first_person

func _build_touch_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MobileControls"
	add_child(layer)

	var panel := HBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -330
	panel.offset_top = -112
	panel.offset_right = -18
	panel.offset_bottom = -18
	panel.add_theme_constant_override("separation", 8)
	layer.add_child(panel)

	var left_group := VBoxContainer.new()
	panel.add_child(left_group)
	_add_touch_button(left_group, "↑", "move_forward")
	var middle := HBoxContainer.new()
	left_group.add_child(middle)
	_add_touch_button(middle, "←", "move_left")
	_add_touch_button(middle, "↓", "move_back")
	_add_touch_button(middle, "→", "move_right")

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(spacer)

	var right_group := VBoxContainer.new()
	panel.add_child(right_group)
	_add_touch_button(right_group, "پرش", "jump")
	_add_touch_button(right_group, "دوربین", "camera_toggle")

func _add_touch_button(parent: Control, caption: String, action: String) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(66, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.modulate = Color(0.8, 0.9, 1.0, 0.82)
	parent.add_child(button)
	if action == "camera_toggle":
		button.pressed.connect(_toggle_camera)
	else:
		button.button_down.connect(func(): Input.action_press(action))
		button.button_up.connect(func(): Input.action_release(action))
