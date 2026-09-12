class_name VehicleRespawn
extends RefCounted
## Surveille un vehicule et decide quand le remettre en piste.
##
## Cette decision appartient au SERVEUR : c'est lui qui simule, lui qui tranche.
## Le client l'apprend par le changement de `teleport_id` dans l'etat recu.
##
## Quatre motifs :
##   1. la voiture est retournee depuis plus de `stuck_time` ;
##   2. elle est immobile HORS PISTE depuis plus de `stuck_time` — a l'arret sur
##      la piste, on laisse le joueur tranquille ;
##   3. elle est tombee sous `fall_height` : immediat, sans attendre ;
##   4. le joueur a appuye sur R : immediat.

## Frequence de test de la position par rapport a la piste, en secondes.
## Inutile de la recalculer a chaque image : elle ne sert qu'a l'arret.
const TRACK_CHECK_INTERVAL: float = 0.25

var _upside_down_timer: float = 0.0
var _stuck_timer: float = 0.0
var _track_check_timer: float = 0.0
var _off_track: bool = false

## Motif de la derniere remise en piste, affiche par le panneau F3.
var last_reason: String = ""


func reset() -> void:
	_upside_down_timer = 0.0
	_stuck_timer = 0.0
	_track_check_timer = 0.0
	_off_track = false


## `track` peut valoir `null` : la detection hors piste est alors ignoree.
func should_respawn(state: VehicleState, input: InputFrame, track: Node, delta: float) -> bool:
	if input != null and input.respawn:
		last_reason = "demande du joueur"
		return true

	if state.position.y < Tuning.fall_height:
		last_reason = "chute hors de la piste"
		return true

	# 1. Retournement : l'axe haut de la voiture s'ecarte trop de la verticale.
	if state.up.dot(Vector3.UP) < Tuning.upside_down_dot:
		_upside_down_timer += delta
		if _upside_down_timer >= Tuning.stuck_time:
			last_reason = "vehicule retourne"
			return true
	else:
		_upside_down_timer = 0.0

	# 2. Immobilite hors piste.
	if state.velocity.length() < Tuning.stuck_speed:
		_track_check_timer -= delta
		if _track_check_timer <= 0.0:
			_track_check_timer = TRACK_CHECK_INTERVAL
			_off_track = track != null and track.has_method("is_on_track") \
				and not bool(track.call("is_on_track", state.position))
		if _off_track:
			_stuck_timer += delta
			if _stuck_timer >= Tuning.stuck_time:
				last_reason = "immobilise hors piste"
				return true
		else:
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
		_track_check_timer = 0.0
		_off_track = false

	return false
