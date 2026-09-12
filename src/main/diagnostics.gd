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

# Cumul des mesures, pour donner une moyenne plutot qu'un instantane bruite.
var _physics_time_sum: float = 0.0
var _process_time_sum: float = 0.0
var _fps_sum: float = 0.0
var _samples: int = 0


func setup(world: RaceWorld) -> void:
	_world = world


func _process(delta: float) -> void:
	if _world == null:
		return
	_elapsed += delta
	_physics_time_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_process_time_sum += Performance.get_monitor(Performance.TIME_PROCESS)
	_fps_sum += Engine.get_frames_per_second()
	_samples += 1
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	print(_build_line())


## Moyennes depuis le lancement. C'est ce qu'il faut comparer entre la version
## bureau et la version web : un releve instantane varie trop pour conclure.
func report_averages() -> String:
	if _samples == 0:
		return "aucune mesure"
	return "moyennes sur %.0f s : %.1f images/s | physique %.3f ms/image | rendu %.3f ms/image" % [
		_elapsed,
		_fps_sum / float(_samples),
		_physics_time_sum / float(_samples) * 1000.0,
		_process_time_sum / float(_samples) * 1000.0,
	]


func _build_line() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("[diag %5.1fs]" % _elapsed)
	parts.append("fps %3d" % Engine.get_frames_per_second())
	parts.append("physique %.3f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0))
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
