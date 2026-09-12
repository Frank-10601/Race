class_name NetClock
extends RefCounted
## Horloge partagee entre le serveur et les clients, comptee en PAS DE PHYSIQUE
## plutot qu'en millisecondes.
##
## Pourquoi des pas et pas une horloge murale : la simulation avance par pas de
## taille fixe, et c'est cette cadence qui doit servir de reference. Comparer
## des horloges systeme entre machines demanderait une synchronisation precise,
## sensible a la derive et au changement d'heure. Compter les pas evite tout
## cela.
##
## Cote client, `server_time` avance librement puis se recale doucement sur
## chaque instantane recu. Comme les instantanes arrivent avec la latence,
## l'horloge se cale naturellement sur « temps serveur moins latence » — ce qui
## est exactement l'instant qu'on veut afficher.

## Au-dela de cet ecart, on se recale d'un coup : la connexion a saute.
const RESYNC_THRESHOLD: float = 1.0
## Vitesse de recalage progressif (1/s).
const SYNC_SPEED: float = 2.5

## Tick courant du serveur (cote serveur uniquement).
var server_tick: int = 0
## Estimation locale du temps serveur, en secondes.
var server_time: float = 0.0
## Aller-retour mesure, en millisecondes.
var ping_ms: float = 0.0

var _synced: bool = false
var _ping_samples: Array[float] = []


## Cote serveur : avance d'un pas.
func tick() -> void:
	server_tick += 1
	server_time = float(server_tick) * Tuning.physics_delta


## Cote client : fait avancer l'horloge entre deux instantanes.
func advance(delta: float) -> void:
	server_time += delta


## Cote client : recale l'horloge sur l'instantane recu.
func on_snapshot(tick_received: int) -> void:
	var target: float = float(tick_received) * Tuning.physics_delta
	if not _synced or absf(target - server_time) > RESYNC_THRESHOLD:
		server_time = target
		_synced = true
		return
	# Recalage progressif : un saut d'horloge se verrait sur toutes les voitures.
	server_time += (target - server_time) * minf(1.0, SYNC_SPEED * Tuning.physics_delta)


## Instant a afficher pour les voitures distantes : le passe proche, pour
## toujours disposer de deux etats a interpoler.
func get_render_time() -> float:
	return server_time - Tuning.interpolation_delay


## Enregistre un aller-retour mesure. Moyenne glissante : une mesure isolee est
## trop bruitee pour etre affichee telle quelle.
func record_ping(round_trip_ms: float) -> void:
	_ping_samples.append(round_trip_ms)
	if _ping_samples.size() > 8:
		_ping_samples.pop_front()
	var total: float = 0.0
	for sample: float in _ping_samples:
		total += sample
	ping_ms = total / float(_ping_samples.size())


func reset() -> void:
	server_tick = 0
	server_time = 0.0
	ping_ms = 0.0
	_synced = false
	_ping_samples.clear()
