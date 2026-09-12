class_name VehicleVisuals
extends Node3D
## Apparence du vehicule : carrosserie, quatre roues, pseudo.
##
## Ce noeud est en `top_level` : il vit en coordonnees monde, independamment du
## corps de collision. C'est ce qui permet de dissocier la SIMULATION du RENDU.
##
## Deux lissages s'y superposent, et il ne faut pas les confondre :
##
##   1. Lissage temporel — la physique tourne a 60 Hz, l'ecran souvent plus vite.
##      On interpole entre l'etat precedent et l'etat courant. Sans retard ajoute.
##
##   2. Resorption d'erreur — quand la reconciliation reseau deplace brutalement
##      le corps, le visuel garde l'ancienne position et la rattrape en douceur
##      (`visual_correction_time`). La simulation est juste immediatement, l'oeil
##      ne voit aucun saut.
##
## Une remise en piste (`teleport_id`) court-circuite le point 2 : c'est un saut
## voulu, il doit etre instantane.

## Inclinaison maximale de la caisse en virage, en degres.
const MAX_ROLL: float = 7.0
## Plongee maximale au freinage / cabrage a l'acceleration, en degres.
const MAX_PITCH: float = 3.0
## Rapidite de reaction de la suspension visuelle (1/s).
const SUSPENSION_SPEED: float = 8.0

var _body_node: Node3D
var _wheels: Array[Node3D] = []
var _name_tag: Label3D

# Etats echantillonnes a chaque pas de physique, pour l'interpolation de rendu.
var _previous_transform: Transform3D = Transform3D.IDENTITY
var _current_transform: Transform3D = Transform3D.IDENTITY

# Erreur restant a resorber apres une correction reseau.
var _position_error: Vector3 = Vector3.ZERO
var _yaw_error: float = 0.0

var _wheel_spin: float = 0.0
## Rayon des roues effectivement affichees. Un modele importe a rarement le
## rayon des roues primitives, et s'en servir ferait tourner les roues a une
## vitesse sans rapport avec le defilement du sol.
var _wheel_radius: float = VehicleFactory.WHEEL_RADIUS
var _steer_visual: float = 0.0
var _roll: float = 0.0
var _pitch: float = 0.0
var _previous_forward_speed: float = 0.0
var _last_teleport_id: int = 0


func setup(color: Color, player_name: String, model_path: String = "") -> void:
	top_level = true

	var model: Dictionary = VehicleFactory.load_model(model_path)
	if model.is_empty():
		# Aucun modele : formes primitives, avec leurs quatre roues.
		_body_node = VehicleFactory.create_body(color)
		add_child(_body_node)
		for suffix: String in ["FL", "FR", "RL", "RR"]:
			var wheel: Node3D = VehicleFactory.create_wheel(suffix)
			add_child(wheel)
			_wheels.append(wheel)
	else:
		var root: Node3D = model["root"]
		# Le modele a son origine AU SOL (voir tools/prepare_vehicle.py), alors
		# que ce noeud suit le centre du vehicule, situe a `ride_height`.
		root.position = Vector3(0.0, -Tuning.ride_height, 0.0)
		add_child(root)
		_body_node = model["body"]
		# Roues separees si le modele en fournit ; sinon elles font partie de la
		# carrosserie et il n'y a rien a animer.
		_wheels.assign(model["wheels"])
		_measure_model_wheels()

	if model.is_empty():
		# Les roues primitives sont placees par le code ; celles d'un modele
		# sont deja a leur place et ne doivent surtout pas etre deplacees.
		for index: int in _wheels.size():
			_wheels[index].position = VehicleFactory.WHEEL_POSITIONS[index] \
				+ Vector3(0.0, VehicleFactory.WHEEL_RADIUS - Tuning.ride_height, 0.0)

	_name_tag = VehicleFactory.create_name_tag(player_name)
	add_child(_name_tag)


## Deduit le rayon des roues du modele : le moyeu d'une roue posee au sol se
## trouve exactement a la hauteur de son rayon.
func _measure_model_wheels() -> void:
	if _wheels.is_empty():
		return
	var total: float = 0.0
	for wheel: Node3D in _wheels:
		total += wheel.position.y
	_wheel_radius = maxf(total / float(_wheels.size()), 0.05)


## Roues actuellement animees. Vide si le modele n'en fournit pas de separees.
func get_wheels() -> Array[Node3D]:
	return _wheels


func set_player_name(player_name: String) -> void:
	if _name_tag != null:
		_name_tag.text = player_name


