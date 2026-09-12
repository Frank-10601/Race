extends Node
## Verifie la geometrie produite par TrackPlan.
## Lancer : godot --headless res://tools/tests/test_track_plan.tscn

var _failures: int = 0


func _ready() -> void:
	_test_straight()
	_test_right_turn()
	_test_left_turn()
	if _failures == 0:
		print("TrackPlan : tous les tests passent.")
	else:
		printerr("TrackPlan : %d test(s) en echec." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_straight() -> void:
	var plan: TrackPlan = TrackPlan.new()
	plan.straight(100.0)
	var result: Dictionary = plan.sample()
	var points: PackedVector2Array = result["points"]
	_expect_vector("ligne droite : arrivee", points[points.size() - 1], Vector2(0.0, -100.0))


func _test_right_turn() -> void:
	# 50 m tout droit, 90 degres a droite sur rayon 50, puis 50 m tout droit.
	var plan: TrackPlan = TrackPlan.new()
	plan.straight(50.0).turn(90.0, 50.0).straight(50.0)
	var result: Dictionary = plan.sample()
	var points: PackedVector2Array = result["points"]
	var headings: PackedFloat32Array = result["headings"]
	# Apres le virage on roule vers +X : cap -90 degres.
	_expect_vector("virage droite : arrivee", points[points.size() - 1], Vector2(100.0, -100.0))
	_expect_float("virage droite : cap", rad_to_deg(headings[headings.size() - 1]), -90.0)


func _test_left_turn() -> void:
	var plan: TrackPlan = TrackPlan.new()
	plan.straight(50.0).turn(-90.0, 50.0).straight(50.0)
	var result: Dictionary = plan.sample()
	var points: PackedVector2Array = result["points"]
	var headings: PackedFloat32Array = result["headings"]
	_expect_vector("virage gauche : arrivee", points[points.size() - 1], Vector2(-100.0, -100.0))
	_expect_float("virage gauche : cap", rad_to_deg(headings[headings.size() - 1]), 90.0)


func _expect_vector(label: String, actual: Vector2, expected: Vector2) -> void:
	if actual.distance_to(expected) > 0.05:
		printerr("ECHEC %s : obtenu %s, attendu %s" % [label, actual, expected])
		_failures += 1


func _expect_float(label: String, actual: float, expected: float) -> void:
	if absf(actual - expected) > 0.1:
		printerr("ECHEC %s : obtenu %.3f, attendu %.3f" % [label, actual, expected])
		_failures += 1
