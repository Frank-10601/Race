extends Node3D
## Piste de test de la phase 0.
##
## Une longue ligne droite avec des rampes, puis trois virages larges bordes de
## murs bas. Ce n'est pas un circuit de course : c'est un terrain d'essai pour
## regler le ressenti de conduite. Le vrai circuit ferme arrive en phase 1.

## Rampes : [distance depuis le depart, decalage lateral, longueur, inclinaison].
const RAMPS: Array = [
	[70.0, 0.0, 16.0, 10.0],
	[118.0, -6.5, 14.0, 8.0],
	[118.0, 6.5, 14.0, 8.0],
	[168.0, 0.0, 18.0, 12.0],
]

## Tolerance au-dela du bord de piste avant de considerer un vehicule hors piste.
const OFF_TRACK_MARGIN: float = 3.0

const RAMP_WIDTH: float = 9.0
const RAMP_THICKNESS: float = 1.6
const LAYER_WORLD: int = 1

var _builder: TrackBuilder = TrackBuilder.new()
var _spawn_points: Array[Transform3D] = []
var _centerline: PackedVector2Array = PackedVector2Array()
var _track_width: float = 24.0
var _last_segment: int = 0


func _ready() -> void:
	var plan: TrackPlan = _make_plan()
	_track_width = plan.width
	_centerline = plan.sample()["points"]
	_builder.build(plan, self)
	_build_ramps(plan)
	_spawn_points = _builder.build_spawn_points(Tuning.max_players)
	_build_environment()


## Trace de la piste de test. Une instruction par ligne, comme on decrirait le
## circuit a voix haute.
func _make_plan() -> TrackPlan:
	var plan: TrackPlan = TrackPlan.new()
	plan.width = 24.0
	plan.straight(230.0)        # longue ligne droite : vitesse de pointe et rampes
	plan.turn(95.0, 55.0)       # premier virage large a droite
	plan.straight(110.0)
	plan.turn(85.0, 48.0)       # deuxieme virage, un peu plus serre
	plan.straight(150.0)
	plan.turn(100.0, 60.0)      # troisieme virage, tres ouvert
	plan.straight(120.0)
	return plan


## Position de depart d'un joueur. Les indices au-dela de la grille bouclent,
## ce qui evite toute erreur si le nombre de joueurs change.
func get_spawn_transform(index: int) -> Transform3D:
	if _spawn_points.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, Tuning.ride_height, 0.0))
	return _spawn_points[index % _spawn_points.size()]


func get_spawn_count() -> int:
	return _spawn_points.size()


## Tremplins poses sur la ligne droite : boites inclinees dont le bord bas
## affleure le sol.
func _build_ramps(plan: TrackPlan) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Ramps"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.40, 0.44)
	material.roughness = 0.9

	for ramp: Array in RAMPS:
		var distance: float = ramp[0]
		var lateral_offset: float = ramp[1]
		var length: float = ramp[2]
		var angle: float = deg_to_rad(ramp[3])

		var sample: Dictionary = _sample_plan(plan, distance)
		var position: Vector2 = sample["position"]
		var heading: float = sample["heading"]
		var lateral: Vector2 = TrackPlan.right_vector(heading) * lateral_offset

		# Hauteur du centre pour que le bord bas touche exactement le sol.
		var height: float = length * 0.5 * sin(angle) - RAMP_THICKNESS * 0.5 * cos(angle)
		var origin: Vector3 = Vector3(position.x + lateral.x, height, position.y + lateral.y)
		# Le nez de la rampe se releve : rotation autour de l'axe lateral.
		var basis: Basis = Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, -angle)
		var transform: Transform3D = Transform3D(basis, origin)

		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(RAMP_WIDTH, RAMP_THICKNESS, length)
		shape.shape = box
		shape.transform = transform
		body.add_child(shape)

		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(RAMP_WIDTH, RAMP_THICKNESS, length)
		mesh_instance.mesh = mesh
		mesh_instance.material_override = material
		mesh_instance.transform = transform
		body.add_child(mesh_instance)


## Eclairage de jour simple : un soleil avec ombres et un ciel procedural.
func _build_environment() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)

	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.28, 0.48, 0.78)
	sky_material.sky_horizon_color = Color(0.72, 0.80, 0.88)
	sky_material.ground_bottom_color = Color(0.22, 0.26, 0.24)
	sky_material.ground_horizon_color = Color(0.60, 0.64, 0.62)
	sky_material.sun_angle_max = 8.0

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.85
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.70, 0.78, 0.86)
	environment.fog_density = 0.0012
	environment.fog_sky_affect = 0.0

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)


## Petit utilitaire local : position et cap a une distance donnee sur le trace.
func _sample_plan(plan: TrackPlan, distance: float) -> Dictionary:
	var sampled: Dictionary = plan.sample()
	var points: PackedVector2Array = sampled["points"]
	var headings: PackedFloat32Array = sampled["headings"]
	var travelled: float = 0.0
	for index: int in range(points.size() - 1):
		var segment: float = points[index].distance_to(points[index + 1])
		if travelled + segment >= distance:
			var t: float = (distance - travelled) / maxf(segment, 0.0001)
			return {"position": points[index].lerp(points[index + 1], t), "heading": headings[index]}
		travelled += segment
	return {"position": points[points.size() - 1], "heading": headings[headings.size() - 1]}


## Le point donne est-il sur le ruban de piste ?
## Utilise par la remise en piste automatique pour distinguer « arrete sur la
## piste » (on laisse jouer) de « plante dans l'herbe » (on remet en piste).
## La recherche repart du dernier segment trouve : cout constant en pratique.
func is_on_track(position: Vector3) -> bool:
	if _centerline.is_empty():
		return true
	var point: Vector2 = Vector2(position.x, position.z)
	var half_width: float = _track_width * 0.5 + OFF_TRACK_MARGIN
	var count: int = _centerline.size()
	for step: int in count:
		# Balayage en spirale autour du dernier segment connu.
		var offset: int = (step + 1) / 2
		if step % 2 == 1:
			offset = -offset
		var index: int = wrapi(_last_segment + offset, 0, count - 1)
		var distance: float = _distance_to_segment(point, _centerline[index], _centerline[index + 1])
		if distance <= half_width:
			_last_segment = index
			return true
	return false


## Distance d'un point au segment [a, b].
static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment: Vector2 = b - a
	var length_squared: float = segment.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * t)
