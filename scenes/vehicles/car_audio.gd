extends Node3D
## Sons do carro. Precisa ser filho de um Vehicle (vehicle.gd).
## - Motor: loop com pitch pelo RPM de um câmbio simulado.
## - Pneus: chiado quando as rodas perdem aderência no asfalto.
## - Terra: ronco de cascalho rodando em superfície com meta "surface" = "dirt".
## - Batidas: tocadas quando a velocidade muda bruscamente.
## Os WAVs são gerados por tools/generate_car_sfx.py.

const ENGINE_SOUND := preload("res://assets/audio/car/engine_loop.wav")
const SKID_SOUND := preload("res://assets/audio/car/skid_loop.wav")
const GRAVEL_SOUND := preload("res://assets/audio/car/gravel_loop.wav")
const IMPACT_SOUND := preload("res://assets/audio/car/impact.wav")
const SILENT_DB := -60.0

@export var idle_pitch := 0.8
@export var max_pitch := 3.2
## Limite de cada marcha do câmbio simulado, como fração da velocidade máxima
## do veículo (Vehicle.top_speed). A última marcha deve ser 1.0.
@export var gear_ratios := PackedFloat32Array([0.18, 0.34, 0.52, 0.74, 1.0])
## Variação de velocidade (m/s) num frame de física que conta como batida.
@export var impact_threshold := 3.0

@onready var _car := get_parent() as Vehicle

var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _gravel: AudioStreamPlayer3D
var _impact: AudioStreamPlayer3D
var _wheels: Array[VehicleWheel3D] = []
## RPM normalizado (0 = marcha lenta, 1 = limite) e marcha atual (0 = primeira).
## Lidos também pelo HUD.
var rpm := 0.0
var gear := 0
var _prev_velocity := Vector3.ZERO
var _impact_cooldown := 0.0


func _ready() -> void:
	_engine = _make_player("Engine", ENGINE_SOUND)
	_skid = _make_player("Skid", SKID_SOUND)
	_gravel = _make_player("Gravel", GRAVEL_SOUND)
	_impact = _make_player("Impact", IMPACT_SOUND)
	_impact.max_polyphony = 3
	for p in [_engine, _skid, _gravel]:
		p.volume_db = SILENT_DB
		p.play()
	for child in _car.get_children():
		if child is VehicleWheel3D:
			_wheels.append(child)


func _physics_process(delta: float) -> void:
	var velocity := _car.linear_velocity
	var speed := velocity.length()
	var throttle := absf(_car.throttle_input)

	_update_engine(delta, throttle)
	_update_tires(speed)
	_update_impacts(delta, velocity)
	_prev_velocity = velocity


func _update_engine(delta: float, throttle: float) -> void:
	var forward_speed := absf(_car.linear_velocity.dot(_car.global_basis.z))
	var ratio := forward_speed / maxf(_car.top_speed, 1.0)
	gear = 0
	while gear < gear_ratios.size() - 1 and ratio > gear_ratios[gear]:
		gear += 1
	var in_gear := clampf(ratio / gear_ratios[gear], 0.0, 1.0)
	# Sem tração (no ar ou parado acelerando) o motor gira solto.
	var free_rev := throttle * (0.6 if not _any_wheel_in_contact() else 0.2)
	var target := maxf(in_gear * 0.85 + throttle * 0.15, free_rev)
	var rate := 8.0 if target > rpm else 4.0
	rpm = lerpf(rpm, target, 1.0 - exp(-rate * delta))

	_engine.pitch_scale = lerpf(idle_pitch, max_pitch, rpm)
	_engine.volume_db = lerpf(-12.0, -2.0, clampf(throttle * 0.6 + rpm * 0.4, 0.0, 1.0))


func _update_tires(speed: float) -> void:
	var slip := 0.0
	var on_dirt := 0
	var in_contact := 0
	for wheel in _wheels:
		if not wheel.is_in_contact():
			continue
		in_contact += 1
		var body := wheel.get_contact_body()
		if body and body.get_meta("surface", "asphalt") == "dirt":
			on_dirt += 1
		else:
			slip = maxf(slip, 1.0 - wheel.get_skidinfo())

	# Derrapagem lateral também chia, mesmo com as rodas "agarrando".
	var lateral := absf(_car.linear_velocity.dot(_car.global_basis.x))
	slip = maxf(slip, clampf((lateral - 2.0) / 6.0, 0.0, 1.0))
	if speed < 2.0:
		slip = 0.0
	var dirt_ratio := float(on_dirt) / maxf(in_contact, 1)

	_skid.volume_db = _amount_to_db(slip * (1.0 - dirt_ratio), -4.0)
	_skid.pitch_scale = 0.9 + slip * 0.2
	_gravel.volume_db = _amount_to_db(dirt_ratio * clampf(speed / 20.0, 0.0, 1.0), -3.0)
	_gravel.pitch_scale = 0.8 + clampf(speed / 40.0, 0.0, 0.6)


func _update_impacts(delta: float, velocity: Vector3) -> void:
	_impact_cooldown -= delta
	var dv := (velocity - _prev_velocity).length()
	if dv > impact_threshold and _impact_cooldown <= 0.0:
		var strength := clampf((dv - impact_threshold) / 12.0, 0.0, 1.0)
		_impact.volume_db = lerpf(-14.0, 0.0, strength)
		_impact.pitch_scale = randf_range(0.85, 1.1)
		_impact.play()
		_impact_cooldown = 0.15


func _any_wheel_in_contact() -> bool:
	for wheel in _wheels:
		if wheel.is_in_contact():
			return true
	return false


func _amount_to_db(amount: float, max_db: float) -> float:
	if amount <= 0.01:
		return SILENT_DB
	return max_db + linear_to_db(amount)


func _make_player(node_name: String, stream: AudioStream) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = stream
	# Atenuação suave: continua audível com a câmera alta de rally.
	player.unit_size = 15.0
	add_child(player)
	return player
