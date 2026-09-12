class_name LagSimulator
extends RefCounted
## Retarde volontairement les messages recus, pour tester le jeu comme s'il
## tournait sur une connexion lente sans quitter sa machine.
##
## Pourquoi dans le jeu plutot qu'avec `tc netem` : cela fonctionne partout, y
## compris dans un navigateur et sous Windows, et cela n'exige aucun privilege.
##
## Le retard est applique A LA RECEPTION, des deux cotes. Un reglage de 150 ms
## produit donc bien 150 ms d'aller-retour : 75 ms a l'aller, 75 ms au retour.
##
## Activation : `--lag 150` en ligne de commande. Desactive, cette classe
## n'introduit aucun cout : les messages sont traites immediatement.

## Retard aller-retour simule, en millisecondes. 0 desactive la simulation.
var round_trip_ms: float = 0.0

## Gigue ajoutee, en millisecondes : le retard varie de plus ou moins cette
## valeur. Reproduit une connexion irreguliere.
var jitter_ms: float = 0.0

var _queue: Array = []
var _time: float = 0.0


func is_active() -> bool:
	return round_trip_ms > 0.0


## Traite le message maintenant, ou le met en attente si la simulation est active.
func deliver(callback: Callable, arguments: Array) -> void:
	if not is_active():
		callback.callv(arguments)
		return
	var delay: float = round_trip_ms * 0.0005  # moitie du trajet, en secondes
	if jitter_ms > 0.0:
		delay += randf_range(-jitter_ms, jitter_ms) * 0.001
	_queue.append({"at": _time + maxf(delay, 0.0), "callback": callback, "arguments": arguments})


## A appeler a chaque image : libere les messages dont le retard est ecoule.
func process(delta: float) -> void:
	if _queue.is_empty():
		return
	_time += delta
	var pending: Array = []
	for entry: Dictionary in _queue:
		if entry["at"] <= _time:
			var callback: Callable = entry["callback"]
			callback.callv(entry["arguments"])
		else:
			pending.append(entry)
	_queue = pending


func clear() -> void:
	_queue.clear()
	_time = 0.0
