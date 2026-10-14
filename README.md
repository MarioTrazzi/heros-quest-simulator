# HeroQuest Simulator (Godot 3D)

Recriação digital do jogo de tabuleiro HeroQuest (1989) em Godot 4.7 (Forward+).

| Pasta | Conteúdo |
|---|---|
| `docs/01-regras-heroquest.md` | Regras completas, stats, feitiços, armeria, tesouros, quests e planta do tabuleiro |
| `docs/02-arquitetura-godot.md` | Arquitetura proposta, modelo de dados, IA, importador de quests e roteiro |
| `data/*.json` | Dados do jogo prontos para carregar no Godot |
| `scripts/logic/` | Motor de regras puro: tabuleiro, movimento, visão, dados, combate e turno |
| `scripts/view/` + `scenes/game.tscn` | Partida em 3D: tabuleiro, miniaturas, câmera e HUD |
| `scenes/main_menu.tscn`, `scenes/campaign_hub.tscn` | Menu inicial e tela da campanha (armeria e quests) |
| `data/quests/` | Quests em JSON (`sandbox.json` = mapa de teste) |
| `tests/` | Testes das regras e smoke da partida, headless |
| `referencias/heroscribe/` | Exemplo de quest no formato HeroScribe XML e catálogo de objetos, para o importador |

Valores marcados com ⚠️ nos docs ou com `_uncertain` nos JSON ainda precisam ser conferidos com o livro de regras físico.

## Roteiro

- [x] **Fase 0** Motor de regras: tabuleiro, BFS, linha de visão, dados, combate e turno, com testes (`AGENTS.md`)
- [x] **Fase 1** Tabuleiro 3D jogável: portas, câmera, clicar para mover/atacar/abrir porta, rodízio de turnos
- [x] **Fase 2** Combate na tela: IA de Zargon, alerta por linha de visão, dados 3D, morte e derrota
- [x] **Fase 3** Exploração: névoa de guerra, busca de tesouro/armadilhas/portas secretas, armadilhas, baralho de tesouro, monstro errante, poções
- [x] **Fase 4** Magia: escolha das escolas, 12 feitiços dos heróis com mira por linha de visão, sono/tempestade/pele de pedra, Chaos Warlock (Bola de Fogo, Sono, Tempestade)
- [x] **Fase 5** Quest completa: objetivo, saída pela escada e vitória; importador do HeroScribe; Barak Tor (mapa oficial) jogável
- [x] **Fase 6** Campanha: menu, tela da campanha, armeria, save/load, ouro e equipamento entre quests, Campeão
- [x] **Fase 7** Polimento: sons sintetizados, opções (velocidade/volume), números de dano e tremor de câmera, pular fosso, espólio do herói morto, todos os feitiços do Caos
- [ ] Mais quests: as 15 do livro base estão em `referencias/heroscribe/hqbase_eu` (mapa + notas); feitas: The Trial, The Rescue of Sir Ragnar, Barak Tor
- [x] **Fase 8** Assets 3D (Blender via MCP, scripts em `tools/blender/`): miniaturas, móveis, piso/paredes/portas e dados
