extends PanelContainer
## Panneau de debogage (touche F3).
##
## Affiche ce qui sert vraiment a diagnostiquer le reseau et la conduite :
## images par seconde, ping, joueurs, vitesse, position, adherence des roues,
## et l'etat de la reconciliation — le nombre de pas rejoues et l'ecart mesure
## disent immediatement si la prediction fonctionne.

## Frequence de rafraichissement. Lire ces valeurs a chaque image ferait
## clignoter le texte sans rien apprendre.
const REFRESH_INTERVAL: float = 0.1

@onready var _text: Label = $Margin/Text

var _world: RaceWorld = null
var _timer: float = 0.0


func setup(world: RaceWorld) -> void:
	_world = world


func toggle() -> void:
	visible = not visible


func _process(delta: float) -> void:
	if not visible or _world == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	_text.text = _build_report()


func _build_report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[F3] Debogage")
	lines.append("FPS              %d" % Engine.get_frames_per_second())
	lines.append("Mode             %s" % _describe_mode())
	lines.append("Transport        %s" % (Net.transport.get_transport_name() if Net.transport != null else "aucun"))
	lines.append("Joueurs          %d / %d" % [maxi(Net.player_count(), _world.vehicle_count()), Tuning.max_players])
	lines.append("Ping             %.0f ms" % Net.clock.ping_ms)
	if Net.lag.is_active():
		lines.append("Latence simulee  %.0f ms (gigue %.0f)" % [Net.lag.round_trip_ms, Net.lag.jitter_ms])

	var vehicle: Vehicle = _world.local_vehicle
	if vehicle == null or not is_instance_valid(vehicle):
		lines.append("")
		lines.append("Aucun vehicule local.")
		return "\n".join(lines)

	var state: VehicleState = vehicle.state
	lines.append("")
	lines.append("Vitesse          %.1f km/h" % vehicle.get_speed_kmh())
	lines.append("Vitesse avant    %.1f m/s" % state.get_forward_speed())
	lines.append("Position         %.1f  %.1f  %.1f" % [state.position.x, state.position.y, state.position.z])
	lines.append("Cap              %.0f deg" % rad_to_deg(state.yaw))
	lines.append("Roues            %s" % _describe_grip(state))
	lines.append("Adherence        %.2f (derapage %.2f)" % [vehicle.physics.last_grip, state.drift])
	lines.append("Braquage         %+.2f" % state.steer_smoothed)

	if vehicle.prediction != null:
		lines.append("")
		lines.append("Sequence         %d (serveur : %d)" % [state_sequence(vehicle), vehicle.acked_sequence])
		lines.append("Ecart predit     %.3f m" % vehicle.prediction.last_position_error)
		lines.append("Pas rejoues      %d" % vehicle.prediction.last_replay_count)
		lines.append("Corrections      %d" % vehicle.prediction.corrections_applied)
		if vehicle.prediction.overruns > 0:
			lines.append("Decrochages      %d (machine a la peine)" % vehicle.prediction.overruns)
	return "\n".join(lines)


func state_sequence(vehicle: Vehicle) -> int:
	return vehicle.last_input.sequence


## Etat d'adherence des roues, en clair.
func _describe_grip(state: VehicleState) -> String:
	if not state.grounded:
		return "en l'air"
	if state.drift > 0.5:
		return "en glisse"
	if state.drift > 0.1:
		return "reprise d'adherence"
	return "adherentes"


func _describe_mode() -> String:
	match Net.mode:
		Net.Mode.HOST:
			return "hote"
		Net.Mode.DEDICATED:
			return "serveur dedie"
		Net.Mode.CLIENT:
			return "client"
		_:
			return "solo"
