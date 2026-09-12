class_name RaceWorld
extends Node
## Orchestration de la course : piste, vehicules, entrees, etats.
##
## C'est ici que vit la boucle serveur autoritaire. Repartition des roles :
##
##   SERVEUR   simule tous les vehicules a `physics_tick_rate` (60 Hz) a partir
##             des entrees recues, puis diffuse l'etat du monde a
##             `state_send_rate` (20 Hz).
##   CLIENT    simule SA voiture immediatement (prediction), envoie ses entrees,
##             et interpole les voitures des autres.
##   SOLO      se comporte comme un serveur sans reseau : la meme simulation,
##             exactement le meme code.
##
## Sur `MultiplayerSpawner` et `MultiplayerSynchronizer` : le premier est
## utilise, c'est exactement son role — repliquer l'apparition et la
## disparition des vehicules. Le second ne convient pas ici et a ete remplace
## par un envoi groupe (voir `docs/NOTES.md`) : il lui manque le numero de
## sequence acquitte, propre a chaque client, sans lequel la reconciliation est
## impossible ; il emettrait de plus un paquet par vehicule au lieu d'un seul.

signal local_vehicle_ready(vehicle: Vehicle)

const TRACK_SCENE: String = "res://src/track/test_track.tscn"

## Entrees renvoyees a chaque paquet pour absorber une perte.
const INPUT_REDUNDANCY: int = 3

var track: Node3D = null
var local_vehicle: Vehicle = null
var lag: LagSimulator = LagSimulator.new()

var _vehicles: Dictionary = {}          ## peer_id -> Vehicle
var _vehicle_container: Node3D = null
var _spawner: MultiplayerSpawner = null

# --- Cote serveur ---
var _input_queues: Dictionary = {}      ## peer_id -> Array[InputFrame]
var _last_processed: Dictionary = {}    ## peer_id -> int
var _last_input: Dictionary = {}        ## peer_id -> InputFrame
var _spawn_slots: Dictionary = {}       ## peer_id -> int
var _send_accumulator: float = 0.0
var _next_spawn_slot: int = 0

# --- Cote client ---
var _input_accumulator: float = 0.0


func _ready() -> void:
	_vehicle_container = Node3D.new()
	_vehicle_container.name = "Vehicles"
	add_child(_vehicle_container)

	_spawner = MultiplayerSpawner.new()
	_spawner.name = "VehicleSpawner"
	add_child(_spawner)
	# Chemin RELATIF au spawner, et assigne une fois le spawner dans l'arbre :
	# un chemin absolu ne se resout pas depuis un noeud detache.
	_spawner.spawn_path = NodePath("../Vehicles")
	_spawner.spawn_function = _spawn_vehicle

	var scene: PackedScene = load(TRACK_SCENE) as PackedScene
	track = scene.instantiate() as Node3D
	add_child(track)

	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)


func _physics_process(delta: float) -> void:
	lag.process(delta)
	if Net.is_server() or not Net.is_online():
		_server_tick(delta)
	elif Net.is_connected_to_server():
		_client_tick(delta)


func _process(delta: float) -> void:
	if Net.mode != Net.Mode.CLIENT:
		return
	Net.clock.advance(delta)
	var render_time: float = Net.clock.get_render_time()
	for vehicle: Vehicle in _vehicles.values():
		if vehicle.mode == Vehicle.Mode.INTERPOLATED:
			vehicle.update_interpolated(render_time)


# --- Boucle serveur (et solo) ------------------------------------------------

func _server_tick(delta: float) -> void:
	Net.clock.tick()

	for peer_id: int in _vehicles:
		var vehicle: Vehicle = _vehicles[peer_id]
		var input: InputFrame
		if vehicle.mode == Vehicle.Mode.AUTHORITY and peer_id == Net.local_peer_id():
			# Hote ou jeu solo : le joueur local fournit ses entrees directement.
			input = PlayerInput.sample(vehicle.next_sequence())
		else:
			input = _consume_input(peer_id)
		vehicle.simulate(input, delta)

	if not Net.is_online():
		return

	_send_accumulator += delta
	if _send_accumulator < Tuning.state_send_interval:
		return
	_send_accumulator = 0.0
	_broadcast_snapshot()


