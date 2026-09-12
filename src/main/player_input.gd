class_name PlayerInput
extends RefCounted
## Lecture du clavier vers une trame d'entrees.
##
## Seul endroit du projet qui lit les touches. Le reste du code ne manipule que
## des `InputFrame`, ce qui permettra plus tard d'ajouter une manette ou un
## pilote automatique sans rien changer ailleurs.

## Quand cette valeur est fausse (menu ouvert, champ de saisie actif), on
## renvoie des entrees neutres : la voiture ne doit pas rouler pendant qu'on
## tape son pseudo.
static var enabled: bool = true


static func sample(sequence: int) -> InputFrame:
	if not enabled:
		return InputFrame.neutral(sequence)

	var throttle: float = Input.get_action_strength("drive_accelerate")
	var brake: float = Input.get_action_strength("drive_brake")
	var steer: float = Input.get_action_strength("drive_right") \
		- Input.get_action_strength("drive_left")
	var handbrake: bool = Input.is_action_pressed("drive_handbrake")
	var respawn: bool = Input.is_action_just_pressed("drive_respawn")

	return InputFrame.create(sequence, throttle, brake, steer, handbrake, respawn)
