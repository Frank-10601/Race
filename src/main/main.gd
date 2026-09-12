extends Node
## Point d'entree du jeu : aiguille vers l'un des modes de lancement.
##
##   godot                                  menu
##   godot -- --solo                        conduite seule, sans reseau
##   godot -- --host                        heberge et joue
##   godot --headless -- --server           serveur dedie, sans affichage
##   godot -- --join 127.0.0.1              rejoint un serveur
##
## Dans un navigateur, les memes options passent par l'URL :
##   index.html?join=mon-serveur.fr&port=8910

const CAMERA_SCRIPT: String = "res://src/camera/chase_camera.gd"

@onready var _menu: Control = $UI/MainMenu
@onready var _hud: Control = $UI/Hud
@onready var _debug_panel: PanelContainer = $UI/DebugPanel

var _args: CliArgs = null
var _world: RaceWorld = null
var _camera: ChaseCamera = null
var _diagnostics: Diagnostics = null


func _ready() -> void:
	_args = CliArgs.parse()
	print("[lancement] %s" % _args.describe())
	Net.lag.round_trip_ms = _args.lag_ms
	Net.lag.jitter_ms = _args.jitter_ms

	_menu.host_requested.connect(_on_host_requested)
	_menu.join_requested.connect(_on_join_requested)
	Net.server_closed.connect(_on_server_closed)
	Net.connection_failed.connect(_on_connection_failed)

	match _args.launch:
		CliArgs.Launch.DEDICATED:
			_start_dedicated_server()
		CliArgs.Launch.HOST:
			_start_host(_args.player_name, _args.port)
		CliArgs.Launch.CLIENT:
			_start_client(_args.player_name, _args.address, _args.port)
		CliArgs.Launch.SOLO:
			_start_solo(_args.player_name)
		_:
			_show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("camera_cycle") and _camera != null:
		_camera.cycle_view()
		_hud.call("show_notice", "Camera : %s" % _camera.get_view_name())
	elif event.is_action("debug_panel"):
		_debug_panel.call("toggle")
	elif event.is_action("ui_quit") and not OS.has_feature("web"):
		get_tree().quit()


# --- Modes de lancement ------------------------------------------------------

func _show_menu() -> void:
	_menu.call("set_menu_active", true)
	_hud.visible = false


func _start_dedicated_server() -> void:
	# Aucun affichage : pas de camera, pas d'interface, pas de vehicule local.
	_menu.queue_free()
	_hud.queue_free()
	_debug_panel.queue_free()
	Net.local_player_name = "Serveur"
	_create_world()
	if not Net.host(_args.port, _args.transport, true):
		push_error("[serveur] demarrage impossible.")
		get_tree().quit(1)
		return
	print("[serveur] pret. Ctrl+C pour arreter.")


func _start_host(player_name: String, port: int) -> void:
	Net.local_player_name = player_name
	_create_world()
	if not Net.host(port, _args.transport, false):
		_show_menu()
		_menu.call("show_status", "Impossible d'ouvrir le port %d." % port)
		return
	_enter_race()


func _start_client(player_name: String, address: String, port: int) -> void:
	Net.local_player_name = player_name
	_create_world()
	if not Net.join(address, port, _args.transport):
		_show_menu()
		return
	_enter_race()


## Conduite seule, sans reseau : le meme monde, la meme simulation, mais aucune
## connexion. C'est le mode a utiliser pour regler le ressenti.
func _start_solo(player_name: String) -> void:
	Net.local_player_name = player_name
	_create_world()
	_world.create_solo_vehicle(player_name)
	_enter_race()


# --- Assemblage --------------------------------------------------------------

func _create_world() -> void:
	_world = RaceWorld.new()
	_world.name = "RaceWorld"
	_world.local_vehicle_ready.connect(_on_local_vehicle_ready)
	# Insere avant l'interface pour que la scene 3D soit dessinee dessous.
	add_child(_world)
	move_child(_world, 0)

	if _args.lag_ms > 0.0:
		print("[reseau] latence simulee : %.0f ms aller-retour (gigue %.0f ms)"
			% [_args.lag_ms, _args.jitter_ms])
	if _args.autopilot:
		print("[essai] pilote automatique actif")
	if _args.diagnostics:
		_diagnostics = Diagnostics.new()
		_diagnostics.name = "Diagnostics"
		_diagnostics.setup(_world)
		add_child(_diagnostics)


func _enter_race() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.call("set_menu_active", false)
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = true
	if _debug_panel != null and is_instance_valid(_debug_panel):
		_debug_panel.call("setup", _world)


func _on_local_vehicle_ready(vehicle: Vehicle) -> void:
	if Net.is_dedicated():
		return
	if _camera == null:
		_camera = ChaseCamera.new()
		_camera.name = "ChaseCamera"
		_camera.current = true
		_world.add_child(_camera)
	_camera.set_target(vehicle)
	_hud.call("set_vehicle", vehicle)
	vehicle.respawned.connect(_on_vehicle_respawned)


func _on_vehicle_respawned(reason: String) -> void:
	_hud.call("show_notice", "Remise en piste : %s" % reason)


# --- Retours du reseau -------------------------------------------------------

func _on_host_requested(player_name: String, port: int) -> void:
	_start_host(player_name, port)


func _on_join_requested(player_name: String, address: String, port: int) -> void:
	_start_client(player_name, address, port)


func _on_connection_failed(reason: String) -> void:
	_teardown_world()
	_show_menu()
	_menu.call("show_status", reason)


func _on_server_closed() -> void:
	_teardown_world()
	_show_menu()
	_menu.call("show_status", "Le serveur s'est arrete.")


func _teardown_world() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.queue_free()
		_camera = null
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null
	Net.shutdown()
