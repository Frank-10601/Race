class_name Vehicle
extends CharacterBody3D
## Un vehicule dans la course.
##
## Le meme noeud sert dans trois roles differents, et c'est volontaire : la
## simulation doit etre rigoureusement identique partout, sinon la prediction
## client ne peut pas fonctionner.
##
##   AUTHORITY     — le serveur (ou le jeu solo). Simule pour de vrai, a partir
##                   des entrees recues. C'est la verite.
##   PREDICTED     — sur un client, SA propre voiture. Simule immediatement ses
##                   entrees, puis se corrige a l'arrivee de l'etat serveur.
##   INTERPOLATED  — sur un client, la voiture des AUTRES. Ne simule rien, se
##                   contente d'interpoler entre les etats recus.
##
## Ce noeud ignore tout des RPC : c'est `RaceWorld` qui route les entrees et les
## etats. Il ne sait que simuler, predire ou interpoler.

signal respawned(reason: String)

enum Mode { AUTHORITY, PREDICTED, INTERPOLATED }

## Couche du vehicule. Il ne percute QUE le decor : les collisions entre
## joueurs sont hors perimetre de la phase 0 (elles arrivent en phase 5).
const LAYER_VEHICLE: int = 2
const MASK_WORLD: int = 1

## Nombre d'entrees renvoyees a chaque paquet, pour rattraper une perte.
const INPUT_REDUNDANCY: int = 3

var peer_id: int = 0
var player_name: String = ""
var color_index: int = 0
var mode: Mode = Mode.AUTHORITY

## Etat courant de la simulation. Toujours la verite locale de ce noeud.
var state: VehicleState = VehicleState.new()
## Derniere entree appliquee, conservee pour le panneau de debogage.
var last_input: InputFrame = InputFrame.neutral(0)
## Derniere sequence d'entree que le serveur declare avoir traitee.
var acked_sequence: int = 0

var physics: VehiclePhysics = VehiclePhysics.new()
var prediction: PredictionBuffer = null
var interpolator: StateInterpolator = null
var respawn: VehicleRespawn = null

var _visuals: VehicleVisuals = null
var _track: Node = null
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _sequence: int = 0


func _ready() -> void:
	collision_layer = LAYER_VEHICLE
	collision_mask = MASK_WORLD
	# Le corps ne sert qu'aux collisions : le rendu vit dans `VehicleVisuals`,
	# qui est en `top_level` pour pouvoir absorber les corrections reseau.
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = VehiclePhysics.CHASSIS_SIZE
	shape.shape = box
	add_child(shape)

	physics.setup(self)


## A appeler juste apres l'instanciation, avant l'ajout a l'arbre.
func configure(p_peer_id: int, p_player_name: String, p_color_index: int,
		p_mode: Mode, p_track: Node) -> void:
	peer_id = p_peer_id
	player_name = p_player_name
	color_index = p_color_index
	mode = p_mode
	_track = p_track

	if mode == Mode.PREDICTED:
		prediction = PredictionBuffer.new(Tuning.input_history_size)
	elif mode == Mode.INTERPOLATED:
		interpolator = StateInterpolator.new()
	if mode == Mode.AUTHORITY:
		respawn = VehicleRespawn.new()


func setup_visuals(is_local_player: bool) -> void:
	_visuals = VehicleVisuals.new()
	_visuals.name = "Visuals"
	add_child(_visuals)
	_visuals.setup(VehicleFactory.get_player_color(color_index), player_name)
	_visuals.set_name_tag_visible(not is_local_player)
	_visuals.sync_to_state(state)


## Place le vehicule sur la grille de depart.
func place_at(transform: Transform3D) -> void:
	_spawn_transform = transform
	state = VehicleState.create_at(
		transform.origin + Vector3.UP * Tuning.spawn_height,
		transform.basis.get_euler().y)
	global_position = state.position
	if _visuals != null:
		_visuals.sync_to_state(state)


# --- Simulation --------------------------------------------------------------

## Avance la simulation d'un pas avec l'entree donnee. Utilise par le serveur
## et par le jeu solo.
func simulate(input: InputFrame, delta: float) -> void:
	last_input = input
	if respawn != null and respawn.should_respawn(state, input, _track, delta):
		var reason: String = respawn.last_reason
		do_respawn()
		respawned.emit(reason)
		return
	state = physics.step(state, input, delta)
	_sync_body()


## Avance la simulation ET archive l'entree pour pouvoir la rejouer.
## Utilise par le client pour sa propre voiture.
func predict(input: InputFrame, delta: float) -> void:
	last_input = input
	state = physics.step(state, input, delta)
	prediction.record(input.sequence, input, state)
	_sync_body()


## Prochain numero de sequence a emettre.
func next_sequence() -> int:
	_sequence += 1
	return _sequence


## Applique un etat recu du serveur.
## Sur la voiture locale : reconciliation. Sur les autres : mise en file
## d'interpolation.
func apply_server_state(server_state: VehicleState, p_acked_sequence: int,
		server_time: float, delta: float) -> void:
	match mode:
		Mode.PREDICTED:
			acked_sequence = p_acked_sequence
			var result: Dictionary = prediction.reconcile(
				server_state, p_acked_sequence, state, physics, delta)
			if result.is_empty():
				return
			var corrected: VehicleState = result["state"]
			if _visuals != null:
				if corrected.teleport_id != state.teleport_id:
					# Remise en piste : saut voulu, on ne le lisse pas.
					_visuals.sync_to_state(corrected)
				else:
					_visuals.absorb_correction(
						result["moved_from"], corrected.position,
						result["yaw_from"], corrected.yaw)
			state = corrected
			_sync_body()
		Mode.INTERPOLATED:
			interpolator.push(server_state, server_time)
		Mode.AUTHORITY:
			pass  # le serveur ne recoit d'etat de personne


## Met a jour une voiture distante a l'instant d'affichage demande.
func update_interpolated(render_time: float) -> void:
	if interpolator == null or interpolator.is_empty():
		return
	var sampled: VehicleState = interpolator.sample(render_time)
	if sampled == null:
		return
	state = sampled
	global_position = state.position


## Remet le vehicule sur la grille. Decision du serveur uniquement.
func do_respawn() -> void:
	state = physics.teleport(state, _spawn_transform.origin + Vector3.UP * Tuning.spawn_height,
		_spawn_transform.basis.get_euler().y)
	if respawn != null:
		respawn.reset()
	_sync_body()


## Entrees pas encore confirmees, a renvoyer au serveur.
func get_pending_inputs() -> Array[InputFrame]:
	if prediction == null:
		return []
	return prediction.get_unacked_inputs(acked_sequence, INPUT_REDUNDANCY)


func _process(delta: float) -> void:
	if _visuals == null:
		return
	if mode == Mode.INTERPOLATED:
		# Les voitures distantes n'ont pas de pas de physique : leur transform
		# est deja continue, on la recopie telle quelle.
		_visuals.sync_to_state(state)
	_visuals.update_visual(state, delta)


## Recopie l'etat simule dans le noeud physique et prepare l'image suivante.
func _sync_body() -> void:
	global_position = state.position
	velocity = state.velocity
	if _visuals != null:
		_visuals.sync_to_state(state)


func get_speed_kmh() -> float:
	return state.get_speed() * 3.6


func get_visuals() -> VehicleVisuals:
	return _visuals
