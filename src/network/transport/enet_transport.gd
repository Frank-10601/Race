class_name EnetTransport
extends NetworkTransport
## Transport ENet (UDP). Bureau uniquement : un navigateur ne peut pas ouvrir de
## socket UDP, donc un client web ne pourra jamais rejoindre un serveur lance
## avec ce transport.
##
## Interet : pas de blocage de tete de file. Sur une connexion qui perd des
## paquets, les voitures distantes restent plus fluides qu'en WebSocket. Utile
## pour mesurer ce que coute reellement le TCP entre deux machines de bureau.

func create_server(port: int, max_clients: int) -> Dictionary:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: int = peer.create_server(port, max_clients)
	if error != OK:
		return {"peer": null, "error": error}
	return {"peer": peer, "error": OK}


func create_client(address: String, port: int) -> Dictionary:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: int = peer.create_client(address, port)
	if error != OK:
		return {"peer": null, "error": error}
	return {"peer": peer, "error": OK}


func get_transport_name() -> String:
	return "enet"


func supports_web() -> bool:
	return false
