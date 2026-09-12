class_name PredictionBuffer
extends RefCounted
## Prediction et reconciliation de la voiture du joueur local.
##
## LE POINT CRITIQUE DE LA PHASE 0. Dans un jeu de course, le moindre retard a
## la direction se sent immediatement. Le client ne peut donc pas attendre la
## reponse du serveur : il applique ses entrees tout de suite et corrige apres
## coup.
##
## Fonctionnement :
##   1. A chaque pas, le client simule son entree et archive (sequence, entree,
##      etat obtenu).
##   2. Quand l'etat serveur arrive, il est date d'une sequence deja traitee par
##      le serveur. On compare cet etat a ce qu'on avait predit pour CETTE
##      sequence-la — jamais a l'etat courant, qui a 150 ms d'avance.
##   3. Si l'ecart est negligeable, on ne touche a rien.
##   4. Sinon on repart de l'etat serveur et on rejoue toutes les entrees
##      emises depuis. Le resultat est exact, car `VehiclePhysics.step()` est
##      deterministe et la piste est statique.
##
## Historique circulaire indexe par `sequence % taille` : insertion et lecture
## en temps constant, aucune allocation pendant la partie.

## Statistiques du dernier appel a `reconcile()`, lues par le panneau F3.
var last_replay_count: int = 0
var last_position_error: float = 0.0
var corrections_applied: int = 0

var _size: int = 128
var _sequences: PackedInt32Array = PackedInt32Array()
var _inputs: Array[InputFrame] = []
var _states: Array[VehicleState] = []
var _newest_sequence: int = 0


func _init(size: int = 128) -> void:
	resize(size)


func resize(size: int) -> void:
	_size = maxi(size, 8)
	_sequences.resize(_size)
	_sequences.fill(-1)
	_inputs.resize(_size)
	_states.resize(_size)
	_newest_sequence = 0


func clear() -> void:
	_sequences.fill(-1)
	_newest_sequence = 0
	last_replay_count = 0
	last_position_error = 0.0


## Archive une entree et l'etat qu'elle a produit.
func record(sequence: int, input: InputFrame, state: VehicleState) -> void:
	var slot: int = sequence % _size
	_sequences[slot] = sequence
	_inputs[slot] = input
	_states[slot] = state
	_newest_sequence = maxi(_newest_sequence, sequence)


## Compare l'etat serveur a la prediction faite pour la meme sequence, et
## rejoue si necessaire.
##
## Retourne :
##   `state`      — le nouvel etat courant, ou `null` si aucune correction
##   `moved_from` — position avant correction (pour la resorption visuelle)
##   `yaw_from`   — orientation avant correction
func reconcile(server_state: VehicleState, acked_sequence: int,
		current_state: VehicleState, physics: VehiclePhysics, delta: float) -> Dictionary:
	last_replay_count = 0

	var slot: int = acked_sequence % _size
	var has_prediction: bool = _sequences[slot] == acked_sequence

	if has_prediction:
		var predicted: VehicleState = _states[slot]
		last_position_error = predicted.position_error(server_state)
		var rotation_error: float = predicted.rotation_error(server_state)
		if last_position_error < Tuning.reconciliation_position_threshold \
				and rotation_error < Tuning.reconciliation_rotation_rad:
			# Prediction exacte a la tolerance pres : ne rien faire, surtout pas
			# rejouer. C'est le cas le plus frequent, et le moins couteux.
			return {}
	else:
		# Sequence inconnue (connexion, remise en piste, historique depasse) :
		# l'etat serveur fait foi sans discussion.
		last_position_error = current_state.position_error(server_state)

	var before_position: Vector3 = current_state.position
	var before_yaw: float = current_state.yaw

	# Replay : on repart du serveur et on rejoue tout ce qu'il n'a pas encore vu.
	var state: VehicleState = server_state.copy()
	var sequence: int = acked_sequence + 1
	while sequence <= _newest_sequence:
		var replay_slot: int = sequence % _size
		if _sequences[replay_slot] != sequence:
			# Entree perdue de l'historique : on s'arrete la plutot que de
			# rejouer avec une entree fausse.
			break
		state = physics.step(state, _inputs[replay_slot], delta)
		_states[replay_slot] = state
		last_replay_count += 1
		sequence += 1

	corrections_applied += 1
	return {
		"state": state,
		"moved_from": before_position,
		"yaw_from": before_yaw,
	}


## Entrees pas encore confirmees par le serveur, plus recentes en dernier.
## Renvoyees a chaque paquet pour qu'une entree perdue soit rattrapee par le
## paquet suivant, sans accuse de reception.
func get_unacked_inputs(acked_sequence: int, maximum: int) -> Array[InputFrame]:
	var frames: Array[InputFrame] = []
	var first: int = maxi(acked_sequence + 1, _newest_sequence - maximum + 1)
	var sequence: int = maxi(first, 1)
	while sequence <= _newest_sequence:
		var slot: int = sequence % _size
		if _sequences[slot] == sequence:
			frames.append(_inputs[slot])
		sequence += 1
	return frames
