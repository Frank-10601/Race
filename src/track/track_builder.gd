class_name TrackBuilder
extends RefCounted
## Construit la geometrie d'un circuit a partir d'un `TrackPlan`.
##
## Tout est genere par le code, uniquement avec des primitives Godot : aucun
## asset externe en phase 0 (CLAUDE.md, contrainte 4). Les elements repetes
## (bandes au sol, poteaux, murs) passent par des `MultiMesh` : un seul appel de
## rendu pour des centaines d'objets, ce qui compte beaucoup dans un navigateur.

## Couches de collision, separees a dessein : le sol est sonde par les rayons du
## vehicule, les murs sont percutes par son corps de collision.
const LAYER_GROUND: int = 1
const LAYER_WALL: int = 4

## Geometrie des bordures.
const WALL_HEIGHT: float = 0.70
const WALL_THICKNESS: float = 0.60
const WALL_SEGMENT_POINTS: int = 2  ## un segment de mur tous les N points echantillonnes

## Reperes visuels au sol : bandes transversales pour ressentir la vitesse.
const STRIPE_SPACING: float = 10.0
const STRIPE_DEPTH: float = 0.70

## Poteaux de bord de piste : le defilement vertical renforce la sensation de vitesse.
const POST_SPACING: float = 25.0
const POST_HEIGHT: float = 3.20
const POST_RADIUS: float = 0.13
const POST_OFFSET: float = 3.00

## Hauteurs d'empilement, pour eviter que les surfaces ne clignotent entre elles.
const GROUND_Y: float = 0.0
const ASPHALT_Y: float = 0.03
const STRIPE_Y: float = 0.07

var _plan: TrackPlan
var _points: PackedVector2Array
var _headings: PackedFloat32Array


func build(plan: TrackPlan, parent: Node3D) -> void:
	_plan = plan
	var sampled: Dictionary = plan.sample()
	_points = sampled["points"]
	_headings = sampled["headings"]

	_build_ground(parent)
	_build_asphalt(parent)
	_build_stripes(parent)
	_build_walls(parent)
	_build_posts(parent)


## Positions de depart, disposees en grille de deux colonnes sur la ligne droite
## initiale. Prevu pour 12 joueurs des maintenant (CLAUDE.md, contrainte 7).
func build_spawn_points(count: int) -> Array[Transform3D]:
	var spawns: Array[Transform3D] = []
	var row_spacing: float = 8.0
	var column_offset: float = 4.5
	for index: int in count:
		var row: int = index / 2
		var column: float = -column_offset if index % 2 == 0 else column_offset
		var distance: float = 10.0 + float(row) * row_spacing
		var sample: Dictionary = _sample_at_distance(distance)
		var position: Vector2 = sample["position"]
		var heading: float = sample["heading"]
		var lateral: Vector2 = TrackPlan.right_vector(heading) * column
		var origin: Vector3 = Vector3(position.x + lateral.x, Tuning.ride_height, position.y + lateral.y)
		spawns.append(Transform3D(Basis(Vector3.UP, heading), origin))
	return spawns


## Grand plan d'herbe avec collision : rattrape la voiture hors de la piste.
func _build_ground(parent: Node3D) -> void:
	var size: float = 900.0
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = LAYER_GROUND
	body.collision_mask = 0

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(size, 2.0, size)
	shape.shape = box
	shape.position = Vector3(0.0, GROUND_Y - 1.0, 0.0)
	body.add_child(shape)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(size, size)
	mesh_instance.mesh = plane
	mesh_instance.material_override = _make_material(Color(0.24, 0.31, 0.22), 0.95)
	mesh_instance.position = Vector3(0.0, GROUND_Y, 0.0)
	body.add_child(mesh_instance)

	# Recentrer le sol sur le circuit plutot que sur l'origine du monde.
	body.position = Vector3(_bounds_center().x, 0.0, _bounds_center().y)
	parent.add_child(body)


## Ruban d'asphalte suivant la ligne centrale.
func _build_asphalt(parent: Node3D) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)

	var half_width: float = _plan.width * 0.5
	for index: int in range(_points.size() - 1):
		var a_left: Vector3 = _edge_point(index, -half_width, ASPHALT_Y)
		var a_right: Vector3 = _edge_point(index, half_width, ASPHALT_Y)
		var b_left: Vector3 = _edge_point(index + 1, -half_width, ASPHALT_Y)
		var b_right: Vector3 = _edge_point(index + 1, half_width, ASPHALT_Y)
		# Deux triangles par segment, orientes vers le haut.
		surface.add_vertex(a_left)
		surface.add_vertex(b_left)
		surface.add_vertex(a_right)
		surface.add_vertex(a_right)
		surface.add_vertex(b_left)
		surface.add_vertex(b_right)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Asphalt"
	mesh_instance.mesh = surface.commit()
	mesh_instance.material_override = _make_material(Color(0.20, 0.20, 0.22), 0.92)
	parent.add_child(mesh_instance)


## Bandes transversales regulieres : le principal repere de vitesse.
func _build_stripes(parent: Node3D) -> void:
	var total: float = _track_length()
	var count: int = int(total / STRIPE_SPACING)
	if count <= 0:
		return

	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(_plan.width - 1.0, 0.04, STRIPE_DEPTH)
	multi.mesh = box
	multi.instance_count = count

	for index: int in count:
		var sample: Dictionary = _sample_at_distance(float(index) * STRIPE_SPACING)
		var position: Vector2 = sample["position"]
		var heading: float = sample["heading"]
		var transform: Transform3D = Transform3D(
			Basis(Vector3.UP, heading),
			Vector3(position.x, STRIPE_Y, position.y))
		multi.set_instance_transform(index, transform)
		# Une bande claire sur cinq est plus marquee : reperes de distance.
		var bright: bool = index % 5 == 0
		multi.set_instance_color(index, Color(0.92, 0.92, 0.88) if bright else Color(0.55, 0.56, 0.58))

	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = "Stripes"
	instance.multimesh = multi
	instance.material_override = _make_vertex_color_material()
	parent.add_child(instance)


