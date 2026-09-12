extends Node
## Chargeur des reglages du jeu (autoload `Tuning`).
##
## Lit `src/config/tuning.cfg` et expose chaque reglage comme propriete typee.
## Aucune valeur de reglage ne doit apparaitre ailleurs dans le code.
##
## En multijoueur, le SERVEUR est la seule source de verite : il envoie ses
## reglages au client a la connexion (`to_dict()` / `apply_dict()`), sinon la
## prediction du client donnerait un resultat different de la simulation
## serveur et la voiture serait corrigee a chaque paquet.

signal settings_changed

const CONFIG_PATH: String = "res://src/config/tuning.cfg"

# --- [vehicle] ---------------------------------------------------------------
var engine_acceleration: float = 28.0
var max_speed: float = 45.0
var max_reverse_speed: float = 12.0
var brake_force: float = 55.0
var engine_braking: float = 9.0
var rolling_resistance: float = 0.06
var steer_rate: float = 145.0
var steer_rate_at_max_speed: float = 0.35
var steer_response: float = 10.0
var steer_visual_angle: float = 32.0
var air_steer_factor: float = 0.30

# --- [grip] ------------------------------------------------------------------
var lateral_grip: float = 7.0
var handbrake_grip: float = 0.9
var handbrake_yaw_boost: float = 0.45
var handbrake_braking: float = 6.0
var grip_recovery: float = 3.5
var drift_min_speed: float = 7.0
var drift_slip_damping: float = 2.0
var downforce_grip_bonus: float = 0.35

# --- [ground] ----------------------------------------------------------------
var gravity: float = 28.0
var ride_height: float = 0.42
var ground_ray_length: float = 1.30
var ground_snap_speed: float = 14.0
var align_to_ground_speed: float = 12.0
var align_in_air_speed: float = 2.5
var wall_bounce: float = 0.25
var wall_speed_loss: float = 0.45

# --- [respawn] ---------------------------------------------------------------
var upside_down_angle: float = 65.0
var stuck_time: float = 3.0
var stuck_speed: float = 1.5
var fall_height: float = -25.0
var spawn_height: float = 1.0

# --- [camera] ----------------------------------------------------------------
var chase_distance: float = 6.8
var chase_height: float = 2.5
var follow_speed: float = 9.0
var look_speed: float = 11.0
var speed_pullback: float = 2.5
var corner_tilt: float = 4.0
var base_fov: float = 68.0
var speed_fov_gain: float = 14.0
var close_distance: float = 4.5
var close_height: float = 1.9
var hood_forward: float = 0.35
var hood_height: float = 1.15

# --- [network] ---------------------------------------------------------------
var physics_tick_rate: int = 60
var state_send_rate: int = 20
var input_send_rate: int = 60
var interpolation_delay_ms: int = 100
var max_extrapolation_ms: int = 150
var server_input_buffer_ticks: int = 2
var reconciliation_position_threshold: float = 0.02
var reconciliation_rotation_threshold: float = 1.0
var visual_correction_time: float = 0.12
var input_history_size: int = 128
var max_replay_steps: int = 30
var max_players: int = 12
var default_port: int = 8910
var default_transport: String = "websocket"

# --- Valeurs derivees (recalculees apres chaque chargement) -------------------
var physics_delta: float = 1.0 / 60.0          ## duree d'un pas de simulation
var state_send_interval: float = 1.0 / 20.0    ## intervalle d'envoi serveur
var interpolation_delay: float = 0.1           ## retard d'affichage, en secondes
var max_extrapolation: float = 0.15            ## extrapolation max, en secondes
var reconciliation_rotation_rad: float = 0.017 ## seuil d'orientation, en radians
var steer_rate_rad: float = 2.53               ## braquage max, en radians/seconde
var steer_visual_angle_rad: float = 0.558      ## angle visuel des roues, radians
var upside_down_dot: float = 0.42              ## produit scalaire seuil de retournement