## Preleve la prochaine entree d'un joueur.
##
## Le serveur garde volontairement quelques entrees d'avance
## (`server_input_buffer_ticks`) pour absorber la gigue du reseau. Quand la
## file est vide, il REPETE la derniere entree connue plutot que de rendre la
## main : sur une voiture, une entree manquante se traduirait par un a-coup de
## deceleration tres desagreable.
func _consume_input(peer_id: int) -> InputFrame:
	var queue: Array = _input_queues.get(peer_id, [])
	if queue.size() > Tuning.server_input_buffer_ticks:
		var frame: InputFrame = queue.pop_front()
		_last_processed[peer_id] = frame.sequence
		_last_input[peer_id] = frame
		return frame

	var previous: InputFrame = _last_input.get(peer_id, null)
	if previous == null:
		return InputFrame.neutral(0)
	# La remise en piste ne se repete pas : une pression sur R ne doit pas
	# declencher plusieurs reapparitions.
	var repeated: InputFrame = previous.duplicate_frame()
	repeated.respawn = false
	return repeated


func _broadcast_snapshot() -> void:
	var count: int = _vehicles.size()
	if count == 0:
		return

	var peer_ids: PackedInt32Array = PackedInt32Array()
	var data: PackedFloat32Array = PackedFloat32Array()
	peer_ids.resize(count)
	data.resize(count * VehicleState.ENCODED_FLOATS)

	var index: int = 0
	for peer_id: int in _vehicles:
		peer_ids[index] = peer_id
		var floats: PackedFloat32Array = _vehicles[peer_id].state.to_floats()
		for value_index: int in VehicleState.ENCODED_FLOATS:
			data[index * VehicleState.ENCODED_FLOATS + value_index] = floats[value_index]
		index += 1

	var tick: int = Net.clock.server_tick
	# Un envoi par client : chacun doit recevoir SON numero de sequence
	# acquitte, sans lequel il ne peut pas se reconcilier.
	for peer_id: int in Net.players:
		if peer_id == Net.SERVER_PEER_ID:
			continue
		var acked: int = _last_processed.get(peer_id, 0)
		_receive_snapshot.rpc_id(peer_id, tick, peer_ids, data, acked)


# --- Boucle client -----------------------------------------------------------

func _client_tick(delta: float) -> void:
	if local_vehicle == null:
		return

	var sequence: int = local_vehicle.next_sequence()
	var input: InputFrame = PlayerInput.sample(sequence)
	local_vehicle.predict(input, delta)

	_input_accumulator += delta
	var send_interval: float = 1.0 / float(Tuning.input_send_rate)
	if _input_accumulator < send_interval:
		return
	_input_accumulator = 0.0

	var pending: Array[InputFrame] = local_vehicle.get_pending_inputs()
	if pending.is_empty():
		return
	_receive_inputs.rpc_id(Net.SERVER_PEER_ID, InputFrame.encode_batch(pending))


# --- Echanges reseau ---------------------------------------------------------

## Entrees d'un client. Le serveur est le seul destinataire legitime.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_inputs(buffer: PackedByteArray) -> void:
	if not Net.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	lag.deliver(_apply_received_inputs, [peer_id, buffer])


func _apply_received_inputs(peer_id: int, buffer: PackedByteArray) -> void:
	if not _vehicles.has(peer_id):
		return
	var frames: Array[InputFrame] = InputFrame.decode_batch(buffer)
	var queue: Array = _input_queues.get(peer_id, [])
	var processed: int = _last_processed.get(peer_id, 0)
	var newest: int = queue[queue.size() - 1].sequence if not queue.is_empty() else processed
	for frame: InputFrame in frames:
		# On ignore ce qui est deja traite ou deja en file : les entrees sont
		# renvoyees plusieurs fois pour survivre a une perte.
		if frame.sequence <= processed or frame.sequence <= newest:
			continue
		queue.append(frame)
		newest = frame.sequence
	# Garde-fou : un client qui enverrait sans fin ne doit pas faire gonfler la
	# memoire du serveur.
	while queue.size() > Tuning.input_history_size:
		queue.pop_front()
	_input_queues[peer_id] = queue


