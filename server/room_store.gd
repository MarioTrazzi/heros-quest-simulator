class_name RoomStore
extends RefCounted
## Salas gravadas em disco: um JSON por sala em <dir>/rooms/<id>.json e um
## índice leve (<dir>/rooms_index.json) para listar o lobby sem abrir todas.
##
## Sala: {id, name, owner_token, owner_name, pass_salt, pass_hash, created,
##        last_played, seats: {hero: {name, token} | null}, campaign: Campaign.to_dict()}
## A quest em andamento vai dentro da campanha (campaign.in_progress).

const HASH_ROUNDS := 2000

var dir := ""
## id → resumo (ver summary()).
var index: Dictionary = {}


func _init(p_dir: String) -> void:
	dir = p_dir
	DirAccess.make_dir_recursive_absolute(dir.path_join("rooms"))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_index_path())) \
		if FileAccess.file_exists(_index_path()) else null
	if data is Dictionary:
		index = data
	else:
		_rebuild_index()


func _index_path() -> String:
	return dir.path_join("rooms_index.json")


func _room_path(id: String) -> String:
	return dir.path_join("rooms").path_join(id + ".json")


## Índice perdido ou corrompido: refaz lendo as salas.
func _rebuild_index() -> void:
	index = {}
	for file in DirAccess.get_files_at(dir.path_join("rooms")):
		if file.ends_with(".json"):
			var rec := load_room(file.get_basename())
			if not rec.is_empty():
				index[rec.id] = summary(rec)
	_write(_index_path(), index)


func create(room_name: String, password: String, token: String, player_name: String) -> Dictionary:
	var id := _new_id()
	var salt := _random_hex(16)
	var seats := {}
	for hero_id in QuestLoader.HERO_ORDER:
		seats[hero_id] = null
	var now := int(Time.get_unix_time_from_system())
	var rec := {
		"id": id, "name": room_name, "owner_token": token, "owner_name": player_name,
		"pass_salt": salt, "pass_hash": hash_password(salt, password) if password != "" else "",
		"created": now, "last_played": now, "seats": seats, "campaign": Campaign.create().to_dict(),
	}
	save_room(rec)
	return rec


## {} se não existe ou não abre.
func load_room(id: String) -> Dictionary:
	if not id.is_valid_hex_number() or not FileAccess.file_exists(_room_path(id)):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_room_path(id)))
	return data if data is Dictionary else {}


func save_room(rec: Dictionary) -> void:
	_write(_room_path(rec.id), rec)
	var line := summary(rec)
	if index.get(rec.id) != line:
		index[rec.id] = line
		_write(_index_path(), index)


func count_owned(token: String) -> int:
	return index.values().filter(func(s: Dictionary) -> bool: return s.get("owner_token") == token).size()


## Salas cujo nome contém `search` (sem diferenciar maiúsculas), as mais recentes primeiro.
func list(search: String, limit := 50) -> Array:
	var needle := search.strip_edges().to_lower()
	var out := index.values().filter(func(s: Dictionary) -> bool: return needle == "" or str(s.name).to_lower().contains(needle))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.last_played) > int(b.last_played))
	return out.slice(0, limit)


## O que o lobby mostra (sem senha; o token do dono fica só no servidor).
static func summary(rec: Dictionary) -> Dictionary:
	var seated: Array = []
	for hero_id: String in rec.seats:
		if rec.seats[hero_id] != null:
			seated.append(rec.seats[hero_id].token)
	var running: Dictionary = rec.campaign.get("in_progress", {})
	return {
		"id": rec.id, "name": rec.name, "owner": rec.owner_name, "owner_token": rec.owner_token,
		"locked": rec.pass_hash != "", "seats": seated.size(), "seat_tokens": seated,
		"quest": running.get("quest_id", ""), "completed": rec.campaign.get("completed", []).size(),
		"last_played": int(rec.last_played),
	}


static func check_password(rec: Dictionary, password: String) -> bool:
	if rec.pass_hash == "":
		return true
	var given := hash_password(rec.pass_salt, password)
	# Compara em tempo constante.
	var diff := given.length() ^ str(rec.pass_hash).length()
	for i in mini(given.length(), str(rec.pass_hash).length()):
		diff |= given.unicode_at(i) ^ str(rec.pass_hash).unicode_at(i)
	return diff == 0


static func hash_password(salt: String, password: String) -> String:
	var digest := salt + password
	for i in HASH_ROUNDS:
		digest = (salt + digest).sha256_text()
	return digest


func _new_id() -> String:
	var id := _random_hex(5)
	while FileAccess.file_exists(_room_path(id)):
		id = _random_hex(5)
	return id


static func _random_hex(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()


## Grava num temporário e troca: um servidor que cai no meio não corrompe a sala.
static func _write(path: String, data: Variant) -> void:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("RoomStore: não consegui gravar %s" % path)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(tmp, path)
