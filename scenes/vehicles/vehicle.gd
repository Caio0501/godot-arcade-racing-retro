class_name Vehicle
extends VehicleBody3D
## Base de todos os carros. Lê `stats` (VehicleStats) e traduz para a física do
## VehicleBody3D: massa, força do motor, limite de velocidade, volante e
## aderência dos pneus. Para um modelo novo, monte a cena com VehicleWheel3D
## (marque use_as_steering / use_as_traction), use este script e aponte `stats`
## para um .tres próprio.

const MIN_WEIGHT := 600.0
const MAX_WEIGHT := 3000.0
## Tempo (s) até a velocidade máxima para o carro mais leve / mais pesado.
const ACCEL_TIME_LIGHT := 5.0
const ACCEL_TIME_HEAVY := 14.0
## Ângulo máximo do volante (rad) com dirigibilidade 1 / 10.
const STEER_ANGLE_MIN := 0.35
const STEER_ANGLE_MAX := 0.75
## Rapidez do volante (rad/s) com dirigibilidade 1 / 10.
const STEER_SPEED_MIN := 1.5
const STEER_SPEED_MAX := 4.0
## Fração do ângulo que sobra na velocidade máxima (volante fica mais "duro").
const STEER_AT_TOP_SPEED := 0.55
## Aderência das rodas dianteiras (wheel_friction_slip) com dirigibilidade 1 / 10.
## Quanto maior, mais força lateral o pneu aguenta antes de escorregar.
const FRONT_GRIP_MIN := 0.35
const FRONT_GRIP_MAX := 1.2
## Aderência traseira = dianteira × este fator, do mais leve ao mais pesado.
## Traseira mais firme que a frente faz o carro sair de frente em vez de rodar.
const REAR_GRIP_FACTOR_LIGHT := 0.8
const REAR_GRIP_FACTOR_HEAVY := 1.4
## Amortecimento de giro (angular_damp) do mais leve ao mais pesado.
const YAW_DAMP_LIGHT := 0.4
const YAW_DAMP_HEAVY := 1.2
## Força máxima de cada suspensão, em múltiplos do peso que ela sustenta parado.
## O padrão da Godot (6000 N) não segura carros pesados com gravity_scale alto.
const SUSPENSION_FORCE_HEADROOM := 3.0
## Desaceleração ao soltar o acelerador (1/s). Substitui o amortecimento padrão
## do projeto; o motor compensa esse arrasto enquanto acelera, então o tempo até
## a velocidade máxima continua sendo o definido pelo peso.
const COAST_DRAG := 0.15
## Freio de mão: força de frenagem das rodas traseiras por kg de massa (a doc
## da Godot sugere ~25-30 de brake para frear forte um carro de 1000 kg) e
## fração da aderência traseira que sobra com ele puxado, para a traseira
## escorregar e o carro girar nas curvas fechadas.
const HANDBRAKE_FORCE_PER_KG := 0.03
const HANDBRAKE_REAR_GRIP := 0.45
## Força de ré como fração da força do motor, e velocidade máxima de ré.
const REVERSE_FORCE := 0.6
const REVERSE_TOP_SPEED_KMH := 30.0

@export var stats: VehicleStats:
	set(value):
		if stats and stats.changed.is_connected(apply_stats):
			stats.changed.disconnect(apply_stats)
		stats = value
		if stats:
			stats.changed.connect(apply_stats)
		if is_inside_tree():
			apply_stats()
## Lê acelerador e volante do teclado/controle. Desligue para IA ou replays.
@export var player_controlled := true

## Valores calculados a partir de `stats`; lidos pelo áudio e pelo HUD.
var max_engine_force := 0.0
var top_speed := 0.0  # m/s
var throttle_input := 0.0
var steer_input := 0.0
var handbrake_input := false

var _traction_wheels := 1
var _rear_wheels: Array[VehicleWheel3D] = []
var _rear_grip := 1.0
var _max_steer := 0.5
var _steer_speed := 2.5


