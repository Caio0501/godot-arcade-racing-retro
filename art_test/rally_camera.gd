extends Camera3D
## Câmera alta e inclinada, no estilo art of rally: segue o carro de longe,
## gira devagar na direção do movimento e ajusta o foco (DOF tilt-shift)
## pela distância até o carro. Tecla C alterna com a câmera do próprio carro.

@export var target: Node3D
@export var distance := 24.0
@export var height := 18.0
@export var follow_speed := 3.0
@export var turn_speed := 0.8
@export var focus_band := 10.0
## Distância à frente do carro para onde a câmera olha.
@export var look_ahead := 6.0

var _yaw := 0.0
var _car_camera: Camera3D
var _pixel_quad: Node3D


func _ready() -> void:
	if not target:
		return
	_car_camera = target.get_node_or_null("CameraPivot/Camera")
	# O quad de pixelização da câmera do carro aparece flutuando no mundo
	# quando outra câmera está ativa; escondemos enquanto esta câmera é a atual.
	_pixel_quad = target.get_node_or_null("CameraPivot/Camera/MeshInstance3D")
	_yaw = _heading_from_basis()
	global_position = _desired_position()
	look_at(target.global_position, Vector3.UP)
	make_current()
	_sync_pixel_quad()


func _process(delta: float) -> void:
	if not target:
		return
	var desired_yaw := _yaw
	var body := target as RigidBody3D
	if body and body.linear_velocity.length() > 3.0:
		desired_yaw = atan2(body.linear_velocity.x, body.linear_velocity.z)
	_yaw = lerp_angle(_yaw, desired_yaw, 1.0 - exp(-turn_speed * delta))
	global_position = global_position.lerp(_desired_position(), 1.0 - exp(-follow_speed * delta))
	var ahead := Vector3(sin(_yaw), 0, cos(_yaw)) * look_ahead
	look_at(target.global_position + ahead + Vector3.UP, Vector3.UP)

	var practical := attributes as CameraAttributesPractical
	if practical:
		var dist := global_position.distance_to(target.global_position)
		practical.dof_blur_far_distance = dist + focus_band
		practical.dof_blur_near_distance = maxf(dist - focus_band, 0.5)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_C and _car_camera:
		if current:
			_car_camera.make_current()
		else:
			make_current()
		_sync_pixel_quad()


func _sync_pixel_quad() -> void:
	if _pixel_quad:
		_pixel_quad.visible = not current


func _heading_from_basis() -> float:
	var fwd := target.global_basis.z  # a frente do SUV aponta para +Z
	return atan2(fwd.x, fwd.z)


func _desired_position() -> Vector3:
	var back := Vector3(sin(_yaw), 0, cos(_yaw)) * -distance
	return target.global_position + back + Vector3.UP * height
