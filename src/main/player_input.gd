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

## Pilote automatique (option `--autopilot`). Sert aux essais sans clavier :
## verifier le reseau, la prediction ou les performances demande une voiture qui
## roule, et personne ne peut tenir le volant sur un serveur headless.
## Les entrees ne dependent que du numero de sequence, donc deux instances
## produisent exactement la meme conduite : les ecarts observes viennent alors
## du reseau, pas du pilotage.
static var autopilot: bool = false


static func sample(sequence: int) -> InputFrame:
	if autopilot:
		return _autopilot_frame(sequence)
	if not enabled:
		return InputFrame.neutral(sequence)

	var throttle: float = Input.get_action_strength("drive_accelerate")
	var brake: float = Input.get_action_strength("drive_brake")
	var steer: float = Input.get_action_strength("drive_right") \
		- Input.get_action_strength("drive_left")
	var handbrake: bool = Input.is_action_pressed("drive_handbrake")
	var respawn: bool = Input.is_action_just_pressed("drive_respawn")

	return InputFrame.create(sequence, throttle, brake, steer, handbrake, respawn)


## Conduite synthetique : plein gaz et leger slalom.
##
## Le braquage reste volontairement modeste et alterne vite : a fond, la voiture
## quitterait la piste en deux secondes et finirait contre un mur, ce qui ne
## dirait plus rien du reseau.
static func _autopilot_frame(sequence: int) -> InputFrame:
	# Cosinus et non sinus : integrer un sinus donne un cap toujours du meme
	# signe, et la voiture partait en diagonale jusqu'au mur. Avec un cosinus,
	# le cap oscille autour de zero et la trajectoire reste dans l'axe.
	var steer: float = 0.30 * cos(float(sequence) * 0.04)
	return InputFrame.create(sequence, 1.0, 0.0, steer, false, false)
