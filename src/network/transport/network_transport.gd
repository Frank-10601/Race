class_name NetworkTransport
extends RefCounted
## Interface d'une couche de transport reseau.
##
## Deux implementations (voir CLAUDE.md section 3.2) :
##   - `WebSocketTransport` : par defaut. Seul transport utilisable depuis un
##     navigateur, donc le seul qui permette a un joueur web et a un joueur
##     bureau de se retrouver sur le meme serveur.
##   - `EnetTransport` : UDP, bureau uniquement. Meilleure latence sur une
##     connexion instable, utile pour comparer.
##
## LIMITE : une `MultiplayerAPI` ne porte qu'un seul `MultiplayerPeer`. Le
## serveur choisit donc son transport au lancement ; il ne peut pas ecouter les
## deux a la fois. Voir `docs/NOTES.md`.


## Cree un serveur. Retourne { "peer": MultiplayerPeer, "error": int }.
func create_server(_port: int, _max_clients: int) -> Dictionary:
	push_error("create_server() doit etre redefini.")
	return {"peer": null, "error": ERR_UNCONFIGURED}


## Cree un client. Retourne { "peer": MultiplayerPeer, "error": int }.
func create_client(_address: String, _port: int) -> Dictionary:
	push_error("create_client() doit etre redefini.")
	return {"peer": null, "error": ERR_UNCONFIGURED}


## Nom court du transport, tel qu'attendu en ligne de commande.
func get_transport_name() -> String:
	return "inconnu"


## Ce transport fonctionne-t-il dans un navigateur ?
func supports_web() -> bool:
	return false


## Fabrique : "websocket" ou "enet". Toute autre valeur retombe sur WebSocket,
## qui est le seul choix sur lequel tous les clients peuvent se rejoindre.
static func create(transport_name: String) -> NetworkTransport:
	match transport_name.to_lower():
		"enet":
			if OS.has_feature("web"):
				push_warning("ENet est indisponible dans un navigateur : WebSocket utilise.")
				return WebSocketTransport.new()
			return EnetTransport.new()
		"websocket", "ws", "":
			return WebSocketTransport.new()
		_:
			push_warning("Transport inconnu « %s » : WebSocket utilise." % transport_name)
			return WebSocketTransport.new()