## Etat du monde diffuse par le serveur.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_snapshot(tick: int, peer_ids: PackedInt32Array,
		data: PackedFloat32Array, acked: int) -> void:
	lag.deliver(_apply_snapshot, [tick, peer_ids, data, acked])


func _apply_snapshot(tick: int, peer_ids: PackedInt32Array,
		data: PackedFloat32Array, acked: int) -> void:
	Net.clock.on_snapshot(tick)
	var server_time: float = float(tick) * Tuning.physics_delta

	for index: int in peer_ids.size():
		var peer_id: int = peer_ids[index]
		if not _vehicles.has(peer_id):
			continue
		var state: VehicleState = VehicleState.from_floats(
			data, index * VehicleState.ENCODED_FLOATS)
		var vehicle: Vehicle = _vehicles[peer_id]
		vehicle.apply_server_state(state, acked, server_time, Tuning.physics_delta)


# --- Cycle de vie des vehicules ----------------------------------------------

func _on_player_joined(peer_id: int) -> void:
	if not Net.is_server():
		return
	_create_vehicle_for(peer_id)


func _on_player_left(peer_id: int) -> void:
	if not _vehicles.has(peer_id):
		return
	var vehicle: Vehicle = _vehicles[peer_id]
	_vehicles.erase(peer_id)
	_input_queues.erase(peer_id)
	_last_processed.erase(peer_id)
	_last_input.erase(peer_id)
	_spawn_slots.erase(peer_id)
	if is_instance_valid(vehicle):
		vehicle.queue_free()


## Cree le vehicule d'un joueur. Cote serveur uniquement : `MultiplayerSpawner`
## le replique ensuite chez tous les clients.
func _create_vehicle_for(peer_id: int) -> void:
	if _vehicles.has(peer_id):
		return
	var slot: int = _next_spawn_slot
	_next_spawn_slot += 1
	_spawn_slots[peer_id] = slot
	_spawner.spawn({
		"peer_id": peer_id,
		"name": Net.get_player_name(peer_id),
		"color_index": Net.get_player_color_index(peer_id),
		"slot": slot,
	})


## Cree un vehicule pour le jeu solo, sans reseau.
func create_solo_vehicle(player_name: String) -> void:
	var vehicle: Vehicle = _spawn_vehicle({
		"peer_id": Net.SERVER_PEER_ID,
		"name": player_name,
		"color_index": 0,
		"slot": 0,
	})
	_vehicle_container.add_child(vehicle)


## Construit le vehicule. Execute sur le serveur ET sur chaque client, par
## `MultiplayerSpawner`. Le role depend de qui execute :
##   - sur le serveur : AUTHORITY, il simule pour de vrai ;
##   - sur un client, pour sa propre voiture : PREDICTED ;
##   - sur un client, pour les autres : INTERPOLATED.
func _spawn_vehicle(data: Variant) -> Node:
	var info: Dictionary = data
	var peer_id: int = info["peer_id"]
	var is_local: bool = peer_id == Net.local_peer_id()

	var mode: Vehicle.Mode
	if Net.is_server() or not Net.is_online():
		mode = Vehicle.Mode.AUTHORITY
	elif is_local:
		mode = Vehicle.Mode.PREDICTED
	else:
		mode = Vehicle.Mode.INTERPOLATED

	var vehicle: Vehicle = Vehicle.new()
	vehicle.name = "Vehicle_%d" % peer_id
	vehicle.configure(peer_id, info["name"], info["color_index"], mode, track)
	_vehicles[peer_id] = vehicle

	# Le placement attend l'entree dans l'arbre : la piste doit etre construite.
	vehicle.ready.connect(_on_vehicle_ready.bind(vehicle, int(info["slot"]), is_local),
		CONNECT_ONE_SHOT)
	return vehicle


func _on_vehicle_ready(vehicle: Vehicle, slot: int, is_local: bool) -> void:
	vehicle.setup_visuals(is_local)
	if track != null and track.has_method("get_spawn_transform"):
		vehicle.place_at(track.call("get_spawn_transform", slot))
	if is_local:
		local_vehicle = vehicle
		local_vehicle_ready.emit(vehicle)


func get_vehicles() -> Array:
	return _vehicles.values()


func vehicle_count() -> int:
	return _vehicles.size()
