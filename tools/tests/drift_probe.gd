extends Node
## Sonde de reglage du derapage : affiche l'evolution de la glisse pas a pas,
## pour choisir `drift_slip_damping` sur des mesures plutot qu'au juge.

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
	for damping: float in [0.0, 0.8, 1.4, 2.0, 2.6]:
		Tuning.drift_slip_damping = damping
		_probe(damping)
	get_tree().quit()



## Grande surface plate a l'ecart du trace. Les essais de conduite doivent
## mesurer le MODELE, pas la geometrie du circuit : teste pres de la piste, la
## voiture finissait par percuter un mur et les mesures ne voulaient plus rien
## dire.
const TEST_AREA: Vector3 = Vector3(-200.0, 0.0, -200.0)


func _open_state(speed: float) -> VehicleState:
	var state: VehicleState = VehicleState.create_at(
		TEST_AREA + Vector3.UP * Tuning.spawn_height, 0.0)
	var neutral: InputFrame = InputFrame.create(0, 0.0, 0.0, 0.0, false, false)
	for _index: int in 16:
		state = _vehicle.physics.step(state, neutral, Tuning.physics_delta)
	state.velocity = -state.get_basis().z * speed
	return state


func _probe(damping: float) -> void:
	var state: VehicleState = _open_state(30.0)

	var drifting: InputFrame = InputFrame.create(0, 1.0, 0.0, 1.0, true, false)
	var samples: PackedStringArray = PackedStringArray()
	for step: int in 90:
		state = _vehicle.physics.step(state, drifting, Tuning.physics_delta)
		if (step + 1) % 18 == 0:
			samples.append("%.0f deg" % _signed_slip(state))
	print("damping %.1f -> derive apres 0,3 / 0,6 / 0,9 / 1,2 / 1,5 s : %s | vitesse finale %.0f km/h"
		% [damping, " , ".join(samples), state.get_speed() * 3.6])


## Angle de derive signe : negatif = la voiture glisse vers sa gauche.
func _signed_slip(state: VehicleState) -> float:
	var basis: Basis = state.get_basis()
	var lateral: float = state.velocity.dot(basis.x)
	var forward: float = state.velocity.dot(-basis.z)
	return rad_to_deg(atan2(lateral, absf(forward)))