## Descripteurs : [nom de la propriete, section du .cfg, cle du .cfg].
## Une seule table pour le chargement, l'envoi reseau et la validation.
const _FLOAT_KEYS: Array = [
	["engine_acceleration", "vehicle", "engine_acceleration"],
	["max_speed", "vehicle", "max_speed"],
	["max_reverse_speed", "vehicle", "max_reverse_speed"],
	["brake_force", "vehicle", "brake_force"],
	["engine_braking", "vehicle", "engine_braking"],
	["rolling_resistance", "vehicle", "rolling_resistance"],
	["steer_rate", "vehicle", "steer_rate"],
	["steer_rate_at_max_speed", "vehicle", "steer_rate_at_max_speed"],
	["steer_response", "vehicle", "steer_response"],
	["steer_visual_angle", "vehicle", "steer_visual_angle"],
	["air_steer_factor", "vehicle", "air_steer_factor"],
	["lateral_grip", "grip", "lateral_grip"],
	["handbrake_grip", "grip", "handbrake_grip"],
	["handbrake_yaw_boost", "grip", "handbrake_yaw_boost"],
	["handbrake_braking", "grip", "handbrake_braking"],
	["grip_recovery", "grip", "grip_recovery"],
	["drift_min_speed", "grip", "drift_min_speed"],
	["drift_slip_damping", "grip", "drift_slip_damping"],
	["downforce_grip_bonus", "grip", "downforce_grip_bonus"],
	["gravity", "ground", "gravity"],
	["ride_height", "ground", "ride_height"],
	["ground_ray_length", "ground", "ground_ray_length"],
	["ground_snap_speed", "ground", "ground_snap_speed"],
	["align_to_ground_speed", "ground", "align_to_ground_speed"],
	["align_in_air_speed", "ground", "align_in_air_speed"],
	["wall_bounce", "ground", "wall_bounce"],
	["wall_speed_loss", "ground", "wall_speed_loss"],
	["upside_down_angle", "respawn", "upside_down_angle"],
	["stuck_time", "respawn", "stuck_time"],
	["stuck_speed", "respawn", "stuck_speed"],
	["fall_height", "respawn", "fall_height"],
	["spawn_height", "respawn", "spawn_height"],
	["chase_distance", "camera", "chase_distance"],
	["chase_height", "camera", "chase_height"],
	["follow_speed", "camera", "follow_speed"],
	["look_speed", "camera", "look_speed"],
	["speed_pullback", "camera", "speed_pullback"],
	["corner_tilt", "camera", "corner_tilt"],
	["base_fov", "camera", "base_fov"],
	["speed_fov_gain", "camera", "speed_fov_gain"],
	["close_distance", "camera", "close_distance"],
	["close_height", "camera", "close_height"],
	["hood_forward", "camera", "hood_forward"],
	["hood_height", "camera", "hood_height"],
	["reconciliation_position_threshold", "network", "reconciliation_position_threshold"],
	["reconciliation_rotation_threshold", "network", "reconciliation_rotation_threshold"],
	["visual_correction_time", "network", "visual_correction_time"],
]

const _INT_KEYS: Array = [
	["physics_tick_rate", "network", "physics_tick_rate"],
	["state_send_rate", "network", "state_send_rate"],
	["input_send_rate", "network", "input_send_rate"],
	["interpolation_delay_ms", "network", "interpolation_delay_ms"],
	["max_extrapolation_ms", "network", "max_extrapolation_ms"],
	["server_input_buffer_ticks", "network", "server_input_buffer_ticks"],
	["input_history_size", "network", "input_history_size"],
	["max_replay_steps", "network", "max_replay_steps"],
	["max_players", "network", "max_players"],
	["default_port", "network", "default_port"],
]

const _STRING_KEYS: Array = [
	["default_transport", "network", "default_transport"],
]


func _ready() -> void:
	load_from_file()


