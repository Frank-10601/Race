class_name TrackPlan
extends RefCounted
## Description d'un trace, independante de sa geometrie.
##
## Un trace s'ecrit comme une suite d'instructions de pilotage : « avance de
## 210 m », « tourne de 90 degres a droite sur un rayon de 50 m ». C'est la facon
## la plus lisible de decrire un circuit a la main, et cela prepare la phase 1 :
## ajouter un circuit reviendra a ecrire un nouveau `TrackPlan`, sans toucher au
## reste du code.
##
## Conventions : le plan travaille dans le plan horizontal (x, z). Le cap suit
## la convention de Godot — cap 0 pointe vers -Z, un cap croissant tourne vers
## la gauche. Les virages, eux, s'expriment dans le sens naturel du pilote :
## angle positif = a droite.

enum Command { STRAIGHT, TURN }

## Largeur du ruban de piste, en metres.
var width: float = 24.0
## Position de depart, dans le plan horizontal.
var start_position: Vector2 = Vector2.ZERO
## Cap de depart, en degres.
var start_heading: float = 0.0
## Instructions : [STRAIGHT, longueur] ou [TURN, angle, rayon].
var commands: Array = []
## Pas d'echantillonnage de la ligne centrale, en metres.
var sample_step: float = 4.0


func straight(length: float) -> TrackPlan:
	commands.append([Command.STRAIGHT, length])
	return self


## Angle positif : virage a droite. Angle negatif : virage a gauche.
func turn(angle_degrees: float, radius: float) -> TrackPlan:
	commands.append([Command.TURN, angle_degrees, radius])
	return self


## Echantillonne la ligne centrale.
## Retourne { "points": PackedVector2Array, "headings": PackedFloat32Array }.
func sample() -> Dictionary:
	var points: PackedVector2Array = PackedVector2Array()
	var headings: PackedFloat32Array = PackedFloat32Array()

	var position: Vector2 = start_position
	var heading: float = deg_to_rad(start_heading)
	points.append(position)
	headings.append(heading)

	for command: Array in commands:
		if command[0] == Command.STRAIGHT:
			var length: float = command[1]
			var steps: int = maxi(1, int(ceil(length / sample_step)))
			var direction: Vector2 = heading_vector(heading)
			for step: int in range(1, steps + 1):
				points.append(position + direction * (length * float(step) / float(steps)))
				headings.append(heading)
			position += direction * length
		else:
			var turn_angle: float = deg_to_rad(command[1])  # positif = a droite
			var radius: float = command[2]
			var steps: int = maxi(2, int(ceil(absf(turn_angle) * radius / sample_step)))
			# Le centre du virage se trouve du cote vers lequel on tourne.
			var right: Vector2 = right_vector(heading)
			var center: Vector2 = position + right * radius * signf(turn_angle)
			var start_angle: float = (position - center).angle()
			for step: int in range(1, steps + 1):
				var t: float = float(step) / float(steps)
				var arc_angle: float = start_angle + turn_angle * t
				points.append(center + Vector2(cos(arc_angle), sin(arc_angle)) * radius)
				# Tourner a droite fait DIMINUER le cap (convention de Godot).
				headings.append(heading - turn_angle * t)
			position = points[points.size() - 1]
			heading -= turn_angle

	return {"points": points, "headings": headings}


## Vecteur unitaire correspondant a un cap. Cap 0 pointe vers -Z.
static func heading_vector(heading: float) -> Vector2:
	return Vector2(-sin(heading), -cos(heading))


## Vecteur unitaire pointant vers la droite du cap donne.
static func right_vector(heading: float) -> Vector2:
	var forward: Vector2 = heading_vector(heading)
	return Vector2(-forward.y, forward.x)
