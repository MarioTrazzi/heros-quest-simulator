extends Node
## Efeitos sonoros sintetizados em código (sem arquivos de áudio), para o jogo
## ter retorno sonoro até a fase de assets. Sfx.play("hit").
##
## Sons: dice, die_hit, hit, block, door, step, spell, heal, trap, coin, death, victory, defeat.

const RATE := 22050
const VOICES := 8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_streams = {
		"dice": _dice(),
		"die_hit": _mix([_noise(0.025, 140.0, 0.55), _tone(2300.0, 0.03, 120.0, 0.12)]),
		"hit": _mix([_tone(110.0, 0.25, 9.0), _noise(0.06, 40.0, 0.5)]),
		"block": _mix([_tone(1400.0, 0.15, 25.0, 0.5), _tone(2100.0, 0.12, 30.0, 0.3)]),
		"door": _to_wav(_sweep(190.0, 90.0, 0.45, 0.5, true)),
		"step": _to_wav(_noise(0.05, 60.0, 0.25)),
		"spell": _mix([_sweep(300.0, 1300.0, 0.45, 0.45), _sweep(450.0, 1950.0, 0.45, 0.2)]),
		"heal": _to_wav(_sweep(520.0, 980.0, 0.35, 0.35)),
		"trap": _mix([_noise(0.3, 10.0, 0.7), _tone(70.0, 0.3, 8.0)]),
		"coin": _to_wav(_notes([1800.0, 2400.0], 0.07, 0.4)),
		"death": _to_wav(_sweep(320.0, 60.0, 0.6, 0.5)),
		"victory": _to_wav(_notes([523.25, 659.25, 783.99, 1046.5], 0.16, 0.45)),
		"defeat": _to_wav(_notes([440.0, 349.23, 293.66, 220.0], 0.26, 0.45)),
	}


## Para tudo. Chame (e espere um quadro) antes de get_tree().quit(): som
## ainda tocando na saída deixa a reprodução vazada.
func stop_all() -> void:
	for player in _players:
		player.stop()
		player.stream = null


func play(sound: String, pitch := 1.0) -> void:
	if not _streams.has(sound) or Settings.volume <= 0.0:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[sound]
	player.pitch_scale = pitch * randf_range(0.94, 1.06)
	player.volume_db = linear_to_db(Settings.volume)
	player.play()


func has_sound(sound: String) -> bool:
	return _streams.has(sound)


# ---------- síntese ----------

## Senoide com decaimento exponencial.
static func _tone(freq: float, duration: float, decay: float, gain := 0.6) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	for i in out.size():
		var t := float(i) / RATE
		out[i] = sin(TAU * freq * t) * exp(-decay * t) * gain
	return out


static func _noise(duration: float, decay: float, gain := 0.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	for i in out.size():
		out[i] = randf_range(-1.0, 1.0) * exp(-decay * float(i) / RATE) * gain
	return out


## Varredura de frequência (dente de serra com tremolo, se `rough`).
static func _sweep(f0: float, f1: float, duration: float, gain: float, rough := false) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	var phase := 0.0
	for i in out.size():
		var k := float(i) / out.size()
		phase += lerpf(f0, f1, k) / RATE
		var wave := (fmod(phase, 1.0) * 2.0 - 1.0) * (0.6 + 0.4 * sin(TAU * 18.0 * k)) if rough else sin(TAU * phase)
		out[i] = wave * gain * sin(PI * k)
	return out


static func _notes(freqs: Array, each: float, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f: float in freqs:
		out.append_array(_tone(f, each, 6.0, gain))
	return out


## Cliques de dados batendo na mesa.
static func _dice() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(int(0.4 * RATE))
	for c in 6:
		var start := int(randf_range(0.0, 0.33) * RATE)
		var click := _noise(0.02, 120.0, 0.6 * (1.0 - c * 0.1))
		for i in click.size():
			if start + i < out.size():
				out[start + i] += click[i]
	return _to_wav(out)


static func _mix(parts: Array) -> AudioStreamWAV:
	var length := 0
	for p: PackedFloat32Array in parts:
		length = maxi(length, p.size())
	var out := PackedFloat32Array()
	out.resize(length)
	for p: PackedFloat32Array in parts:
		for i in p.size():
			out[i] += p[i]
	return _to_wav(out)


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
