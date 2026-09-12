extends Control
## Menu principal : pseudo, hebergement, connexion.
##
## Le bouton « Quitter » est masque dans un navigateur : une page web ne se
## ferme pas elle-meme, le bouton n'y aurait aucun effet.

signal solo_requested(player_name: String)
signal host_requested(player_name: String, port: int)
signal join_requested(player_name: String, address: String, port: int)

@onready var _solo_button: Button = $Center/Panel/Margin/Layout/SoloButton
@onready var _name_field: LineEdit = $Center/Panel/Margin/Layout/NameField
@onready var _address_field: LineEdit = $Center/Panel/Margin/Layout/AddressRow/AddressField
@onready var _port_field: LineEdit = $Center/Panel/Margin/Layout/AddressRow/PortField
@onready var _host_button: Button = $Center/Panel/Margin/Layout/HostButton
@onready var _join_button: Button = $Center/Panel/Margin/Layout/JoinButton
@onready var _quit_button: Button = $Center/Panel/Margin/Layout/QuitButton
@onready var _status: Label = $Center/Panel/Margin/Layout/Status


func _ready() -> void:
	_name_field.text = "Joueur %d" % (randi() % 900 + 100)
	_address_field.text = "127.0.0.1"
	_port_field.text = str(Tuning.default_port)

	_solo_button.pressed.connect(_on_solo_pressed)
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_name_field.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())

	# Une page web ne peut pas se fermer elle-meme.
	_quit_button.visible = not OS.has_feature("web")

	# Un navigateur ne peut pas ECOUTER de connexions : il n'existe pas de
	# serveur WebSocket dans une page web. Depuis le navigateur, on conduit seul
	# ou on rejoint un serveur, jamais on n'heberge.
	if OS.has_feature("web"):
		_host_button.visible = false
		_host_button.disabled = true

	Net.connection_failed.connect(_on_connection_failed)
	Net.server_failed.connect(show_status)


## Le menu prend le clavier tant qu'il est affiche : sans cela, taper son pseudo
## ferait accelerer la voiture.
func set_menu_active(active: bool) -> void:
	visible = active
	PlayerInput.enabled = not active
	if active:
		_solo_button.disabled = false
		_host_button.disabled = not OS.has_feature("web") and false
		_join_button.disabled = false
		_name_field.grab_focus()


func show_status(message: String) -> void:
	_status.text = message
	_solo_button.disabled = false
	_host_button.disabled = false
	_join_button.disabled = false


func get_player_name() -> String:
	var entered: String = _name_field.text.strip_edges()
	return entered if not entered.is_empty() else "Joueur"


func _on_solo_pressed() -> void:
	_lock("Chargement de la piste...")
	solo_requested.emit(get_player_name())


func _on_host_pressed() -> void:
	_lock("Ouverture du serveur...")
	host_requested.emit(get_player_name(), _read_port())


func _on_join_pressed() -> void:
	var address: String = _address_field.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	_lock("Connexion a %s..." % address)
	join_requested.emit(get_player_name(), address, _read_port())


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_connection_failed(reason: String) -> void:
	show_status(reason)


func _lock(message: String) -> void:
	_status.text = message
	_solo_button.disabled = true
	_host_button.disabled = true
	_join_button.disabled = true


func _read_port() -> int:
	var value: int = int(_port_field.text)
	return value if value > 0 else Tuning.default_port
