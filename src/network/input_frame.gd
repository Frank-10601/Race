class_name InputFrame
extends RefCounted
## Une trame d'entrees du joueur, estampillee d'un numero de sequence.
##
## C'est la SEULE chose que le client envoie au serveur. Jamais de position :
## le serveur est autoritaire (voir CLAUDE.md, contrainte 1).
##
## Encodage compact : 8 octets par trame. A 60 Hz cela represente 480 octets par
## seconde et par joueur, redondance comprise.

## Taille d'une trame encodee, en octets.
const ENCODED_SIZE: int = 8

const _FLAG_HANDBRAKE: int = 1 << 0
const _FLAG_RESPAWN: int = 1 << 1

## Numero de sequence, croissant de 1 en 1 a chaque pas de simulation client.
var sequence: int = 0
## Acceleration, de 0 a 1 (float pour accepter une gachette analogique plus tard).
var throttle: float = 0.0
## Frein / marche arriere, de 0 a 1.
var brake: float = 0.0
## Direction, de -1 (gauche) a 1 (droite).
var steer: float = 0.0
## Frein a main : declenche le derapage.
var handbrake: bool = false
## Demande de remise en piste manuelle (touche R).
var respawn: bool = false


static func create(p_sequence: int, p_throttle: float, p_brake: float,
		p_steer: float, p_handbrake: bool, p_respawn: bool) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	frame.sequence = p_sequence
	frame.throttle = clampf(p_throttle, 0.0, 1.0)
	frame.brake = clampf(p_brake, 0.0, 1.0)
	frame.steer = clampf(p_steer, -1.0, 1.0)
	frame.handbrake = p_handbrake
	frame.respawn = p_respawn
	return frame


## Trame neutre, utilisee par le serveur quand aucune entree n'est disponible
## pour ce tick (le joueur laisse alors rouler la voiture en roue libre).
static func neutral(p_sequence: int) -> InputFrame:
	return InputFrame.create(p_sequence, 0.0, 0.0, 0.0, false, false)


func duplicate_frame() -> InputFrame:
	return InputFrame.create(sequence, throttle, brake, steer, handbrake, respawn)


## Ecrit la trame a la position donnee dans un tampon d'octets.
func encode_into(buffer: PackedByteArray, offset: int) -> void:
	buffer.encode_u32(offset, sequence)
	buffer.encode_u8(offset + 4, int(round(throttle * 255.0)))
	buffer.encode_u8(offset + 5, int(round(brake * 255.0)))
	buffer.encode_s8(offset + 6, int(round(steer * 127.0)))
	var flags: int = 0
	if handbrake:
		flags |= _FLAG_HANDBRAKE
	if respawn:
		flags |= _FLAG_RESPAWN
	buffer.encode_u8(offset + 7, flags)


static func decode_from(buffer: PackedByteArray, offset: int) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	frame.sequence = buffer.decode_u32(offset)
	frame.throttle = float(buffer.decode_u8(offset + 4)) / 255.0
	frame.brake = float(buffer.decode_u8(offset + 5)) / 255.0
	frame.steer = clampf(float(buffer.decode_s8(offset + 6)) / 127.0, -1.0, 1.0)
	var flags: int = buffer.decode_u8(offset + 7)
	frame.handbrake = (flags & _FLAG_HANDBRAKE) != 0
	frame.respawn = (flags & _FLAG_RESPAWN) != 0
	return frame


## Encode un lot de trames. Le client renvoie ses dernieres entrees a chaque
## paquet : une entree perdue (transport non fiable) est ainsi rattrapee par le
## paquet suivant, sans accuse de reception.
static func encode_batch(frames: Array[InputFrame]) -> PackedByteArray:
	var buffer: PackedByteArray = PackedByteArray()
	buffer.resize(frames.size() * ENCODED_SIZE)
	for index: int in frames.size():
		frames[index].encode_into(buffer, index * ENCODED_SIZE)
	return buffer


static func decode_batch(buffer: PackedByteArray) -> Array[InputFrame]:
	var frames: Array[InputFrame] = []
	var count: int = buffer.size() / ENCODED_SIZE
	for index: int in count:
		frames.append(decode_from(buffer, index * ENCODED_SIZE))
	return frames
