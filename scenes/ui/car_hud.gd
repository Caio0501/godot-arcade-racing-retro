extends CanvasLayer
## HUD simples do carro: velocidade, marcha, RPM e pedal (acelerador/freio).
## RPM e marcha vêm do nó CarAudio do carro, que simula o câmbio.

const PEDAL_GAS := Color(0.35, 0.85, 0.4)
const PEDAL_BRAKE := Color(0.95, 0.3, 0.25)
const RPM_LOW := Color(0.35, 0.85, 0.4)
const RPM_MID := Color(0.98, 0.8, 0.2)
const RPM_HIGH := Color(0.95, 0.3, 0.25)

@export var car: VehicleBody3D
## Força máxima do motor, para converter engine_force em pedal (0 a 1).
@export var max_engine_force := 300.0

@onready var _speed: Label = %Speed
@onready var _gear: Label = %Gear
@onready var _rpm_bar: ProgressBar = %RpmBar
@onready var _pedal_bar: ProgressBar = %PedalBar
@onready var _pedal_label: Label = %PedalLabel

var _audio: Node
var _rpm_fill: StyleBoxFlat
var _pedal_fill: StyleBoxFlat


func _ready() -> void:
	if car:
		_audio = car.get_node_or_null("CarAudio")
	# Cópias próprias do preenchimento para poder trocar a cor em tempo real.
	_rpm_fill = _rpm_bar.get_theme_stylebox("fill").duplicate()
	_rpm_bar.add_theme_stylebox_override("fill", _rpm_fill)
	_pedal_fill = _pedal_bar.get_theme_stylebox("fill").duplicate()
	_pedal_bar.add_theme_stylebox_override("fill", _pedal_fill)


func _process(_delta: float) -> void:
	if not car:
		return
	var forward_speed := car.linear_velocity.dot(car.global_basis.z)
	# Só a velocidade no plano: quedas e pulos não contam no velocímetro.
	var ground_speed := Vector2(car.linear_velocity.x, car.linear_velocity.z).length()
	_speed.text = str(roundi(ground_speed * 3.6))

	var pedal := clampf(car.engine_force / max_engine_force, -1.0, 1.0)
	_pedal_bar.value = absf(pedal)
	_pedal_fill.bg_color = PEDAL_GAS if pedal >= 0.0 else PEDAL_BRAKE
	_pedal_label.text = "ACEL" if pedal >= 0.0 else "FREIO"

	if _audio:
		var rpm: float = _audio.rpm
		_rpm_bar.value = rpm
		if rpm < 0.7:
			_rpm_fill.bg_color = RPM_LOW
		elif rpm < 0.88:
			_rpm_fill.bg_color = RPM_MID
		else:
			_rpm_fill.bg_color = RPM_HIGH

	if forward_speed < -0.5:
		_gear.text = "R"
	elif absf(forward_speed) < 0.5 and pedal == 0.0:
		_gear.text = "N"
	elif _audio:
		_gear.text = str(_audio.gear + 1)