func _ready() -> void:
	apply_stats()


func apply_stats() -> void:
	var s := stats if stats else VehicleStats.new()
	var h := (s.handling - 1.0) / 9.0
	var w := clampf(inverse_lerp(MIN_WEIGHT, MAX_WEIGHT, s.weight), 0.0, 1.0)

	mass = s.weight
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = COAST_DRAG
	top_speed = s.top_speed / 3.6
	# Força constante que leva o carro do zero à velocidade máxima no tempo
	# definido pelo peso; o motor corta perto do limite em _physics_process.
	var accel_time := lerpf(ACCEL_TIME_LIGHT, ACCEL_TIME_HEAVY, w)
	max_engine_force = mass * top_speed / accel_time

	_max_steer = lerpf(STEER_ANGLE_MIN, STEER_ANGLE_MAX, h)
	_steer_speed = lerpf(STEER_SPEED_MIN, STEER_SPEED_MAX, h)
	angular_damp = lerpf(YAW_DAMP_LIGHT, YAW_DAMP_HEAVY, w)

	var front_grip := lerpf(FRONT_GRIP_MIN, FRONT_GRIP_MAX, h)
	var rear_grip := front_grip * lerpf(REAR_GRIP_FACTOR_LIGHT, REAR_GRIP_FACTOR_HEAVY, w)
	var wheels := get_children().filter(func(c): return c is VehicleWheel3D)
	var load_per_wheel := mass * float(ProjectSettings.get_setting("physics/3d/default_gravity")) * gravity_scale / maxf(wheels.size(), 1)
	_traction_wheels = maxi(wheels.filter(func(wh): return wh.use_as_traction).size(), 1)
	_rear_grip = rear_grip
	_rear_wheels.clear()
	for wheel: VehicleWheel3D in wheels:
		wheel.wheel_friction_slip = front_grip if wheel.use_as_steering else rear_grip
		wheel.suspension_max_force = load_per_wheel * SUSPENSION_FORCE_HEADROOM
		if not wheel.use_as_steering:
			_rear_wheels.append(wheel)


func _physics_process(delta: float) -> void:
	if player_controlled:
		throttle_input = Input.get_axis("brake", "accelerate")
		steer_input = Input.get_axis("steer_right", "steer_left")
		handbrake_input = Input.is_action_pressed("handbrake")

	var forward_speed := linear_velocity.dot(global_basis.z)
	var speed_ratio := clampf(absf(forward_speed) / top_speed, 0.0, 1.0)

	var steer_limit := _max_steer * lerpf(1.0, STEER_AT_TOP_SPEED, speed_ratio)
	steering = move_toward(steering, steer_input * steer_limit, delta * _steer_speed)

	var force := 0.0
	if throttle_input > 0.0:
		# Força base + compensação do arrasto, cortadas perto do limite.
		var drag := mass * COAST_DRAG * maxf(forward_speed, 0.0)
		force = (throttle_input * max_engine_force + drag) * _limiter(forward_speed, top_speed)
	elif throttle_input < 0.0:
		force = throttle_input * max_engine_force * REVERSE_FORCE
		if forward_speed <= 0.0:
			force *= _limiter(-forward_speed, REVERSE_TOP_SPEED_KMH / 3.6)
	if handbrake_input:
		force = 0.0  # embreagem pisada enquanto o freio de mão está puxado
	# A Godot aplica engine_force em cada roda de tração.
	engine_force = force / _traction_wheels

	for wheel in _rear_wheels:
		wheel.brake = mass * HANDBRAKE_FORCE_PER_KG if handbrake_input else 0.0
		wheel.wheel_friction_slip = _rear_grip * (HANDBRAKE_REAR_GRIP if handbrake_input else 1.0)


## Corta o motor suavemente nos últimos 4% antes do limite de velocidade.
func _limiter(speed: float, limit: float) -> float:
	return clampf((limit - speed) / (limit * 0.04), 0.0, 1.0)
