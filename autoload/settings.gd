extends Node
## Opções do jogador: velocidade das animações e volume. Gravadas em
## user://settings.json e aplicadas na hora (Engine.time_scale).

const PATH := "user://settings.json"
const SPEEDS := {"Normal": 1.0, "Rápida": 1.75, "Muito rápida": 3.0}

var speed := 1.0
var volume := 0.7


func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if data is Dictionary:
		speed = float(data.get("speed", speed))
		volume = clampf(float(data.get("volume", volume)), 0.0, 1.0)
	apply()


func set_speed(value: float) -> void:
	speed = value
	apply()
	save()


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	save()


func apply() -> void:
	Engine.time_scale = speed


func save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"speed": speed, "volume": volume}))
