class_name VehiclePhysics
extends RefCounted
## Simulation arcade d'un vehicule. Fonction de transition pure :
## `step(etat, entree, delta) -> etat suivant`.
##
## DETERMINISME — regle absolue
## ----------------------------
## Le client rejoue jusqu'a une vingtaine de pas d'un coup pour se reconcilier
## avec le serveur. Pour que le resultat soit identique des deux cotes, cette
## classe ne doit JAMAIS dependre :
##   - du hasard (`randf`) ;
##   - de l'horloge (`Time.get_ticks_msec`, `Engine.get_frames_drawn`) ;
##   - de l'etat d'un autre vehicule ;
##   - de quoi que ce soit de mobile dans la scene.
## Sa seule dependance externe est la geometrie STATIQUE de la piste, qui ne
## change pas. Toute nouvelle dependance casserait la prediction.
##
## MODELE — voir CLAUDE.md section 3.1
##   vitesse avant scalaire + adherence laterale + lacet pilote par le braquage.
## Ce n'est pas une simulation : c'est un modele concu pour etre agreable et
## reglable. Chaque reglage de `tuning.cfg` correspond a une sensation.

## Boite de collision, centree sur la position simulee. Volontairement un peu
## plus large que la carrosserie visible pour que les chocs contre les murs se
## produisent avant que la peinture ne les traverse a l'ecran.
const CHASSIS_SIZE: Vector3 = Vector3(1.80, 0.90, 4.15)

## Points de sondage du sol, en coordonnees locales (les quatre coins).
const PROBE_OFFSETS: Array[Vector3] = [
	Vector3(-0.80, 0.0, -1.55),
	Vector3(0.80, 0.0, -1.55),
	Vector3(-0.80, 0.0, 1.55),
	Vector3(0.80, 0.0, 1.55),
]

## Hauteur de depart des rayons au-dessus du centre du chassis, en metres.
const PROBE_START_HEIGHT: float = 0.60

## Couches de collision. Le sol et les murs sont SEPARES, et c'est essentiel :
##   - le sol (piste, rampes) est detecte par les rayons, et par eux seuls ;
##   - les murs sont les seuls obstacles que le corps de collision percute.
## Melanger les deux faisait heurter la pente des rampes par la boite de
## collision : au lieu de sauter, la voiture s'ecrasait dessus et perdait les
## trois quarts de sa vitesse.
const LAYER_GROUND: int = 1
const LAYER_WALL: int = 4

## En dessous de cette vitesse, la voiture ne pivote plus : evite de tourner
## sur place a l'arret, ce qui parait faux meme en arcade.
const STEER_ENGAGE_SPEED: float = 4.0

## Vitesse de montee du derapage quand le frein a main est tire (1/s).
## Volontairement rapide : le derapage doit se declencher franchement.
const DRIFT_ENGAGE_RATE: float = 6.0

## Correction verticale maximale appliquee par le plaquage au sol (m/s).
## Borne de securite : evite qu'une bosse ne catapulte la voiture.
const MAX_SNAP_SPEED: float = 18.0

## Nombre maximal de glissements resolus par pas lors d'un choc contre un mur.
const MAX_SLIDES: int = 2

## Part du rappel anti-tete-a-queue conservee hors derapage. Le reste ne
## s'applique qu'en glisse, proportionnellement a celle-ci.
const BASE_SLIP_DAMPING: float = 0.25

var _body: CharacterBody3D
var _exclusions: Array[RID] = []

# Resultat du dernier sondage de sol. Variables membres plutot que valeur de
# retour : evite une allocation par pas, et il y en a beaucoup lors d'un replay.
var _ground_hit: bool = false
var _ground_distance: float = 0.0
var _ground_normal: Vector3 = Vector3.UP

# Derniere adherence laterale effective, lue par le panneau de debogage (F3).
var last_grip: float = 0.0


func setup(body: CharacterBody3D) -> void:
	_body = body
	_exclusions = [body.get_rid()]


