class_name ChaseCamera
extends Camera3D
## Camera a la troisieme personne.
##
## Trois reglages font l'essentiel de la sensation de vitesse :
##   - un leger RETARD de suivi : la camera n'est pas soudee a la voiture ;
##   - un RECUL progressif a haute vitesse, avec un champ de vision qui s'ouvre ;
##   - une INCLINAISON dans les virages.
##
## Detail arcade important : pendant un derapage, la camera reste alignee sur la
## TRAJECTOIRE plutot que sur le nez de la voiture. Sans cela, le decor pivote
## brutalement au declenchement du derapage et on perd ses reperes.
##
## Touche C : vue arriere -> vue rapprochee -> vue capot.

enum View { CHASE, CLOSE, HOOD }

## Part de la trajectoire prise en compte dans l'orientation, a derapage maximal.
const DRIFT_TRAJECTORY_BLEND: float = 0.55
## Distance visee devant la voiture, en metres.
const LOOK_AHEAD: float = 8.0
## Hauteur du point vise au-dessus de la voiture, en metres.
const LOOK_HEIGHT: float = 1.1

var _target: Vehicle = null
var _view: View = View.CHASE
var _smoothed_position: Vector3 = Vector3.ZERO
var _smoothed_look: Vector3 = Vector3.ZERO
var _smoothed_yaw: float = 0.0
var _tilt: float = 0.0
var _initialised: bool = false


func _ready() -> void:
	top_level = true
	# S'execute apres les vehicules, pour suivre une image deja a jour.
	process_priority = 100
	fov = Tuning.base_fov


func set_target(vehicle: Vehicle) -> void:
	_target = vehicle
	_initialised = false


func cycle_view() -> void:
	_view = ((_view + 1) % View.size()) as View


func get_view_name() -> String:
	match _view:
		View.CHASE:
			return "arriere"
		View.CLOSE:
			return "rapprochee"
		_:
			return "capot"


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	var state: VehicleState = _target.state
	var speed_ratio: float = clampf(state.get_speed() / maxf(Tuning.max_speed, 1.0), 0.0, 1.0)

	# Orientation suivie : nez de la voiture, mele a la trajectoire en derapage.
	var car_yaw: float = state.yaw
	var target_yaw: float = car_yaw
	var planar_velocity: Vector2 = Vector2(state.velocity.x, state.velocity.z)
	if planar_velocity.length() > 4.0:
		var travel_yaw: float = atan2(-planar_velocity.x, -planar_velocity.y)
		target_yaw = lerp_angle(car_yaw, travel_yaw, state.drift * DRIFT_TRAJECTORY_BLEND)

	if not _initialised:
		_smoothed_yaw = target_yaw
		_smoothed_position = _desired_position(state, target_yaw, speed_ratio)
		_smoothed_look = state.position
		_initialised = true

	_smoothed_yaw = lerp_angle(_smoothed_yaw, target_yaw, 1.0 - exp(-Tuning.look_speed * delta))

	if _view == View.HOOD:
		_apply_hood_view(state)
		_apply_fov(speed_ratio, delta)
		return

	var desired: Vector3 = _desired_position(state, _smoothed_yaw, speed_ratio)
	_smoothed_position = _smoothed_position.lerp(desired, 1.0 - exp(-Tuning.follow_speed * delta))

	var forward: Vector3 = Vector3(-sin(_smoothed_yaw), 0.0, -cos(_smoothed_yaw))
	var look_target: Vector3 = state.position + forward * LOOK_AHEAD + Vector3.UP * LOOK_HEIGHT
	_smoothed_look = _smoothed_look.lerp(look_target, 1.0 - exp(-Tuning.look_speed * delta))

	global_position = _smoothed_position
	look_at(_smoothed_look, Vector3.UP)

	# Inclinaison en virage, dosee par le braquage et la vitesse.
	var tilt_target: float = deg_to_rad(Tuning.corner_tilt) * state.steer_smoothed * speed_ratio
	_tilt = lerpf(_tilt, tilt_target, 1.0 - exp(-6.0 * delta))
	rotate_object_local(Vector3.FORWARD, _tilt)

	_apply_fov(speed_ratio, delta)


## Position souhaitee derriere la voiture, avant lissage.
func _desired_position(state: VehicleState, yaw: float, speed_ratio: float) -> Vector3:
	var distance: float = Tuning.chase_distance
	var height: float = Tuning.chase_height
	if _view == View.CLOSE:
		distance = Tuning.close_distance
		height = Tuning.close_height
	distance += Tuning.speed_pullback * speed_ratio

	var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	return state.position - forward * distance + Vector3.UP * height


## Vue capot : la camera est solidaire de la voiture, inclinaison comprise.
func _apply_hood_view(state: VehicleState) -> void:
	var basis: Basis = state.get_basis()
	global_position = state.position + basis * Vector3(0.0, Tuning.hood_height, -Tuning.hood_forward)
	global_basis = basis
	_smoothed_position = global_position
	_tilt = 0.0


## Le champ de vision s'ouvre avec la vitesse : c'est l'effet le plus efficace
## pour « sentir » la vitesse a l'ecran.
func _apply_fov(speed_ratio: float, delta: float) -> void:
	var target: float = Tuning.base_fov + Tuning.speed_fov_gain * speed_ratio
	fov = lerpf(fov, target, 1.0 - exp(-5.0 * delta))
