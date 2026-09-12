extends Control
## Affichage en course. Phase 0 : le compteur de vitesse, et rien d'autre.
##
## Les tours, le chronometre et le classement arrivent en phase 1 : ne rien
## ajouter ici tant que ce n'est pas leur tour (CLAUDE.md, section 5).

## Duree d'affichage d'un message passager, en secondes.
const NOTICE_DURATION: float = 2.5

@onready var _speed: Label = $SpeedBox/Speed
@onready var _drift: Label = $Drift
@onready var _notice: Label = $Notice

var _vehicle: Vehicle = null
var _notice_timer: float = 0.0


func _ready() -> void:
	_drift.visible = false
	_notice.text = ""


func set_vehicle(vehicle: Vehicle) -> void:
	_vehicle = vehicle


func show_notice(message: String) -> void:
	_notice.text = message
	_notice_timer = NOTICE_DURATION


func _process(delta: float) -> void:
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			_notice.text = ""

	if _vehicle == null or not is_instance_valid(_vehicle):
		return

	_speed.text = "%d" % roundi(_vehicle.get_speed_kmh())
	# Le temoin n'apparait qu'en derapage franc : sinon il clignote sans arret.
	_drift.visible = _vehicle.state.drift > 0.35
	if _drift.visible:
		_drift.modulate.a = clampf(_vehicle.state.drift, 0.4, 1.0)