## Avance la simulation d'un pas. Fonction pure du point de vue de l'appelant :
## `state` n'est pas modifie, un nouvel etat est retourne.
func step(state: VehicleState, input: InputFrame, delta: float) -> VehicleState:
	var next: VehicleState = state.copy()
	var basis: Basis = next.get_basis()
	var forward: Vector3 = -basis.z
	var right: Vector3 = basis.x

	_probe_ground(next.position, basis)
	next.grounded = _ground_hit

	# --- Direction : le braquage possede de l'inertie -------------------------
	var steer_blend: float = 1.0 - exp(-Tuning.steer_response * delta)
	next.steer_smoothed = lerpf(next.steer_smoothed, input.steer, steer_blend)

	# --- Decomposition de la vitesse dans le repere du vehicule ---------------
	var forward_speed: float = next.velocity.dot(forward)
	var lateral_speed: float = next.velocity.dot(right)

	# --- Moteur, freins, frottements -----------------------------------------
	if next.grounded:
		forward_speed = _apply_engine(forward_speed, input, delta)
	# En l'air, la vitesse avant est conservee : pas de roue au sol, pas de couple.

	# --- Derapage : montee rapide, retour progressif en adherence -------------
	# Seuil base sur la vitesse REELLE et non sur sa projection vers l'avant :
	# une fois la voiture en travers, la projection s'effondre et le derapage
	# se serait coupe tout seul, au pire moment.
	var can_drift: bool = input.handbrake and next.velocity.length() >= Tuning.drift_min_speed
	if can_drift and next.grounded:
		next.drift = minf(1.0, next.drift + DRIFT_ENGAGE_RATE * delta)
	else:
		next.drift = maxf(0.0, next.drift - Tuning.grip_recovery * delta)

	# --- Lacet : le braquage fait pivoter la voiture --------------------------
	#
	# ORDRE CAPITAL. La vitesse est d'abord recomposee dans l'ANCIEN repere :
	# elle conserve ainsi sa direction dans le monde pendant que le vehicule
	# pivote. C'est precisement cet ecart entre le nez et la trajectoire qui
	# constitue le derapage.
	# Recomposer apres la rotation ferait tourner le vecteur vitesse avec la
	# voiture : elle suivrait toujours son nez et ne pourrait jamais glisser,
	# quel que soit le reglage d'adherence.
	var world_velocity: Vector3 = forward * forward_speed + right * lateral_speed

	next.yaw += _compute_yaw_rate(next, forward_speed, lateral_speed) * delta

	# Nouveau repere, apres rotation.
	basis = VehicleState.basis_from(next.yaw, next.up)
	forward = -basis.z
	right = basis.x

	# --- Adherence laterale : la trajectoire rattrape le nez de la voiture ----
	# La vitesse est redecomposee dans le NOUVEAU repere : sa composante
	# laterale mesure maintenant le derapage reel, et c'est elle que l'adherence
	# resorbe. Amortissement exponentiel, donc independant de la taille du pas —
	# indispensable pour que le replay soit exact.
	forward_speed = world_velocity.dot(forward)
	lateral_speed = world_velocity.dot(right)

	var speed_ratio: float = clampf(absf(forward_speed) / Tuning.max_speed, 0.0, 1.0)
	var grip: float = lerpf(Tuning.lateral_grip, Tuning.handbrake_grip, next.drift)
	grip += Tuning.lateral_grip * Tuning.downforce_grip_bonus * speed_ratio
	last_grip = grip
	lateral_speed *= exp(-grip * delta)

	# --- Recomposition de la vitesse -----------------------------------------
	var planar: Vector3 = forward * forward_speed + right * lateral_speed
	if next.grounded:
		# La voiture EPOUSE la pente : la vitesse est projetee sur le plan du
		# sol en conservant sa norme. Sans cette projection, elle aborderait une
		# rampe a l'horizontale et la percuterait de plein fouet.
		var magnitude: float = planar.length()
		var along_slope: Vector3 = planar.slide(_ground_normal)
		if along_slope.length() > 0.001:
			planar = along_slope.normalized() * magnitude

		# Le plaquage ne corrige plus que l'ecart de hauteur residuel.
		var height_error: float = Tuning.ride_height - _ground_distance
		var snap: float = clampf(height_error * Tuning.ground_snap_speed,
			-MAX_SNAP_SPEED, MAX_SNAP_SPEED)
		next.velocity = planar + _ground_normal * snap
	else:
		next.velocity = Vector3(planar.x, next.velocity.y - Tuning.gravity * delta, planar.z)

	# --- Assiette : la voiture epouse la pente, puis se redresse en l'air -----
	var target_up: Vector3 = _ground_normal if next.grounded else Vector3.UP
	var align_speed: float = Tuning.align_to_ground_speed if next.grounded else Tuning.align_in_air_speed
	next.up = next.up.lerp(target_up, 1.0 - exp(-align_speed * delta)).normalized()

	# --- Deplacement et collisions contre les murs ----------------------------
	_move(next, basis, delta)
	return next


## Replace le vehicule, en annulant toute inertie. Utilise par la remise en
## piste. Incremente `teleport_id` pour que le client sache qu'il s'agit d'un
## saut voulu et ne cherche pas a le lisser.
func teleport(state: VehicleState, position: Vector3, yaw: float) -> VehicleState:
	var next: VehicleState = VehicleState.create_at(position, yaw)
	next.teleport_id = state.teleport_id + 1
	return next


## Acceleration, freinage, marche arriere et frottements.
func _apply_engine(forward_speed: float, input: InputFrame, delta: float) -> float:
	var speed: float = forward_speed

	if input.throttle > 0.0:
		speed += Tuning.engine_acceleration * input.throttle * delta

	if input.brake > 0.0:
		if speed > 0.5:
			# On roule vers l'avant : le frein mord fort.
			speed -= Tuning.brake_force * input.brake * delta
		else:
			# A l'arret ou deja en recul : la meme touche engage la marche arriere,
			# plus molle que la marche avant.
			speed -= Tuning.engine_acceleration * 0.6 * input.brake * delta

	if input.throttle <= 0.0 and input.brake <= 0.0:
		speed = move_toward(speed, 0.0, Tuning.engine_braking * delta)

	if input.handbrake:
		speed = move_toward(speed, 0.0, Tuning.handbrake_braking * delta)

	# Frottement proportionnel a la vitesse : limite surtout la vitesse de pointe.
	speed -= speed * Tuning.rolling_resistance * delta

	return clampf(speed, -Tuning.max_reverse_speed, Tuning.max_speed)


