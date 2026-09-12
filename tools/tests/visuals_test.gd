extends Node
## Verifie l'animation des roues du modele charge.
##
## Une capture d'ecran ne dit pas si une roue tourne : il faut mesurer sa
## rotation. Ce banc verifie que les quatre roues sont reconnues, qu'elles
## tournent avec la vitesse, et que seules celles de l'avant braquent.
##
## Lancer : godot --headless res://tools/tests/visuals_test.tscn

const TRACK_SCENE: String = "res://src/track/test_track.tscn"

var _track: Node3D = null
var _vehicle: Vehicle = null
var _failures: int = 0
var _warmup: int = 0


func _ready() -> void:
	var scene: PackedScene = load(TRACK_SCENE) as PackedScene
	_track = scene.instantiate() as Node3D
	add_child(_track)
	_vehicle = Vehicle.new()
	_vehicle.configure(1, "Essai", 0, Vehicle.Mode.AUTHORITY, _track)
	add_child(_vehicle)
	_vehicle.setup_visuals(false)
	_vehicle.place_at(_track.call("get_spawn_transform", 0))


func _physics_process(delta: float) -> void:
	_warmup += 1
	if _warmup < 4:
		return
	set_physics_process(false)
	_run(delta)


func _run(delta: float) -> void:
	print("--- Animation des roues ---")
	var visuals: VehicleVisuals = _vehicle.get_visuals()
	var wheels: Array[Node3D] = visuals.get_wheels()

	print("  roues trouvees : %d" % wheels.size())
	if wheels.is_empty():
		print("  (modele sans roues separees : rien a animer)")
		_finish()
		return
	if wheels.size() != 4:
		_fail("%d roues au lieu de 4" % wheels.size())
		_finish()
		return

	for index: int in wheels.size():
		var wheel: Node3D = wheels[index]
		print("    %-10s position %+.2f %+.2f %+.2f"
			% [wheel.name, wheel.position.x, wheel.position.y, wheel.position.z])

	# --- Roulement : les roues doivent tourner quand la voiture avance --------
	var before: float = wheels[0].rotation.x
	_drive(InputFrame.create(0, 1.0, 0.0, 0.0, false, false), 45, delta)
	var spin: float = absf(wrapf(wheels[0].rotation.x - before, -PI, PI))
	print("  rotation apres 0,75 s a plein gaz : %.2f rad" % spin)
	if spin < 0.3:
		_fail("les roues ne tournent pas (%.3f rad)" % spin)

	# --- Braquage : l'avant braque, l'arriere non ----------------------------
	_drive(InputFrame.create(0, 0.6, 0.0, 1.0, false, false), 40, delta)
	var front: float = absf(wheels[0].rotation.y)
	var rear: float = absf(wheels[2].rotation.y)
	print("  braquage a fond : avant %.1f deg, arriere %.1f deg"
		% [rad_to_deg(front), rad_to_deg(rear)])
	if front < deg_to_rad(8.0):
		_fail("les roues avant ne braquent pas (%.1f deg)" % rad_to_deg(front))
	if rear > deg_to_rad(0.5):
		_fail("les roues arriere braquent alors qu'elles ne devraient pas")

	# --- Sens du braquage ----------------------------------------------------
	# Braquer a droite doit tourner les roues vers la droite, soit un angle
	# negatif dans le repere de Godot.
	if wheels[0].rotation.y > 0.0:
		_fail("les roues braquent du mauvais cote")
	else:
		print("  sens du braquage : correct")

	_finish()


func _drive(input: InputFrame, steps: int, delta: float) -> void:
	for _index: int in steps:
		_vehicle.simulate(input, delta)
		_vehicle.get_visuals().update_visual(_vehicle.state, delta)


func _fail(message: String) -> void:
	printerr("ECHEC " + message)
	_failures += 1


func _finish() -> void:
	print("---------------------------")
	if _failures == 0:
		print("Animation des roues : tous les tests passent.")
	else:
		printerr("Animation des roues : %d test(s) en echec." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
