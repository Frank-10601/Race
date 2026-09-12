class_name StateInterpolator
extends RefCounted
## Affichage fluide des voitures des AUTRES joueurs.
##
## Le serveur envoie l'etat 20 fois par seconde, l'ecran affiche 60 fois ou
## plus. Rendre directement le dernier etat recu donnerait des a-coups. On
## affiche donc ces voitures legerement DANS LE PASSE (`interpolation_delay`,
## 100 ms par defaut, soit deux paquets), ce qui garantit d'avoir toujours deux
## etats encadrant l'instant voulu.
##
## L'interpolation est cubique (Hermite) et non lineaire : a 20 Hz, une
## interpolation lineaire coupe les virages en cordes parfaitement visibles.
## Hermite utilise aussi la VITESSE de chaque etat, donc respecte la courbure
## de la trajectoire.
##
## Si plus rien n'arrive (paquet perdu, pic de latence), on extrapole brievement
## sur la derniere vitesse connue, puis on fige : mieux vaut une voiture qui
## s'arrete qu'une voiture qui part en ligne droite dans le decor.

## Nombre d'etats conserves. 24 couvrent plus d'une seconde a 20 Hz.
const CAPACITY: int = 24

var _states: Array[VehicleState] = []
var _times: PackedFloat64Array = PackedFloat64Array()
var _count: int = 0


## Ajoute un etat date par l'horloge serveur. Les etats arrives dans le
## desordre ou trop vieux sont ignores.
func push(state: VehicleState, server_time: float) -> void:
	if _count > 0 and server_time <= _times[_count - 1]:
		return
	if _count == CAPACITY:
		_states.pop_front()
		_times.remove_at(0)
		_count -= 1
	_states.append(state)
	_times.append(server_time)
	_count += 1


func clear() -> void:
	_states.clear()
	_times.clear()
	_count = 0


func is_empty() -> bool:
	return _count == 0


## Etat a afficher a l'instant `render_time` (horloge serveur, deja retardee).
func sample(render_time: float) -> VehicleState:
	if _count == 0:
		return null
	if _count == 1:
		return _states[0]

	# Avant le plus ancien etat connu : on fige sur celui-la.
	if render_time <= _times[0]:
		return _states[0]

	# Apres le plus recent : extrapolation courte, puis arret.
	if render_time >= _times[_count - 1]:
		return _extrapolate(render_time)

	# Cas normal : chercher l'intervalle encadrant.
	var index: int = _count - 2
	while index > 0 and _times[index] > render_time:
		index -= 1
	return _hermite(_states[index], _states[index + 1],
		_times[index], _times[index + 1], render_time)


## Une remise en piste ne doit jamais etre interpolee : entre l'ancienne et la
## nouvelle position, la voiture traverserait tout le circuit.
func _same_teleport(a: VehicleState, b: VehicleState) -> bool:
	return a.teleport_id == b.teleport_id


## Interpolation cubique de Hermite : respecte position ET vitesse aux deux
## extremites, donc la courbure de la trajectoire.
func _hermite(from: VehicleState, to: VehicleState,
		time_from: float, time_to: float, at: float) -> VehicleState:
	var span: float = float(time_to - time_from)
	if span <= 0.0001:
		return to
	if not _same_teleport(from, to):
		return to

	var t: float = clampf(float(at - time_from) / span, 0.0, 1.0)
	var t2: float = t * t
	var t3: float = t2 * t

	var h00: float = 2.0 * t3 - 3.0 * t2 + 1.0
	var h10: float = t3 - 2.0 * t2 + t
	var h01: float = -2.0 * t3 + 3.0 * t2
	var h11: float = t3 - t2

	var result: VehicleState = VehicleState.new()
	result.position = from.position * h00 + from.velocity * (h10 * span) \
		+ to.position * h01 + to.velocity * (h11 * span)
	result.velocity = from.velocity.lerp(to.velocity, t)
	result.yaw = lerp_angle(from.yaw, to.yaw, t)
	result.up = from.up.lerp(to.up, t).normalized()
	result.drift = lerpf(from.drift, to.drift, t)
	result.steer_smoothed = lerpf(from.steer_smoothed, to.steer_smoothed, t)
	result.grounded = to.grounded
	result.teleport_id = to.teleport_id
	return result


## Prolongement en ligne droite quand plus aucun etat n'arrive, borne par
## `max_extrapolation`.
func _extrapolate(render_time: float) -> VehicleState:
	var last: VehicleState = _states[_count - 1]
	var ahead: float = clampf(float(render_time - _times[_count - 1]), 0.0, Tuning.max_extrapolation)
	if ahead <= 0.0:
		return last
	var result: VehicleState = last.copy()
	result.position = last.position + last.velocity * ahead
	return result