## Vitesse de rotation autour de l'axe vertical, en radians par seconde.
func _compute_yaw_rate(state: VehicleState, forward_speed: float, lateral_speed: float) -> float:
	var absolute_speed: float = absf(forward_speed)

	# Le braquage s'attenue avec la vitesse, sinon la voiture pivote sur elle-meme
	# a pleine vitesse.
	var speed_ratio: float = clampf(absolute_speed / Tuning.max_speed, 0.0, 1.0)
	var authority: float = lerpf(1.0, Tuning.steer_rate_at_max_speed, speed_ratio)

	# ... et s'annule a l'arret : sans roue qui roule, rien ne fait tourner.
	var engagement: float = clampf(absolute_speed / STEER_ENGAGE_SPEED, 0.0, 1.0)

	# Signe : une entree positive veut dire « a droite », alors qu'un lacet
	# croissant tourne vers la GAUCHE dans le repere de Godot. D'ou l'inversion.
	var rate: float = -Tuning.steer_rate_rad * state.steer_smoothed * authority * engagement

	# En marche arriere, la voiture tourne dans l'autre sens.
	if forward_speed < 0.0:
		rate = -rate

	# Rotation supplementaire pendant le derapage : c'est ce qui fait pivoter la
	# voiture quand on tire le frein a main.
	rate -= Tuning.steer_rate_rad * Tuning.handbrake_yaw_boost * state.drift \
		* state.steer_smoothed * engagement

	# Rappel anti-tete-a-queue. Sans lui, rien ne s'oppose a la rotation pendant
	# un derapage et la voiture finit systematiquement en toupie. Ce couple
	# ramene le nez vers la trajectoire, d'autant plus fort que l'angle de
	# derive est grand : le derapage se stabilise a un angle donne au lieu de
	# diverger. C'est ce qui le rend CONTROLABLE, l'objectif de la phase 0.
	if state.grounded and absolute_speed > 1.0:
		var slip: float = atan2(lateral_speed, maxf(absolute_speed, 1.0))
		# Le rappel est surtout actif PENDANT le derapage. En adherence normale,
		# l'adherence laterale limite deja la derive : y ajouter un rappel fort
		# ne ferait que brider inutilement les virages.
		var strength: float = BASE_SLIP_DAMPING + (1.0 - BASE_SLIP_DAMPING) * state.drift
		rate -= slip * Tuning.drift_slip_damping * strength

	if not state.grounded:
		rate *= Tuning.air_steer_factor

	return rate


## Quatre rayons vers le bas depuis les coins du chassis.
## Remplit `_ground_hit`, `_ground_distance` et `_ground_normal`.
func _probe_ground(position: Vector3, basis: Basis) -> void:
	var up: Vector3 = basis.y
	var hits: int = 0
	var distance_sum: float = 0.0
	var normal_sum: Vector3 = Vector3.ZERO

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.collision_mask = LAYER_GROUND
	query.exclude = _exclusions
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state

	for offset: Vector3 in PROBE_OFFSETS:
		var origin: Vector3 = position + basis * offset + up * PROBE_START_HEIGHT
		query.from = origin
		query.to = origin - up * (PROBE_START_HEIGHT + Tuning.ground_ray_length)
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			continue
		hits += 1
		var point: Vector3 = result["position"]
		distance_sum += origin.distance_to(point) - PROBE_START_HEIGHT
		normal_sum += result["normal"]

	if hits == 0:
		_ground_hit = false
		_ground_distance = Tuning.ground_ray_length
		_ground_normal = Vector3.UP
		return

	_ground_hit = true
	_ground_distance = distance_sum / float(hits)
	_ground_normal = (normal_sum / float(hits)).normalized()


## Deplace le corps et resout les chocs contre les murs.
func _move(state: VehicleState, basis: Basis, delta: float) -> void:
	_body.global_position = state.position
	_body.global_basis = basis

	var motion: Vector3 = state.velocity * delta
	var forward: Vector3 = -basis.z

	for _slide: int in MAX_SLIDES:
		var collision: KinematicCollision3D = _body.move_and_collide(motion)
		if collision == null:
			break
		var normal: Vector3 = collision.get_normal()
		var into_wall: float = state.velocity.dot(normal)
		if into_wall < 0.0:
			# Composante entrante annulee, plus un leger rebond.
			state.velocity -= normal * into_wall * (1.0 + Tuning.wall_bounce)
			# Un choc frontal coute plus cher qu'un frottement rasant.
			var frontality: float = absf(normal.dot(forward))
			state.velocity *= 1.0 - Tuning.wall_speed_loss * frontality
		motion = collision.get_remainder().slide(normal)
		if motion.length_squared() < 0.000001:
			break

	state.position = _body.global_position