## Charge `tuning.cfg`. Les valeurs absentes gardent leur valeur par defaut.
func load_from_file() -> void:
	var config: ConfigFile = ConfigFile.new()
	var error: int = config.load(CONFIG_PATH)
	if error != OK:
		push_warning("Reglages introuvables (%s) : valeurs par defaut utilisees." % CONFIG_PATH)
		_refresh_derived()
		return

	for entry: Array in _FLOAT_KEYS:
		var property: String = entry[0]
		if config.has_section_key(entry[1], entry[2]):
			set(property, float(config.get_value(entry[1], entry[2])))
	for entry: Array in _INT_KEYS:
		var property: String = entry[0]
		if config.has_section_key(entry[1], entry[2]):
			set(property, int(config.get_value(entry[1], entry[2])))
	for entry: Array in _STRING_KEYS:
		var property: String = entry[0]
		if config.has_section_key(entry[1], entry[2]):
			set(property, str(config.get_value(entry[1], entry[2])))

	_validate()
	_refresh_derived()
	settings_changed.emit()


## Serialise les reglages pour les envoyer du serveur vers les clients.
func to_dict() -> Dictionary:
	var data: Dictionary = {}
	for table: Array in [_FLOAT_KEYS, _INT_KEYS, _STRING_KEYS]:
		for entry: Array in table:
			var property: String = entry[0]
			data[property] = get(property)
	return data


## Applique les reglages recus du serveur. Indispensable pour que la prediction
## du client corresponde exactement a la simulation serveur.
func apply_dict(data: Dictionary) -> void:
	for entry: Array in _FLOAT_KEYS:
		var property: String = entry[0]
		if data.has(property):
			set(property, float(data[property]))
	for entry: Array in _INT_KEYS:
		var property: String = entry[0]
		if data.has(property):
			set(property, int(data[property]))
	for entry: Array in _STRING_KEYS:
		var property: String = entry[0]
		if data.has(property):
			set(property, str(data[property]))
	_validate()
	_refresh_derived()
	settings_changed.emit()


## Borne les valeurs qui casseraient le jeu si elles etaient mal saisies.
func _validate() -> void:
	physics_tick_rate = clampi(physics_tick_rate, 20, 120)
	state_send_rate = clampi(state_send_rate, 5, physics_tick_rate)
	input_send_rate = clampi(input_send_rate, 10, physics_tick_rate)
	server_input_buffer_ticks = clampi(server_input_buffer_ticks, 0, 10)
	input_history_size = clampi(input_history_size, 32, 1024)
	max_replay_steps = clampi(max_replay_steps, 4, input_history_size)
	max_players = clampi(max_players, 1, 64)
	default_port = clampi(default_port, 1024, 65535)
	max_extrapolation_ms = clampi(max_extrapolation_ms, 0, 1000)

	# Il faut au moins deux intervalles d'envoi en tampon, sinon l'interpolation
	# manque de points et les autres voitures saccadent.
	var minimum_delay: int = int(ceil(2000.0 / float(state_send_rate)))
	if interpolation_delay_ms < minimum_delay:
		push_warning("interpolation_delay_ms releve de %d a %d ms (minimum : 2 intervalles a %d Hz)."
			% [interpolation_delay_ms, minimum_delay, state_send_rate])
		interpolation_delay_ms = minimum_delay

	if ground_ray_length <= ride_height:
		push_warning("ground_ray_length doit depasser ride_height : ajuste a %.2f m."
			% (ride_height + 0.5))
		ground_ray_length = ride_height + 0.5

	if handbrake_grip >= lateral_grip:
		push_warning("handbrake_grip doit rester inferieur a lateral_grip, sinon le frein a main ne fait rien derapper.")

	if default_transport != "websocket" and default_transport != "enet":
		push_warning("default_transport inconnu (%s) : websocket utilise." % default_transport)
		default_transport = "websocket"


## Recalcule les valeurs derivees des reglages bruts.
func _refresh_derived() -> void:
	physics_delta = 1.0 / float(physics_tick_rate)
	state_send_interval = 1.0 / float(state_send_rate)
	interpolation_delay = float(interpolation_delay_ms) / 1000.0
	max_extrapolation = float(max_extrapolation_ms) / 1000.0
	reconciliation_rotation_rad = deg_to_rad(reconciliation_rotation_threshold)
	steer_rate_rad = deg_to_rad(steer_rate)
	steer_visual_angle_rad = deg_to_rad(steer_visual_angle)
	upside_down_dot = cos(deg_to_rad(upside_down_angle))
	Engine.physics_ticks_per_second = physics_tick_rate
