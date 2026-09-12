class_name VehicleFactory
extends RefCounted
## Construit l'apparence d'un vehicule.
##
## PHASE 0 : uniquement des primitives Godot (boites, cylindres) avec des
## materiaux de couleur unie — aucun asset externe (CLAUDE.md, contrainte 4).
##
## PHASE 3 : il suffira de renseigner `model_path`. `_load_model()` cherchera
## dans le `.glb` les noeuds `Body`, `WheelFL`, `WheelFR`, `WheelRL`, `WheelRR`
## (voir `assets/vehicles/README.md`) et les branchera exactement aux memes
## emplacements. Le reste du code — physique, reseau, camera — n'a pas a changer :
## il ne connait que les noeuds retournes ici.

## Geometrie des roues, partagee avec l'animation visuelle.
const WHEEL_RADIUS: float = 0.38
const WHEEL_WIDTH: float = 0.32

## Emplacement des roues, en coordonnees locales, dans l'ordre
## avant-gauche, avant-droite, arriere-gauche, arriere-droite.
##
## L'ecartement (0,90 m) depasse volontairement la demi-largeur de la
## carrosserie visible : sinon les roues disparaissent dans la caisse et la
## voiture n'est plus qu'une boite qui glisse.
const WHEEL_POSITIONS: Array[Vector3] = [
	Vector3(-0.90, 0.0, -1.42),
	Vector3(0.90, 0.0, -1.42),
	Vector3(-0.90, 0.0, 1.42),
	Vector3(0.90, 0.0, 1.42),
]

## Carrosserie visible. Plus etroite et plus haute que la boite de collision :
## elle laisse voir les roues et degage le bas de caisse.
const BODY_SIZE: Vector3 = Vector3(1.62, 0.58, 4.05)
const BODY_HEIGHT_OFFSET: float = 0.17

## Les deux premieres roues braquent.
const STEERING_WHEEL_COUNT: int = 2

## Palette des joueurs. Couleurs franches et bien distinctes, y compris pour les
## formes courantes de daltonisme.
const PLAYER_COLORS: Array[Color] = [
	Color("#e8503a"), Color("#3a8ee8"), Color("#f2b134"), Color("#4caf6a"),
	Color("#9b59b6"), Color("#00b3a4"), Color("#e87fb0"), Color("#d9d2c5"),
	Color("#7a5c3e"), Color("#2f4a6d"), Color("#c2d63a"), Color("#ff8c42"),
]


static func get_player_color(index: int) -> Color:
	return PLAYER_COLORS[index % PLAYER_COLORS.size()]


## Carrosserie : un chassis, un toit et un pare-brise pour lire le sens de la
## voiture en un coup d'oeil, meme de loin.
static func create_body(color: Color) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Body"

	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = color
	# Peinture usee : peu metallique, plutot mate (voir la vision du projet).
	paint.metallic = 0.15
	paint.roughness = 0.55

	var chassis: MeshInstance3D = MeshInstance3D.new()
	chassis.name = "Chassis"
	var chassis_mesh: BoxMesh = BoxMesh.new()
	chassis_mesh.size = BODY_SIZE
	chassis.mesh = chassis_mesh
	chassis.material_override = paint
	chassis.position = Vector3(0.0, BODY_HEIGHT_OFFSET, 0.0)
	root.add_child(chassis)

	var roof: MeshInstance3D = MeshInstance3D.new()
	roof.name = "Roof"
	var roof_mesh: BoxMesh = BoxMesh.new()
	roof_mesh.size = Vector3(1.42, 0.52, 1.85)
	roof.mesh = roof_mesh
	roof.material_override = paint
	roof.position = Vector3(0.0, BODY_HEIGHT_OFFSET + BODY_SIZE.y * 0.5 + 0.22, 0.20)
	root.add_child(roof)

	# Pare-chocs sombres : sans eux, la voiture n'est qu'un bloc de couleur unie
	# dont on ne distingue pas l'avant de l'arriere.
	var trim: StandardMaterial3D = StandardMaterial3D.new()
	trim.albedo_color = Color(0.13, 0.13, 0.15)
	trim.roughness = 0.8
	for side: int in 2:
		var bumper: MeshInstance3D = MeshInstance3D.new()
		bumper.name = "Bumper%d" % side
		var bumper_mesh: BoxMesh = BoxMesh.new()
		bumper_mesh.size = Vector3(BODY_SIZE.x + 0.10, 0.26, 0.22)
		bumper.mesh = bumper_mesh
		bumper.material_override = trim
		var z: float = -BODY_SIZE.z * 0.5 if side == 0 else BODY_SIZE.z * 0.5
		bumper.position = Vector3(0.0, BODY_HEIGHT_OFFSET - 0.12, z)
		root.add_child(bumper)

	# Deux phares clairs a l'avant : reperer le sens de la voiture d'un coup
	# d'oeil compte plus que le detail, surtout de loin.
	var light_material: StandardMaterial3D = StandardMaterial3D.new()
	light_material.albedo_color = Color(0.97, 0.95, 0.80)
	light_material.emission_enabled = true
	light_material.emission = Color(0.9, 0.88, 0.7)
	light_material.emission_energy_multiplier = 0.6
	for side: int in 2:
		var light: MeshInstance3D = MeshInstance3D.new()
		light.name = "Headlight%d" % side
		var light_mesh: BoxMesh = BoxMesh.new()
		light_mesh.size = Vector3(0.34, 0.16, 0.12)
		light.mesh = light_mesh
		light.material_override = light_material
		var x: float = -0.52 if side == 0 else 0.52
		light.position = Vector3(x, BODY_HEIGHT_OFFSET + 0.06, -BODY_SIZE.z * 0.5)
		root.add_child(light)

	var glass_material: StandardMaterial3D = StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.10, 0.13, 0.17)
	glass_material.metallic = 0.3
	glass_material.roughness = 0.25

	var windshield: MeshInstance3D = MeshInstance3D.new()
	windshield.name = "Windshield"
	var glass_mesh: BoxMesh = BoxMesh.new()
	glass_mesh.size = Vector3(1.34, 0.40, 0.16)
	windshield.mesh = glass_mesh
	windshield.material_override = glass_material
	windshield.position = Vector3(0.0, BODY_HEIGHT_OFFSET + BODY_SIZE.y * 0.5 + 0.24, -0.70)
	root.add_child(windshield)

	return root