## Masque le pseudo au-dessus de sa propre voiture : il gene la vue et
## n'apprend rien au joueur.
func set_name_tag_visible(is_visible: bool) -> void:
	if _name_tag != null:
		_name_tag.visible = is_visible


## Appele a chaque pas de physique avec l'etat qui vient d'etre simule.
func sync_to_state(state: VehicleState) -> void:
	_previous_transform = _current_transform
	_current_transform = Transform3D(state.get_basis(), state.position)

	if state.teleport_id != _last_teleport_id:
		# Remise en piste : saut voulu, aucune resorption.
		_last_teleport_id = state.teleport_id
		_previous_transform = _current_transform
		_position_error = Vector3.ZERO
		_yaw_error = 0.0
		_wheel_spin = 0.0


## Enregistre le deplacement provoque par une correction reseau, pour que le
## visuel le rattrape progressivement au lieu de sauter.
func absorb_correction(before: Vector3, after: Vector3, yaw_before: float, yaw_after: float) -> void:
	_position_error += before - after
	_yaw_error = wrapf(_yaw_error + yaw_before - yaw_after, -PI, PI)
	# Au-dela d'un ecart grossier, mieux vaut assumer le saut que de voir la
	# voiture glisser sur plusieurs metres.
	if _position_error.length() > 6.0:
		_position_error = Vector3.ZERO
		_yaw_error = 0.0


## Appele a chaque image. `state` sert aux animations (roues, assiette).
func update_visual(state: VehicleState, delta: float) -> void:
	# 1. Interpolation entre les deux derniers pas de physique.
	var fraction: float = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var smoothed: Transform3D = _previous_transform.interpolate_with(_current_transform, fraction)

	# 2. Resorption exponentielle de l'erreur de reconciliation.
	var decay: float = exp(-delta / maxf(Tuning.visual_correction_time, 0.001))
	_position_error *= decay
	_yaw_error *= decay
	if _position_error.length_squared() < 0.000001:
		_position_error = Vector3.ZERO

	# 3. Assiette : la caisse s'incline en virage et plonge au freinage.
	_update_suspension(state, delta)

	var basis: Basis = smoothed.basis
	if absf(_yaw_error) > 0.0001:
		basis = Basis(Vector3.UP, _yaw_error) * basis
	basis = basis * Basis(Vector3.FORWARD, _roll) * Basis(Vector3.RIGHT, _pitch)

	global_transform = Transform3D(basis, smoothed.origin + _position_error)

	_update_wheels(state, delta)


## Roulis et tangage, deduits du derapage et de la variation de vitesse.
func _update_suspension(state: VehicleState, delta: float) -> void:
	var basis: Basis = state.get_basis()
	var lateral_speed: float = state.velocity.dot(basis.x)
	var forward_speed: float = state.velocity.dot(-basis.z)

	var roll_target: float = deg_to_rad(MAX_ROLL) * clampf(lateral_speed / 14.0, -1.0, 1.0)
	var acceleration: float = (forward_speed - _previous_forward_speed) / maxf(delta, 0.0001)
	var pitch_target: float = deg_to_rad(MAX_PITCH) * clampf(acceleration / 25.0, -1.0, 1.0)
	_previous_forward_speed = forward_speed

	var blend: float = 1.0 - exp(-SUSPENSION_SPEED * delta)
	_roll = lerpf(_roll, roll_target, blend)
	_pitch = lerpf(_pitch, pitch_target, blend)


## Braquage des roues avant et rotation des quatre roues.
func _update_wheels(state: VehicleState, delta: float) -> void:
	if _wheels.is_empty():
		return

	var forward_speed: float = state.velocity.dot(-state.get_basis().z)
	_wheel_spin = wrapf(_wheel_spin + forward_speed / _wheel_radius * delta, 0.0, TAU)

	# Le braquage visuel suit le braquage simule, avec un leger retard qui rend
	# le mouvement plus naturel que de recopier la valeur brute.
	# Meme inversion que pour le lacet : braquer a droite fait tourner les roues
	# vers la droite, donc dans le sens negatif du repere de Godot.
	var steer_target: float = -state.steer_smoothed * Tuning.steer_visual_angle_rad
	_steer_visual = lerpf(_steer_visual, steer_target, 1.0 - exp(-14.0 * delta))

	for index: int in _wheels.size():
		var steer: float = _steer_visual if index < VehicleFactory.STEERING_WHEEL_COUNT else 0.0
		# Ordre d'Euler YXZ : le braquage (Y) s'applique avant le roulement (X).
		_wheels[index].rotation = Vector3(_wheel_spin, steer, 0.0)
