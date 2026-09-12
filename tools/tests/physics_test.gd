extends Node
## Banc d'essai de la physique du vehicule, sans clavier ni affichage.
##
## Lancer : godot --headless res://tools/tests/physics_test.tscn
##
## Le test le plus important est celui du DETERMINISME : si rejouer la meme
## suite d'entrees depuis le meme etat ne redonne pas exactement le meme
## resultat, la reconciliation reseau est impossible et toute la phase 0
## s'ecroule. Les autres tests verifient que la voiture se comporte comme
## annonce dans `tuning.cfg`.

const TRACK_SCENE: String = "res://src/track/test_track.tscn"

## Surface plate a l'ecart du trace, pour mesurer le modele et non le circuit.
const TEST_AREA: Vector3 = Vector3(-200.0, 0.0, -200.0)

var _track: Node3D = null
var _vehicle: Vehicle = null
var _failures: int = 0
var _warmup: int = 0


func _ready() -> void:
	var scene: PackedScene = load(TRACK_SCENE) as PackedScene
	_track = scene.instantiate() as Node3D
	add_child(_track)

	_vehicle = Vehicle.new()
	_vehicle.configure(1, "Test", 0, Vehicle.Mode.AUTHORITY, _track)
	add_child(_vehicle)
	_vehicle.place_at(_track.call("get_spawn_transform", 0))


func _physics_process(_delta: float) -> void:
	# L'espace physique doit etre construit avant le premier raycast.
	_warmup += 1
	if _warmup < 4:
		return
	set_physics_process(false)
	_run_all()


