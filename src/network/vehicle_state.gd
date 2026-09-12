class_name VehicleState
extends RefCounted
## Etat complet d'un vehicule a un instant donne.
##
## Deux roles, et c'est volontaire qu'il n'y en ait qu'une seule classe :
##   1. etat de simulation : `VehiclePhysics.step()` transforme un etat en le
##      suivant. Tout ce qui possede de l'inertie doit figurer ici, sinon la
##      reconciliation client derivera.
##   2. etat reseau : le serveur le diffuse aux clients.
##
## Encodage : 14 nombres en virgule flottante 32 bits, soit 56 octets par
## vehicule. A 12 joueurs et 20 Hz, cela represente environ 13 ko/s.

## Nombre de valeurs encodees.
const ENCODED_FLOATS: int = 14

## Position du centre du chassis, en coordonnees monde.
var position: Vector3 = Vector3.ZERO
## Orientation autour de l'axe vertical, en radians.
var yaw: float = 0.0
## Vitesse, en coordonnees monde (m/s).
var velocity: Vector3 = Vector3.ZERO
## Axe "haut" du vehicule, lisse vers la normale du sol. Porte l'inclinaison.
var up: Vector3 = Vector3.UP
## Quantite de derapage en cours, de 0 (adherence totale) a 1 (glisse complete).
var drift: float = 0.0
## Braquage lisse, de -1 a 1. Possede de l'inertie, donc fait partie de l'etat.
var steer_smoothed: float = 0.0
## Le vehicule touche-t-il le sol ?
var grounded: bool = true
## Incremente a chaque remise en piste. Un changement signale au client un saut
## voulu, qu'il ne doit pas lisser visuellement.
var teleport_id: int = 0


static func create_at(p_position: Vector3, p_yaw: float) -> VehicleState:
	var state: VehicleState = VehicleState.new()
	state.position = p_position
	state.yaw = p_yaw
	return state


func copy() -> VehicleState:
	var state: VehicleState = VehicleState.new()
	state.position = position
	state.yaw = yaw
	state.velocity = velocity
	state.up = up
	state.drift = drift
	state.steer_smoothed = steer_smoothed
	state.grounded = grounded
	state.teleport_id = teleport_id
	return state


## Repere complet du vehicule, reconstruit a partir du lacet et de l'axe haut.
func get_basis() -> Basis:
	return basis_from(yaw, up)


## Construit un repere orthonorme : le vehicule pointe selon `yaw` autour de
## l'axe vertical, puis se couche sur la pente decrite par `up`.
static func basis_from(p_yaw: float, p_up: Vector3) -> Basis:
	var safe_up: Vector3 = p_up.normalized() if p_up.length_squared() > 0.0001 else Vector3.UP
	var flat_forward: Vector3 = Vector3(-sin(p_yaw), 0.0, -cos(p_yaw))
	var right: Vector3 = flat_forward.cross(safe_up)
	if right.length_squared() < 0.0001:
		# Cas degenere : le vehicule est a la verticale. On repart de l'horizontale.
		safe_up = Vector3.UP
		right = flat_forward.cross(safe_up)
	right = right.normalized()
	var forward: Vector3 = safe_up.cross(right).normalized()
	return Basis(right, safe_up, -forward)


## Vitesse projetee sur l'axe avant du vehicule (negative en marche arriere).
func get_forward_speed() -> float:
	return velocity.dot(-get_basis().z)


## Vitesse absolue, en m/s.
func get_speed() -> float:
	return velocity.length()


func to_floats() -> PackedFloat32Array:
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(ENCODED_FLOATS)
	data[0] = position.x
	data[1] = position.y
	data[2] = position.z
	data[3] = yaw
	data[4] = velocity.x
	data[5] = velocity.y
	data[6] = velocity.z
	data[7] = up.x
	data[8] = up.y
	data[9] = up.z
	data[10] = drift
	data[11] = steer_smoothed
	data[12] = 1.0 if grounded else 0.0
	data[13] = float(teleport_id)
	return data


static func from_floats(data: PackedFloat32Array, offset: int = 0) -> VehicleState:
	var state: VehicleState = VehicleState.new()
	state.position = Vector3(data[offset], data[offset + 1], data[offset + 2])
	state.yaw = data[offset + 3]
	state.velocity = Vector3(data[offset + 4], data[offset + 5], data[offset + 6])
	state.up = Vector3(data[offset + 7], data[offset + 8], data[offset + 9])
	state.drift = data[offset + 10]
	state.steer_smoothed = data[offset + 11]
	state.grounded = data[offset + 12] > 0.5
	state.teleport_id = int(data[offset + 13])
	return state


## Ecart de position avec un autre etat, en metres.
func position_error(other: VehicleState) -> float:
	return position.distance_to(other.position)


## Ecart d'orientation avec un autre etat, en radians (toujours positif).
func rotation_error(other: VehicleState) -> float:
	var difference: float = wrapf(yaw - other.yaw, -PI, PI)
	return absf(difference)
