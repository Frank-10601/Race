extends Node
## Photographie un modele sous quatre angles, pour decider de son orientation.
##
## Un fichier .glb ne dit pas ou se trouve l'avant de la voiture : il faut le
## regarder. Ce script evite d'ouvrir Blender pour cela.
##
##   MODEL=res://chemin.glb xvfb-run -a godot --rendering-driver opengl3 \
##     res://tools/tests/model_preview.tscn

const OUTPUT_DIR: String = "user://previews"

## [nom, direction de la camera par rapport au modele]
const VIEWS: Array = [
	["plus_x", Vector3(1.0, 0.25, 0.0)],
	["moins_x", Vector3(-1.0, 0.25, 0.0)],
	["plus_z", Vector3(0.0, 0.25, 1.0)],
	["moins_z", Vector3(0.0, 0.25, -1.0)],
	["dessus", Vector3(0.01, 1.0, 0.0)],
]

var _model: Node3D = null
var _camera: Camera3D = null
var _index: int = 0
var _size: Vector3 = Vector3.ONE
var _centre: Vector3 = Vector3.ZERO


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var path: String = OS.get_environment("MODEL")
	if path.is_empty():
		printerr("Indiquer le modele : MODEL=res://... ")
		get_tree().quit(1)
		return

	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		printerr("Modele illisible : %s" % path)
		get_tree().quit(1)
		return
	_model = scene.instantiate() as Node3D
	add_child(_model)

	var bounds: AABB = _compute_bounds(_model)
	_size = bounds.size
	_centre = bounds.get_center()
	print("dimensions : %.3f x %.3f x %.3f m" % [_size.x, _size.y, _size.z])
	print("centre     : %.3f %.3f %.3f" % [_centre.x, _centre.y, _centre.z])

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, 130.0, 0.0)
	light.light_energy = 1.3
	add_child(light)

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.18, 0.22)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.65, 0.72)
	environment.ambient_light_energy = 0.7
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_shoot.call_deferred()


func _shoot() -> void:
	if _index >= VIEWS.size():
		print("Captures dans %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
		get_tree().quit()
		return

	var view: Array = VIEWS[_index]
	var direction: Vector3 = (view[1] as Vector3).normalized()
	var distance: float = maxf(_size.length(), 0.5) * 1.35
	_camera.global_position = _centre + direction * distance
	_camera.look_at(_centre, Vector3.UP)

	for _frame: int in 4:
		await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUTPUT_DIR, view[0]])
	print("vue %s depuis %s" % [view[0], direction])
	_index += 1
	_shoot.call_deferred()


## Boite englobante de tous les maillages du modele.
func _compute_bounds(node: Node) -> AABB:
	var bounds: AABB = AABB()
	var started: bool = false
	for child: Node in _all_nodes(node):
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		bounds = box if not started else bounds.merge(box)
		started = true
	return bounds


func _all_nodes(node: Node) -> Array[Node]:
	var nodes: Array[Node] = [node]
	for child: Node in node.get_children():
		nodes.append_array(_all_nodes(child))
	return nodes
