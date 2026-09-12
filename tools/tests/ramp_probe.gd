extends Node
## Trace le passage des rampes pas a pas, pour voir ou la voiture perd sa vitesse.

const TRACK_SCENE: String = "res://src/track/test_track.tscn"

var _track: Node3D = null
var _vehicle: Vehicle = null
var _warmup: int = 0


func _ready() -> void:
	var scene: PackedScene = load(TRACK_SCENE) as PackedScene
	_track = scene.instantiate() as Node3D
	add_child(_track)
	_vehicle = Vehicle.new()
	_vehicle.configure(1, "Sonde", 0, Vehicle.Mode.AUTHORITY, _track)
	add_child(_vehicle)
	_vehicle.place_at(_track.call("get_spawn_transform", 0))


func _physics_process(_delta: float) -> void:
	_warmup += 1
	if _warmup < 4:
		return
	set_physics_process(false)

	var transform: Transform3D = _track.call("get_spawn_transform", 0)
	var state: VehicleState = VehicleState.create_at(
		transform.origin + Vector3.UP * Tuning.spawn_height, transform.basis.get_euler().y)
	var full_throttle: InputFrame = InputFrame.create(0, 1.0, 0.0, 0.0, false, false)

	print("pas | distance | hauteur | vitesse | au sol | verticale")
	for step: int in 360:
		state = _vehicle.physics.step(state, full_throttle, Tuning.physics_delta)
		if step % 10 == 0:
			print("%3d | %8.1f | %7.2f | %7.1f | %6s | %+6.1f" % [
				step, -state.position.z, state.position.y,
				state.get_speed() * 3.6, "oui" if state.grounded else "non",
				state.velocity.y])
	get_tree().quit()
