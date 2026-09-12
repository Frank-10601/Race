class_name Diagnostics
extends Node
## Rapport periodique sur la console (option `--diagnostics`).
##
## Le panneau F3 ne sert a rien sur un serveur dedie ni dans un essai
## automatise : ce noeud imprime les memes informations sur la sortie standard.
## Il n'a aucun effet sur le jeu et n'est cree que si l'option est demandee.

## Intervalle entre deux rapports, en secondes.
const INTERVAL: float = 1.0

var _world: RaceWorld = null
var _timer: float = 0.0
var _elapsed: float = 0.0


func setup(world: RaceWorld) -> void:
	_world = world


func _process(delta: float) -> void:
	if _world == null:
		return
	_elapsed += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	print(_build_line())


func _build_line() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("[diag %5.1fs]" % _elapsed)
	parts.append("fps %3d" % Engine.get_frames_per_second())
	parts.append("vehicules %d" % _world.vehicle_count())
	parts.append("joueurs %d" % Net.player_count())

	if Net.mode == Net.Mode.CLIENT:
		parts.append("ping %4.0f ms" % Net.clock.ping_ms)

	var vehicle: Vehicle = _world.local_vehicle
	if vehicle == null or not is_instance_valid(vehicle):
		parts.append("pas de vehicule local")
		return " | ".join(parts)

	parts.append("%5.1f km/h" % vehicle.get_speed_kmh())
	parts.append("pos %6.1f %6.1f" % [vehicle.state.position.x, vehicle.state.position.z])
	parts.append("glisse %.2f" % vehicle.state.drift)

	if vehicle.prediction != null:
		parts.append("ecart %6.3f m" % vehicle.prediction.last_position_error)
		parts.append("rejoues %2d" % vehicle.prediction.last_replay_count)
	return " | ".join(parts)
