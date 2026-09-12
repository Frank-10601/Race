class_name StepBenchmark
extends Node
## Mesure le cout d'UN pas de simulation, isole du rendu.
##
## Pourquoi une mesure separee : les compteurs de Godot rapportent un temps par
## IMAGE. Comparer bureau et navigateur sur cette base ne veut rien dire, car le
## nombre d'images par seconde differe enormement — surtout sur une machine sans
## carte graphique, ou le rendu ecrase tout le reste.
##
## Ici on chronometre uniquement `VehiclePhysics.step()`, en microsecondes par
## pas et par vehicule. C'est le chiffre comparable entre les plateformes, et
## c'est celui qui decide si un serveur peut tenir 12 voitures a 60 Hz.

signal finished(microseconds_per_step: float)

## Pas simules pour la mesure. Assez pour lisser le bruit, assez peu pour ne pas
## figer un navigateur pendant plusieurs secondes.
const ITERATIONS: int = 2000

var _vehicle: Vehicle = null
var _armed: bool = false


func measure(vehicle: Vehicle) -> void:
	_vehicle = vehicle
	_armed = true
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if not _armed or _vehicle == null:
		return
	_armed = false
	set_physics_process(false)

	var state: VehicleState = _vehicle.state.copy()
	var input: InputFrame = InputFrame.create(0, 1.0, 0.0, 0.35, false, false)
	var delta: float = Tuning.physics_delta

	# Quelques pas a blanc : le premier appel paie l'initialisation des requetes
	# physiques et fausserait la moyenne.
	for _warmup: int in 60:
		state = _vehicle.physics.step(state, input, delta)

	var started: int = Time.get_ticks_usec()
	for _index: int in ITERATIONS:
		state = _vehicle.physics.step(state, input, delta)
	var elapsed: int = Time.get_ticks_usec() - started

	var per_step: float = float(elapsed) / float(ITERATIONS)
	print("[mesure] cout d'un pas de simulation : %.1f us par vehicule (%d pas en %.1f ms)"
		% [per_step, ITERATIONS, float(elapsed) / 1000.0])
	print("[mesure] budget a 60 Hz : %.1f %% pour 1 vehicule, %.1f %% pour 12"
		% [per_step / 16666.0 * 100.0, per_step * 12.0 / 16666.0 * 100.0])
	finished.emit(per_step)
