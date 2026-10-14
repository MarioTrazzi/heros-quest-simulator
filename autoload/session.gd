extends Node
## Ponte entre as cenas: a campanha em jogo, a quest escolhida e a troca de tela
## (menu → campanha → partida → campanha).

const MENU := "res://scenes/main_menu.tscn"
const HUB := "res://scenes/campaign_hub.tscn"
const GAME := "res://scenes/game.tscn"
const LOBBY := "res://scenes/online_lobby.tscn"
const SERVER := "res://scenes/server.tscn"

## null = partida avulsa (heróis novos, nada é gravado).
var campaign: Campaign
## Campanha de uma sala online (vem do servidor, que é quem grava).
var online := false
var quest_id := ""
var save_path := Campaign.SAVE_PATH
## Testes: as telas entram como filhas deste nó, em vez de trocar a cena atual.
var host: Node
## Prévia da arte (provisório): todas as quests liberadas na campanha local e o
## tabuleiro inteiro à vista, sem névoa. Só muda o que aparece na tela; as regras
## (revelar, alertar monstros) seguem iguais e o online não muda. Desligar: false.
var preview := true


func _ready() -> void:
	CardStyle.apply_theme()  # papel do jogo em todas as telas
	if OS.get_cmdline_user_args().has("--server"):
		get_tree().change_scene_to_file.call_deferred(SERVER)


func new_campaign() -> void:
	online = false
	campaign = Campaign.create()
	campaign.save(save_path)
	go(HUB)


## false se não há save.
func continue_campaign() -> bool:
	online = false
	campaign = Campaign.load_from(save_path)
	if campaign == null:
		return false
	go(HUB)
	return true


func play(id: String, with_campaign := true) -> void:
	if not with_campaign:
		campaign = null
		online = false
	quest_id = id
	go(GAME)


## Anota o resultado na campanha e grava. {} em partida avulsa.
## Online quem grava é o servidor: o resumo sai de uma cópia da campanha do começo da quest.
func finish_quest(state: GameState, campaign_at_start := {}) -> Dictionary:
	if campaign == null:
		return {}
	if online:
		return Campaign.from_dict(campaign_at_start).record(state, quest_id)
	var report := campaign.record(state, quest_id)
	campaign.save(save_path)
	return report


## Sai do jogo online e volta ao menu.
func go_offline() -> void:
	Net.disconnect_server()
	online = false
	campaign = null
	go(MENU)


func go(path: String) -> void:
	if host != null:
		for child in host.get_children():
			child.queue_free()
		host.add_child(load(path).instantiate())
	else:
		get_tree().change_scene_to_file.call_deferred(path)


## Tela em uso quando `host` está ligado (testes).
func current_screen() -> Node:
	return host.get_child(host.get_child_count() - 1) if host != null and host.get_child_count() > 0 else null
