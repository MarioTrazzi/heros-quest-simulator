class_name Room
extends RefCounted
## Sala acordada no servidor: a campanha e a quest em andamento na memória,
## e quem está presente. Dorme (sai da memória) quando o último sai; tudo já
## está gravado.
##
## Quem joga cada herói: o dono do assento, se está presente; se faltou,
## qualquer jogador sentado na sala (como na mesa). O aliado escoltado também
## pode ser jogado por qualquer um sentado.

var record: Dictionary
var campaign: Campaign
var quest_match: Match
## peer → {"token", "name"}
var peers: Dictionary = {}


func _init(rec: Dictionary) -> void:
	record = rec
	campaign = Campaign.from_dict(rec.campaign)
	if not campaign.in_progress.is_empty():
		quest_match = Match.from_dict(campaign.in_progress)
		if quest_match == null:
			push_error("Sala %s: quest em andamento não fecha no replay; descartada" % rec.id)
			campaign.in_progress = {}


func id() -> String:
	return record.id


func is_owner(token: String) -> bool:
	return record.owner_token == token


func heroes_of(token: String) -> Array[String]:
	var out: Array[String] = []
	for hero_id: String in record.seats:
		var seat: Variant = record.seats[hero_id]
		if seat != null and seat.token == token:
			out.append(hero_id)
	return out


func is_seated(token: String) -> bool:
	return not heroes_of(token).is_empty()


func is_present(token: String) -> bool:
	return peers.values().any(func(p: Dictionary) -> bool: return p.token == token)


## Pode jogar o herói `hero_id` agora?
func can_control(token: String, hero_id: String) -> bool:
	if not is_seated(token):
		return false
	var seat: Variant = record.seats.get(hero_id)
	if seat == null or not is_present(seat.token):
		return true
	return seat.token == token


## Pode mandar este comando? (escolas: quem joga o Mago; o resto: quem joga o herói ativo)
func can_command(token: String, cmd: Dictionary) -> bool:
	if quest_match == null:
		return false
	if cmd.get("type") == "schools":
		return can_control(token, "wizard")
	var active := quest_match.state.active
	if active == null or not active.is_hero():
		return false
	if active.escort:
		return is_seated(token)
	return can_control(token, active.def_id)


## Copia a campanha da memória para o registro (antes de gravar).
func sync_record() -> void:
	if quest_match != null:
		campaign.in_progress = quest_match.to_dict()
	record.campaign = campaign.to_dict()
	record.last_played = int(Time.get_unix_time_from_system())


## O que o jogador `token` vê: assentos sem tokens, quem está online, a campanha inteira.
func view_for(token: String) -> Dictionary:
	var seats := {}
	for hero_id: String in record.seats:
		var seat: Variant = record.seats[hero_id]
		seats[hero_id] = null if seat == null else {
			"name": seat.name, "online": is_present(seat.token), "mine": seat.token == token}
	var online: Array = []
	for p: Dictionary in peers.values():
		if not online.has(p.name):
			online.append(p.name)
	return {
		"id": record.id, "name": record.name, "owner": record.owner_name, "is_owner": is_owner(token),
		"locked": record.pass_hash != "", "seats": seats, "online": online, "campaign": record.campaign,
	}