## Murs bas des deux cotes : visuel en MultiMesh, collision en boites.
func _build_walls(parent: Node3D) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Walls"
	body.collision_layer = LAYER_WALL
	body.collision_mask = 0

	var half_width: float = _plan.width * 0.5 + WALL_THICKNESS * 0.5
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []

	for side: int in 2:
		var offset: float = -half_width if side == 0 else half_width
		var index: int = 0
		while index + WALL_SEGMENT_POINTS < _points.size():
			var start: Vector3 = _edge_point(index, offset, 0.0)
			var end: Vector3 = _edge_point(index + WALL_SEGMENT_POINTS, offset, 0.0)
			var segment: Vector3 = end - start
			var length: float = segment.length()
			if length < 0.01:
				index += WALL_SEGMENT_POINTS
				continue
			var middle: Vector3 = (start + end) * 0.5 + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
			var angle: float = atan2(-segment.x, -segment.z)
			var transform: Transform3D = Transform3D(Basis(Vector3.UP, angle), middle)

			var shape: CollisionShape3D = CollisionShape3D.new()
			var box_shape: BoxShape3D = BoxShape3D.new()
			box_shape.size = Vector3(WALL_THICKNESS, WALL_HEIGHT, length)
			shape.shape = box_shape
			shape.transform = transform
			body.add_child(shape)

			transforms.append(transform.scaled_local(Vector3(WALL_THICKNESS, WALL_HEIGHT, length)))
			# Alternance rouge / blanc : tres lisible a grande vitesse.
			colors.append(Color(0.78, 0.18, 0.16) if (index / WALL_SEGMENT_POINTS) % 2 == 0
				else Color(0.90, 0.90, 0.87))
			index += WALL_SEGMENT_POINTS

	parent.add_child(body)

	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index: int in transforms.size():
		multi.set_instance_transform(index, transforms[index])
		multi.set_instance_color(index, colors[index])

	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = "WallVisuals"
	instance.multimesh = multi
	instance.material_override = _make_vertex_color_material()
	parent.add_child(instance)


## Poteaux verticaux en bord de piste. Purement visuels : leur defilement est
## ce qui donne le mieux la sensation de vitesse.
func _build_posts(parent: Node3D) -> void:
	var total: float = _track_length()
	var count: int = int(total / POST_SPACING)
	if count <= 0:
		return

	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = POST_RADIUS
	cylinder.bottom_radius = POST_RADIUS
	cylinder.height = POST_HEIGHT
	cylinder.radial_segments = 6
	cylinder.rings = 1
	multi.mesh = cylinder
	multi.instance_count = count * 2

	var offset: float = _plan.width * 0.5 + POST_OFFSET
	for index: int in count:
		var sample: Dictionary = _sample_at_distance(float(index) * POST_SPACING)
		var position: Vector2 = sample["position"]
		var heading: float = sample["heading"]
		var lateral: Vector2 = TrackPlan.right_vector(heading) * offset
		for side: int in 2:
			var sign_value: float = -1.0 if side == 0 else 1.0
			var origin: Vector3 = Vector3(
				position.x + lateral.x * sign_value,
				POST_HEIGHT * 0.5,
				position.y + lateral.y * sign_value)
			var slot: int = index * 2 + side
			multi.set_instance_transform(slot, Transform3D(Basis.IDENTITY, origin))
			multi.set_instance_color(slot, Color(0.95, 0.78, 0.20))

	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = "Posts"
	instance.multimesh = multi
	instance.material_override = _make_vertex_color_material()
	parent.add_child(instance)


## Point situe a `offset` metres sur la droite du point echantillonne `index`.
func _edge_point(index: int, offset: float, height: float) -> Vector3:
	var position: Vector2 = _points[index]
	var lateral: Vector2 = TrackPlan.right_vector(_headings[index]) * offset
	return Vector3(position.x + lateral.x, height, position.y + lateral.y)


## Longueur totale de la ligne centrale, en metres.
func _track_length() -> float:
	var total: float = 0.0
	for index: int in range(_points.size() - 1):
		total += _points[index].distance_to(_points[index + 1])
	return total


## Position et cap a une distance donnee depuis le depart.
func _sample_at_distance(distance: float) -> Dictionary:
	var travelled: float = 0.0
	for index: int in range(_points.size() - 1):
		var segment: float = _points[index].distance_to(_points[index + 1])
		if travelled + segment >= distance:
			var t: float = (distance - travelled) / maxf(segment, 0.0001)
			return {
				"position": _points[index].lerp(_points[index + 1], t),
				"heading": _headings[index],
			}
		travelled += segment
	var last: int = _points.size() - 1
	return {"position": _points[last], "heading": _headings[last]}


## Centre de la boite englobante du trace, dans le plan horizontal.
func _bounds_center() -> Vector2:
	var minimum: Vector2 = _points[0]
	var maximum: Vector2 = _points[0]
	for point: Vector2 in _points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return (minimum + maximum) * 0.5


static func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material


## Materiau pour les MultiMesh colores instance par instance.
static func _make_vertex_color_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.85
	material.metallic = 0.0
	return material
