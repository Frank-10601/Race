extends Node
## Capture d'ecran automatique de la piste et du vehicule.
##
## Lancer (Linux sans ecran) :
##   xvfb-run -a godot --rendering-driver opengl3 res://tools/tests/screenshot.tscn
##
## Sert a verifier ce qui ne se voit pas dans les chiffres : materiaux, lumiere,
## orientation du vehicule, cadrage de la camera.

const TRACK_SCENE: String = "res://src/track/test_track.tscn"
const OUTPUT_DIR: String = "user://captures"

## Chaque prise : [nom, secondes de conduite, gaz, braquage, frein a main, vue].
const SHOTS: Array = [
	["01_grille", 0.2, 0.0, 0.0, false, ChaseCamera.View.CHASE],
	["02_ligne_droite", 2.5, 1.0, 0.0, false, ChaseCamera.View.CHASE],
	["03_derapage", 1.2, 1.0, 1.0, true, ChaseCamera.View.CHASE],
	["04_vue_rapprochee", 1.5, 1.0, 0.25, false, ChaseCamera.View.CLOSE],
	["05_vue_capot", 1.0, 1.0, 0.0, false, ChaseCamera.View.HOOD],
]

## Prise supplementaire depuis une camera fixe en hauteur : verifie la grille de
## depart au complet, ce que la camera de poursuite ne montre jamais.
const OVERVIEW_OFFSET: Vector3 = Vector3(0.0, 26.0, 26.0)

var _track: Node3D = null
var _vehicle: Vehicle = null
var _camera: ChaseCamera = null
var _index: int = 0
var _remaining: float = 0.0
var _settled: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var scene: PackedScene = load(TRACK_SCENE) as PackedScene
	_track = scene.instantiate() as Node3D
	add_child(_track)
	# Verification ciblee : RACE_NO_SHADOW=1 coupe les ombres pour distinguer un
	# vrai defaut de geometrie d'un artefact de la carte d'ombres.
	# La piste construit son soleil dans son `_ready`, deja execute a ce stade.
	if OS.get_environment("RACE_NO_SHADOW") == "1":
		var sun: DirectionalLight3D = _track.get_node_or_null("Sun") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = false
			print("ombres desactivees pour cette capture")

	_vehicle = Vehicle.new()
	_vehicle.configure(1, "Claude", 3, Vehicle.Mode.AUTHORITY, _track)
	add_child(_vehicle)
	_vehicle.setup_visuals(false)
	_vehicle.place_at(_track.call("get_spawn_transform", 0))

	# Quelques voisins de grille, pour verifier couleurs et etiquettes.
	for slot: int in range(1, 4):
		var other: Vehicle = Vehicle.new()
		other.configure(100 + slot, "Joueur %d" % slot, slot, Vehicle.Mode.AUTHORITY, _track)
		add_child(other)
		other.setup_visuals(false)
		other.place_at(_track.call("get_spawn_transform", slot))

	_camera = ChaseCamera.new()
	_camera.current = true
	add_child(_camera)
	_camera.set_target(_vehicle)
	_begin_shot()


func _physics_process(delta: float) -> void:
	_settled += 1
	if _settled < 4:
		return
	var shot: Array = SHOTS[_index]
	_vehicle.simulate(InputFrame.create(0, shot[2], 0.0, shot[3], shot[4], false), delta)
	_remaining -= delta
	if _remaining > 0.0:
		return
	set_physics_process(false)
	_capture.call_deferred(shot[0])


func _capture(name: String) -> void:
	# Plusieurs images d'attente : la camera, mais aussi la carte d'ombres,
	# doivent avoir rattrape la scene figee.
	for _frame: int in 12:
		await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [OUTPUT_DIR, name]
	image.save_png(path)
	print("capture : %s (%dx%d)" % [ProjectSettings.globalize_path(path),
		image.get_width(), image.get_height()])

	if OS.get_environment("RACE_DUMP_MESHES") == "1" and name == "02_ligne_droite":
		_dump_meshes()
	_index += 1
	if _index >= SHOTS.size():
		await _capture_overview()
		print("Captures terminees dans %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
		get_tree().quit()
		return
	_begin_shot()
	set_physics_process(true)


## Inventaire des objets susceptibles de projeter une ombre pres du vehicule.
## Sert a identifier une ombre orpheline autrement qu'en devinant.
func _dump_meshes() -> void:
	var reference: Vector3 = _vehicle.state.position
	print("--- objets a moins de 40 m du vehicule (%s) ---" % reference)
	_walk(self, reference)


func _walk(node: Node, reference: Vector3) -> void:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry != null:
		var distance: float = geometry.global_position.distance_to(reference)
		if distance < 40.0:
			print("  %-22s %-22s a %6.1f m  pos %s  ombre %d"
				% [node.name, node.get_class(), distance, geometry.global_position,
				geometry.cast_shadow])
	for child: Node in node.get_children():
		_walk(child, reference)


## Vue plongeante sur la grille de depart.
func _capture_overview() -> void:
	var overview: Camera3D = Camera3D.new()
	add_child(overview)
	var grid_centre: Vector3 = _track.call("get_spawn_transform", 2).origin
	overview.global_position = grid_centre + OVERVIEW_OFFSET
	overview.look_at(grid_centre, Vector3.UP)
	overview.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/06_grille_vue_densemble.png" % OUTPUT_DIR)
	print("capture : vue d'ensemble de la grille")


func _begin_shot() -> void:
	var shot: Array = SHOTS[_index]
	_remaining = shot[1]
	while _camera.get_view_name() != _view_name(shot[5]):
		_camera.cycle_view()


func _view_name(view: int) -> String:
	match view:
		ChaseCamera.View.CHASE:
			return "arriere"
		ChaseCamera.View.CLOSE:
			return "rapprochee"
		_:
			return "capot"
