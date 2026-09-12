class_name CliArgs
extends RefCounted
## Lecture des options de lancement.
##
## Sur bureau, elles viennent de la ligne de commande. Dans un navigateur, il
## n'y a pas de ligne de commande : on lit alors les parametres de l'URL, ce qui
## permet de partager un lien qui connecte directement au bon serveur
## (« .../index.html?join=mon-serveur.fr&port=8910 »).

enum Launch { MENU, SOLO, HOST, DEDICATED, CLIENT }

var launch: Launch = Launch.MENU
var address: String = "127.0.0.1"
var port: int = 0                 ## 0 = valeur de tuning.cfg
var transport: String = ""        ## vide = valeur de tuning.cfg
var player_name: String = ""
var lag_ms: float = 0.0
var jitter_ms: float = 0.0
var max_players: int = 0          ## 0 = valeur de tuning.cfg
## Options d'essai, sans effet sur le jeu normal.
var autopilot: bool = false
var diagnostics: bool = false
## Duree apres laquelle le jeu s'arrete en affichant ses moyennes (0 = jamais).
## Sert aux mesures de performance comparees bureau / navigateur.
var benchmark_seconds: float = 0.0
## Nombre de vehicules simules pour la mesure.
var benchmark_vehicles: int = 1


static func parse() -> CliArgs:
	var args: CliArgs = CliArgs.new()
	if OS.has_feature("web"):
		args._parse_url()
	else:
		args._parse_command_line()
	args._apply_defaults()
	return args


func _parse_command_line() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty():
		# Godot ne separe les arguments par « -- » que si l'utilisateur l'a fait.
		arguments = OS.get_cmdline_args()

	var index: int = 0
	while index < arguments.size():
		var argument: String = arguments[index]
		var value: String = arguments[index + 1] if index + 1 < arguments.size() else ""
		match argument:
			"--server", "--dedicated":
				launch = Launch.DEDICATED
			"--host":
				launch = Launch.HOST
			"--solo":
				launch = Launch.SOLO
			"--autopilot":
				autopilot = true
			"--benchmark":
				benchmark_seconds = float(value)
				launch = Launch.SOLO
				autopilot = true
				index += 1
			"--benchmark-vehicles":
				benchmark_vehicles = maxi(1, int(value))
				index += 1
			"--diagnostics":
				diagnostics = true
			"--join":
				launch = Launch.CLIENT
				if not value.is_empty():
					address = value
					index += 1
			"--port":
				port = int(value)
				index += 1
			"--transport":
				transport = value
				index += 1
			"--name":
				player_name = value
				index += 1
			"--lag":
				lag_ms = float(value)
				index += 1
			"--jitter":
				jitter_ms = float(value)
				index += 1
			"--max-players":
				max_players = int(value)
				index += 1
		index += 1


## Parametres d'URL du client web : ?join=adresse&port=8910&name=Kim&lag=150
func _parse_url() -> void:
	var query: String = str(JavaScriptBridge.eval("window.location.search", true))
	if query.length() <= 1:
		return
	for pair: String in query.substr(1).split("&"):
		var parts: PackedStringArray = pair.split("=")
		if parts.size() != 2:
			continue
		var key: String = parts[0].to_lower()
		var value: String = parts[1].uri_decode()
		match key:
			"join":
				launch = Launch.CLIENT
				address = value
			"solo":
				launch = Launch.SOLO
			"autopilot":
				autopilot = value != "0"
			"benchmark":
				benchmark_seconds = float(value)
				launch = Launch.SOLO
				autopilot = true
			"benchmark_vehicles":
				benchmark_vehicles = maxi(1, int(value))
			"diagnostics":
				diagnostics = value != "0"
			"port":
				port = int(value)
			"transport":
				transport = value
			"name":
				player_name = value
			"lag":
				lag_ms = float(value)
			"jitter":
				jitter_ms = float(value)


func _apply_defaults() -> void:
	if port <= 0:
		port = Tuning.default_port
	if transport.is_empty():
		transport = Tuning.default_transport
	if max_players > 0:
		Tuning.max_players = max_players
	if player_name.is_empty():
		player_name = "Joueur"
	PlayerInput.autopilot = autopilot


func describe() -> String:
	match launch:
		Launch.DEDICATED:
			return "serveur dedie, port %d, transport %s" % [port, transport]
		Launch.HOST:
			return "hote, port %d, transport %s" % [port, transport]
		Launch.CLIENT:
			return "client vers %s:%d, transport %s" % [address, port, transport]
		Launch.SOLO:
			return "solo"
		_:
			return "menu"