## Une roue : le noeud retourne porte le braquage (axe Y) et le roulement
## (axe X). L'ordre d'Euler de Godot etant YXZ, les deux rotations se combinent
## correctement sans noeud intermediaire.
static func create_wheel(name_suffix: String) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = "Wheel" + name_suffix

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.09, 0.10)
	material.roughness = 0.95

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = WHEEL_RADIUS
	cylinder.bottom_radius = WHEEL_RADIUS
	cylinder.height = WHEEL_WIDTH
	cylinder.radial_segments = 14
	cylinder.rings = 1
	mesh_instance.mesh = cylinder
	# Le cylindre de Godot a son axe sur Y : on le couche sur l'axe X.
	mesh_instance.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
	mesh_instance.material_override = material
	pivot.add_child(mesh_instance)

	# Repere clair sur le flanc : rend la rotation des roues visible.
	var marker_material: StandardMaterial3D = StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.65, 0.65, 0.68)
	marker_material.roughness = 0.4

	var hub: MeshInstance3D = MeshInstance3D.new()
	hub.name = "Hub"
	var hub_mesh: BoxMesh = BoxMesh.new()
	hub_mesh.size = Vector3(WHEEL_WIDTH + 0.02, WHEEL_RADIUS * 1.1, 0.09)
	hub.mesh = hub_mesh
	hub.material_override = marker_material
	pivot.add_child(hub)

	return pivot


## Etiquette du pseudo, affichee au-dessus de la voiture.
static func create_name_tag(player_name: String) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "NameTag"
	label.text = player_name
	label.font_size = 96
	label.pixel_size = 0.0045
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.fixed_size = false
	label.outline_size = 26
	label.modulate = Color(1.0, 1.0, 1.0)
	label.outline_modulate = Color(0.05, 0.05, 0.08, 0.85)
	label.position = Vector3(0.0, 1.85, 0.0)
	# Ne gene pas la lisibilite quand deux voitures se superposent.
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	# Une etiquette de texte ne doit pas projeter d'ombre : en billboard, elle
	# pivote avec la camera et son ombre se promene sur la piste.
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label


## Point d'entree de la phase 3 : charge un modele `.glb` et en extrait la
## carrosserie et les quatre roues. Retourne un dictionnaire vide si le modele
## est absent, ce qui fait retomber l'appelant sur les primitives.
static func load_model(model_path: String) -> Dictionary:
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return {}
	var scene: PackedScene = load(model_path) as PackedScene
	if scene == null:
		push_warning("Modele de vehicule illisible : %s" % model_path)
		return {}
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		return {}

	var body: Node3D = instance.find_child("Body", true, false) as Node3D
	var wheels: Array[Node3D] = []
	for suffix: String in ["FL", "FR", "RL", "RR"]:
		var wheel: Node3D = instance.find_child("Wheel" + suffix, true, false) as Node3D
		if wheel == null:
			push_warning("Roue Wheel%s absente de %s : primitives utilisees." % [suffix, model_path])
			instance.queue_free()
			return {}
		wheels.append(wheel)
	if body == null:
		push_warning("Noeud Body absent de %s : primitives utilisees." % model_path)
		instance.queue_free()
		return {}

	return {"root": instance, "body": body, "wheels": wheels}
