extends VehicleBody3D
## A câmera fica fora do carro: veja scenes/cameras/chase_camera.tscn.

const MAX_STEER = 0.8
const ENGINE_POWER = 300


func _physics_process(delta):
	steering = move_toward(steering, Input.get_axis("steer_right", "steer_left") * MAX_STEER, delta * 2.5)
	engine_force = Input.get_axis("brake","accelerate") * ENGINE_POWER