func _run_all() -> void:
	print("--- Banc d'essai de la physique ---")
	_test_rest_height()
	_test_acceleration()
	_test_top_speed()
	_test_braking()
	_test_steering()
	_test_handbrake_drift()
	_test_grip_recovery()
	_test_determinism()
	_test_ramps()
	_test_walls()

	print("-----------------------------------")
	if _failures == 0:
		print("Physique : tous les tests passent.")
	else:
		printerr("Physique : %d test(s) en echec." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

## Au repos, la voiture doit se stabiliser a la hauteur de caisse prevue.
func _test_rest_height() -> void:
	var state: VehicleState = _fresh_state()
	state = _run(state, _make_input(0.0, 0.0, 0.0, false), 120)
	var height: float = state.position.y
	_expect("hauteur de repos", height, Tuning.ride_height, 0.06)


## Depart arrete, plein gaz : la voiture doit partir franchement.
func _test_acceleration() -> void:
	var state: VehicleState = _fresh_state()
	state = _run(state, _make_input(1.0, 0.0, 0.0, false), 60)  # 1 seconde
	var speed: float = state.get_forward_speed()
	print("  acceleration : %.1f m/s apres 1 s (%.0f km/h)" % [speed, speed * 3.6])
	if speed < Tuning.engine_acceleration * 0.6:
		_fail("acceleration trop molle : %.1f m/s apres 1 s" % speed)


## Plein gaz prolonge : la vitesse doit se stabiliser pres de `max_speed`.
func _test_top_speed() -> void:
	# En zone degagee : depuis la grille de depart, la voiture rencontrerait les
	# rampes et la mesure ne voudrait plus rien dire.
	var state: VehicleState = _launched_state(0.0)
	state = _run(state, _make_input(1.0, 0.0, 0.0, false), 60 * 12)
	var speed: float = state.get_forward_speed()
	print("  vitesse de pointe : %.1f m/s (%.0f km/h)" % [speed, speed * 3.6])
	if speed < Tuning.max_speed * 0.85:
		_fail("vitesse de pointe trop basse : %.1f m/s pour un maximum de %.1f"
			% [speed, Tuning.max_speed])
	if speed > Tuning.max_speed * 1.02:
		_fail("vitesse de pointe depassee : %.1f m/s" % speed)


## Le frein doit mordre nettement plus fort que le frein moteur.
func _test_braking() -> void:
	var launched: VehicleState = _launched_state(35.0)
	var before: float = launched.get_forward_speed()
	var braked: VehicleState = _run(launched, _make_input(0.0, 1.0, 0.0, false), 30)
	var lost: float = before - braked.get_forward_speed()
	print("  freinage : %.1f m/s perdus en 0,5 s" % lost)
	if lost < Tuning.brake_force * 0.3:
		_fail("freinage insuffisant : %.1f m/s perdus" % lost)


## Braquage a vitesse de croisiere : le cap doit changer nettement.
func _test_steering() -> void:
	var launched: VehicleState = _launched_state(30.0)
	var before: float = launched.yaw
	var turned: VehicleState = _run(launched, _make_input(1.0, 0.0, 1.0, false), 60)
	var change: float = rad_to_deg(absf(wrapf(turned.yaw - before, -PI, PI)))
	print("  virage : %.0f degres en 1 s" % change)
	# En arcade, le virage doit etre NET. En dessous, la voiture parait lourde.
	if change < 45.0:
		_fail("braquage trop faible : %.0f degres en 1 s a 108 km/h" % change)

	# Et surtout dans le BON SENS : braquer a droite doit envoyer la voiture a
	# droite. Au depart, la piste pointe vers -Z, donc la droite est vers +X.
	var sideways: float = turned.position.x - launched.position.x
	print("  sens du virage : %+.1f m lateralement en braquant a droite" % sideways)
	if sideways <= 0.0:
		_fail("braquer a droite fait partir la voiture a gauche (%+.1f m)" % sideways)


## Frein a main : la voiture doit partir en glisse, c'est-a-dire que sa
## trajectoire doit s'ecarter de son nez.
func _test_handbrake_drift() -> void:
	var launched: VehicleState = _launched_state(30.0)
	var drifting: VehicleState = _run(launched, _make_input(1.0, 0.0, 1.0, true), 90)
	var slip: float = _slip_angle(drifting)
	print("  derapage : glisse %.2f, angle de derive %.0f degres, au sol : %s"
		% [drifting.drift, slip, "oui" if drifting.grounded else "non"])
	if not drifting.grounded:
		_fail("la voiture a quitte le sol pendant le test de derapage")
	if drifting.drift < 0.9:
		_fail("le frein a main ne declenche pas la glisse : %.2f" % drifting.drift)
	if slip < 10.0:
		_fail("angle de derive trop faible : %.0f degres" % slip)
	# Un derapage doit rester maitrisable : au-dela, c'est un tete-a-queue.
	if slip > 45.0:
		_fail("la voiture part en tete-a-queue : %.0f degres de derive" % slip)


## Apres relachement, l'adherence doit revenir progressivement, pas d'un coup.
func _test_grip_recovery() -> void:
	var launched: VehicleState = _launched_state(30.0)
	var drifting: VehicleState = _run(launched, _make_input(1.0, 0.0, 1.0, true), 90)
	var partial: VehicleState = _run(drifting, _make_input(1.0, 0.0, 0.4, false), 6)
	var recovered: VehicleState = _run(drifting, _make_input(1.0, 0.0, 0.4, false), 60)
	print("  reprise d'adherence : %.2f apres 0,1 s, %.2f apres 1 s"
		% [partial.drift, recovered.drift])
	if partial.drift <= 0.05:
		_fail("reprise d'adherence trop brutale : la glisse tombe a %.2f en 0,1 s" % partial.drift)
	if recovered.drift > 0.1:
		_fail("la voiture ne reprend pas son adherence : %.2f apres 1 s" % recovered.drift)


## LE test critique : rejouer la meme suite d'entrees depuis le meme etat doit
## redonner exactement le meme resultat. Sans cela, pas de reconciliation.
func _test_determinism() -> void:
	var inputs: Array[InputFrame] = []
	for index: int in 180:
		# Suite variee : gaz, braquage alterne, frein a main par moments.
		var steer: float = sin(float(index) * 0.09)
		var handbrake: bool = index > 80 and index < 130
		inputs.append(_make_input(1.0, 0.0, steer, handbrake))

	var first: VehicleState = _replay(_fresh_state(), inputs)
	var second: VehicleState = _replay(_fresh_state(), inputs)

	var position_gap: float = first.position.distance_to(second.position)
	var yaw_gap: float = absf(wrapf(first.yaw - second.yaw, -PI, PI))
	print("  determinisme : ecart %.9f m et %.9f rad apres 180 pas"
		% [position_gap, yaw_gap])
	if position_gap > 0.0 or yaw_gap > 0.0:
		_fail("la simulation n'est pas deterministe : ecart de %.9f m" % position_gap)

	# Et un replay partiel, comme le fait la reconciliation : simuler 100 pas,
	# repartir du pas 40 et rejouer les 60 suivants doit retomber au meme point.
	var checkpoint: VehicleState = null
	var direct: VehicleState = _fresh_state()
	for index: int in 100:
		direct = _vehicle.physics.step(direct, inputs[index], Tuning.physics_delta)
		if index == 39:
			checkpoint = direct.copy()
	var replayed: VehicleState = checkpoint
	for index: int in range(40, 100):
		replayed = _vehicle.physics.step(replayed, inputs[index], Tuning.physics_delta)
	var replay_gap: float = direct.position.distance_to(replayed.position)
	print("  replay partiel : ecart %.9f m sur 60 pas rejoues" % replay_gap)
	if replay_gap > 0.0:
		_fail("le replay partiel derive de %.9f m" % replay_gap)


## La voiture doit FRANCHIR les rampes de la ligne droite, pas s'y arreter.
## Une rampe inclinee dans le mauvais sens presente une face verticale : rien ne
## le signale a la lecture du code, seul un essai le revele.
func _test_ramps() -> void:
	var transform: Transform3D = _track.call("get_spawn_transform", 0)
	var state: VehicleState = VehicleState.create_at(
		transform.origin + Vector3.UP * Tuning.spawn_height, transform.basis.get_euler().y)
	state = _run(state, _make_input(0.0, 0.0, 0.0, false), 12)

	# Plein gaz en ligne droite sur 6 s : de quoi passer les trois rampes.
	var travelled_start: float = state.position.z
	var airborne: int = 0
	var minimum_speed: float = 1000.0
	for step: int in 360:
		state = _vehicle.physics.step(state, _make_input(1.0, 0.0, 0.0, false), Tuning.physics_delta)
		if not state.grounded:
			airborne += 1
		# On ignore le tout debut, ou la voiture est encore a l'arret.
		if step > 60:
			minimum_speed = minf(minimum_speed, state.get_speed())
	var distance: float = absf(state.position.z - travelled_start)
	print("  rampes : %.0f m parcourus, %d pas en l'air, vitesse minimale %.0f km/h"
		% [distance, airborne, minimum_speed * 3.6])

	if distance < 180.0:
		_fail("la voiture n'avance pas : %.0f m en 6 s (obstacle sur la ligne droite ?)" % distance)
	if airborne < 10:
		_fail("aucun saut detecte : les rampes ne font pas decoller la voiture")
	if minimum_speed * 3.6 < 40.0:
		_fail("la voiture est presque arretee (%.0f km/h) : elle a percute une rampe"
			% (minimum_speed * 3.6))


## Les murs doivent arreter la voiture. Depuis que le sol et les murs sont sur
## des couches distinctes, c'est le seul obstacle que le corps de collision
## percute encore : si cette separation etait mal faite, la voiture traverserait
## le decor sans rien heurter.
func _test_walls() -> void:
	var transform: Transform3D = _track.call("get_spawn_transform", 0)
	# Face au mur de droite, lancee a pleine vitesse perpendiculairement.
	var state: VehicleState = VehicleState.create_at(
		transform.origin + Vector3.UP * Tuning.spawn_height,
		transform.basis.get_euler().y - PI * 0.5)
	state = _run(state, _make_input(0.0, 0.0, 0.0, false), 12)
	state.velocity = -state.get_basis().z * 40.0

	var start_x: float = state.position.x
	state = _run(state, _make_input(1.0, 0.0, 0.0, false), 90)
	var travelled: float = state.position.x - start_x
	print("  murs : %.1f m parcourus vers le mur (piste large de 24 m)" % travelled)

	# Depuis x = -4,5, le mur de droite est a environ 16,5 m. La voiture doit
	# etre arretee avant, pas continuer sur des dizaines de metres.
	if travelled > 22.0:
		_fail("la voiture traverse le mur : %.1f m parcourus" % travelled)


# --- Utilitaires -------------------------------------------------------------

func _fresh_state() -> VehicleState:
	var transform: Transform3D = _track.call("get_spawn_transform", 0)
	return VehicleState.create_at(
		transform.origin + Vector3.UP * Tuning.spawn_height,
		transform.basis.get_euler().y)


## Voiture lancee a la vitesse voulue, posee au sol, sur une grande surface
## plate A L'ECART du trace.
##
## Deux raisons de ne pas tester sur la piste : une phase d'acceleration y
## conduirait la voiture jusqu'aux rampes, et un virage a fond l'enverrait dans
## un mur. Les mesures refleteraient alors la geometrie du circuit et non le
## modele de conduite, qui est ce qu'on veut verifier ici.
func _launched_state(speed: float) -> VehicleState:
	var state: VehicleState = VehicleState.create_at(
		TEST_AREA + Vector3.UP * Tuning.spawn_height, 0.0)
	state = _run(state, _make_input(0.0, 0.0, 0.0, false), 16)
	state.velocity = -state.get_basis().z * speed
	return state


func _make_input(throttle: float, brake: float, steer: float, handbrake: bool) -> InputFrame:
	return InputFrame.create(0, throttle, brake, steer, handbrake, false)


## Applique la meme entree pendant `steps` pas.
func _run(from: VehicleState, input: InputFrame, steps: int) -> VehicleState:
	var state: VehicleState = from.copy()
	for _index: int in steps:
		state = _vehicle.physics.step(state, input, Tuning.physics_delta)
	return state


func _replay(from: VehicleState, inputs: Array[InputFrame]) -> VehicleState:
	var state: VehicleState = from.copy()
	for input: InputFrame in inputs:
		state = _vehicle.physics.step(state, input, Tuning.physics_delta)
	return state


## Angle entre le nez de la voiture et sa trajectoire reelle, en degres.
func _slip_angle(state: VehicleState) -> float:
	var planar: Vector3 = Vector3(state.velocity.x, 0.0, state.velocity.z)
	if planar.length() < 1.0:
		return 0.0
	var forward: Vector3 = -state.get_basis().z
	var flat_forward: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
	return rad_to_deg(flat_forward.angle_to(planar.normalized()))


func _expect(label: String, actual: float, expected: float, tolerance: float) -> void:
	if absf(actual - expected) > tolerance:
		_fail("%s : obtenu %.3f, attendu %.3f (tolerance %.3f)"
			% [label, actual, expected, tolerance])
	else:
		print("  %s : %.3f" % [label, actual])


func _fail(message: String) -> void:
	printerr("ECHEC " + message)
	_failures += 1
