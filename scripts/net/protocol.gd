class_name Protocol
extends RefCounted
## Protocolo online: mensagens JSON {"t": tipo, ...} sobre WebSocket.
##
## Cliente → servidor:
##   hello {token, name, version} · list_rooms {search} · create_room {name, password}
##   enter_room {id, password} · leave_room · sit {hero} · free_seat {hero}
##   buy {hero, item} · start_quest {quest} · abandon_quest · command {cmd} · sync
## Servidor → cliente:
##   welcome · error {reason} · rooms {rooms} · room {room} (visão de quem recebe)
##   quest_started {quest} (a partida vem no room logo antes) · applied {seq, cmd, hash} · left
##
## Cliente e servidor precisam rodar as mesmas regras (a partida é sincronizada
## reaplicando comandos): suba VERSION quando mudar regra, dado ou quest.

const VERSION := 4
const DEFAULT_PORT := 8765
## Partidas longas mandam o log inteiro ao entrar na sala.
const BUFFER_SIZE := 4 * 1024 * 1024
const MAX_NAME := 24
const MAX_ROOM_NAME := 40
const MAX_PASSWORD := 64


static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)


## {} se não for uma mensagem válida.
static func decode(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary and data.get("t") is String:
		return data
	return {}


## Nome digitado pelo jogador: sem espaços nas pontas e sem quebra de linha.
static func clean_name(value: Variant, max_len: int) -> String:
	if not value is String:
		return ""
	return value.replace("\n", " ").replace("\r", " ").strip_edges().left(max_len)
