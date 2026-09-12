class_name WebSocketTransport
extends NetworkTransport
## Transport WebSocket : le seul utilisable depuis un navigateur.
##
## Consequences du TCP, a connaitre :
##   - sur la voiture LOCALE : aucune. La prediction la rend insensible a la
##     latence comme a la gigue.
##   - sur les AUTRES voitures : en cas de perte, TCP retransmet et bloque les
##     paquets suivants (blocage de tete de file). Un trou d'environ un
##     aller-retour peut apparaitre ; le tampon d'interpolation de 100 ms
##     l'absorbe, et l'extrapolation courte prend le relais au-dela.
##
## `wss://` (chiffre) devient OBLIGATOIRE des que la page est servie en https :
## un navigateur refuse une connexion `ws://` non chiffree depuis une page
## securisee. Voir `docs/HOSTING.md`.

## Schema d'URL a utiliser. Passer a "wss" quand la page est en https.
var use_secure: bool = false


func create_server(port: int, _max_clients: int) -> Dictionary:
	var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	# Le nombre de joueurs est controle par `NetworkManager`, pas ici :
	# WebSocketMultiplayerPeer n'expose pas de limite de connexions.
	var error: int = peer.create_server(port)
	if error != OK:
		return {"peer": null, "error": error}
	return {"peer": peer, "error": OK}


func create_client(address: String, port: int) -> Dictionary:
	var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	var error: int = peer.create_client(build_url(address, port))
	if error != OK:
		return {"peer": null, "error": error}
	return {"peer": peer, "error": OK}


## Construit l'URL de connexion. Accepte aussi une adresse deja complete
## (« wss://mon-serveur.fr/jeu »), pratique derriere un tunnel ou un proxy.
func build_url(address: String, port: int) -> String:
	if address.begins_with("ws://") or address.begins_with("wss://"):
		return address
	var scheme: String = "wss" if _needs_secure() else "ws"
	return "%s://%s:%d" % [scheme, address, port]


## En https, le navigateur impose wss. On le detecte plutot que de le demander
## au joueur, qui n'a aucune raison de le savoir.
func _needs_secure() -> bool:
	if use_secure:
		return true
	if not OS.has_feature("web"):
		return false
	var origin: String = str(JavaScriptBridge.eval("window.location.protocol", true))
	return origin.begins_with("https")


func get_transport_name() -> String:
	return "websocket"


func supports_web() -> bool:
	return true
