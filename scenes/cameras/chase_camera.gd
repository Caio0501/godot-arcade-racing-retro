extends Node3D
## Câmera de perseguição com filtro pixelizado. Segue o `target` com atraso:
## posição rápida e rotação mais lenta, o que deixa a câmera "atrasada" nas
## curvas. Fica fora do carro para poder seguir qualquer veículo.

@export var target: Node3D
@export var position_smoothing := 20.0
@export var rotation_smoothing := 5.0

@onready var camera: Camera3D = $Camera


func _ready() -> void:
	if target:
		global_transform = target.global_transform


func _physics_process(delta: float) -> void:
	if not target:
		return
	global_position = global_position.lerp(target.global_position, delta * position_smoothing)
	global_transform = global_transform.interpolate_with(target.global_transform, delta * rotation_smoothing)
