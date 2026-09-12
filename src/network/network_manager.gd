extends Node
## Gestion des connexions (autoload `Net`).
##
## Responsable du transport, de l'ouverture du serveur, de la connexion des
## clients, de la liste des joueurs et de la mesure du ping. Ne connait rien de
## la course elle-meme : c'est `RaceWorld` qui gere les vehicules.
##
## Trois modes de lancement (CLAUDE.md, contrainte 2) :
##   HOST      — heberge et joue ;
##   DEDICATED — heberge sans afficher, lance en ligne de commande ;
##   CLIENT    — rejoint un serveur (bureau ou navigateur).

signal server_started
signal server_failed(reason: String)
signal connected_to_server
signal connection_failed(reason: String)
signal server_closed
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal player_list_changed

enum Mode { OFFLINE, HOST, DEDICATED, CLIENT }

## Identifiant reserve au serveur par l'API multijoueur de Godot.
const SERVER_PEER_ID: int = 1

## Intervalle entre deux mesures de ping, en secondes.
const PING_INTERVAL: float = 1.0

var mode: Mode = Mode.OFFLINE
var transport: NetworkTransport = null
var clock: NetClock = NetClock.new()

## peer_id -> { "name": String, "color_index": int }
var players: Dictionary = {}
## Pseudo choisi localement, envoye au serveur a la connexion.
var local_player_name: String = "Joueur"

var _ping_timer: float = 0.0
var _ping_sent_at: float = 0.0
var _next_color_index: int = 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if mode != Mode.CLIENT or not is_connected_to_server():
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = PING_INTERVAL
		_ping_sent_at = Time.get_ticks_msec()
		_request_pong.rpc_id(SERVER_PEER_ID)


# --- Ouverture / fermeture ---------------------------------------------------

## Demarre un serveur. `dedicated` = serveur sans joueur local.
func host(port: int, transport_name: String, dedicated: bool = false) -> bool:
	shutdown()
	transport = NetworkTransport.create(transport_name)
	var result: Dictionary = transport.create_server(port, Tuning.max_players)
	if result["error"] != OK:
		var reason: String = "Impossible d'ouvrir le port %d (code %d)." % [port, result["error"]]
		push_error(reason)
		server_failed.emit(reason)
		return false

	multiplayer.multiplayer_peer = result["peer"]
	mode = Mode.DEDICATED if dedicated else Mode.HOST
	clock.reset()
	players.clear()
	_next_color_index = 0

	if not dedicated:
		_register_player(SERVER_PEER_ID, local_player_name)

	print("[reseau] serveur %s demarre sur le port %d (transport : %s, %d joueurs max)"
		% ["dedie" if dedicated else "hote", port, transport.get_transport_name(), Tuning.max_players])
	server_started.emit()
	return true


## Rejoint un serveur.
func join(address: String, port: int, transport_name: String) -> bool:
	shutdown()
	transport = NetworkTransport.create(transport_name)
	var result: Dictionary = transport.create_client(address, port)
	if result["error"] != OK:
		var reason: String = "Connexion impossible vers %s:%d (code %d)." % [address, port, result["error"]]
		push_error(reason)
		connection_failed.emit(reason)
		return false

	multiplayer.multiplayer_peer = result["peer"]
	mode = Mode.CLIENT
	clock.reset()
	players.clear()
	print("[reseau] connexion a %s:%d (transport : %s)" % [address, port, transport.get_transport_name()])
	return true


func shutdown() -> void:
	if multiplayer.multiplayer_peer != null \
			and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	players.clear()
	clock.reset()


# --- Etat --------------------------------------------------------------------

func is_server() -> bool:
	return mode == Mode.HOST or mode == Mode.DEDICATED


func is_dedicated() -> bool:
	return mode == Mode.DEDICATED


func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_connected_to_server() -> bool:
	return mode == Mode.CLIENT \
		and multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return SERVER_PEER_ID
	return multiplayer.get_unique_id()


func get_player_name(peer_id: int) -> String:
	if players.has(peer_id):
		return players[peer_id]["name"]
	return "Joueur %d" % peer_id


func get_player_color_index(peer_id: int) -> int:
	if players.has(peer_id):
		return players[peer_id]["color_index"]
	return 0


func player_count() -> int:
	return players.size()


# --- Signaux de l'API multijoueur --------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if not is_server():
		return
	# Le nombre de joueurs est controle ici : WebSocketMultiplayerPeer n'a pas
	# de limite integree, contrairement a ENet.
	var occupied: int = players.size()
	if occupied >= Tuning.max_players:
		print("[reseau] connexion refusee (%d/%d joueurs)" % [occupied, Tuning.max_players])
		_reject.rpc_id(peer_id, "La course est complete (%d joueurs)." % Tuning.max_players)
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	print("[reseau] pair %d connecte" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if players.has(peer_id):
		print("[reseau] %s (%d) a quitte" % [get_player_name(peer_id), peer_id])
		players.erase(peer_id)
		player_list_changed.emit()
	player_left.emit(peer_id)


func _on_connected_to_server() -> void:
	print("[reseau] connecte au serveur, identifiant %d" % multiplayer.get_unique_id())
	_announce_player.rpc_id(SERVER_PEER_ID, local_player_name)
	connected_to_server.emit()


func _on_connection_failed() -> void:
	mode = Mode.OFFLINE
	connection_failed.emit("Le serveur n'a pas repondu.")


func _on_server_disconnected() -> void:
	mode = Mode.OFFLINE
	players.clear()
	server_closed.emit()


# --- Inscription des joueurs -------------------------------------------------

func _register_player(peer_id: int, player_name: String) -> void:
	players[peer_id] = {
		"name": _sanitize_name(player_name),
		"color_index": _next_color_index,
	}
	_next_color_index += 1
	player_list_changed.emit()
	player_joined.emit(peer_id)


## Les pseudos viennent des clients : on les borne avant de les afficher.
static func _sanitize_name(raw: String) -> String:
	var cleaned: String = raw.strip_edges().replace("\n", " ").replace("\t", " ")
	if cleaned.is_empty():
		cleaned = "Joueur"
	return cleaned.substr(0, 16)


## Le client annonce son pseudo. Le serveur lui attribue une couleur et diffuse
## la liste complete.
@rpc("any_peer", "call_remote", "reliable")
func _announce_player(player_name: String) -> void:
	if not is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if players.has(peer_id):
		return
	_register_player(peer_id, player_name)
	_sync_player_list.rpc(players)


## Le serveur diffuse la liste des joueurs.
@rpc("authority", "call_remote", "reliable")
func _sync_player_list(remote_players: Dictionary) -> void:
	var previous: Dictionary = players
	players = remote_players
	player_list_changed.emit()
	for peer_id: int in players:
		if not previous.has(peer_id):
			player_joined.emit(peer_id)
	for peer_id: int in previous:
		if not players.has(peer_id):
			player_left.emit(peer_id)


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	push_warning("[reseau] connexion refusee : %s" % reason)
	connection_failed.emit(reason)


# --- Mesure du ping ----------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable")
func _request_pong() -> void:
	if not is_server():
		return
	_send_pong.rpc_id(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "unreliable")
func _send_pong() -> void:
	clock.record_ping(float(Time.get_ticks_msec()) - _ping_sent_at)
