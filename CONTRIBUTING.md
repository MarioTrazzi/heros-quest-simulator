# Como contribuir

Que bom que você quer ajudar! Dá para contribuir com quests, arte, regras, testes, tradução
ou um jogo derivado. Não precisa saber programar para tudo.

## Antes de começar

1. Abra uma [issue](https://github.com/MarioTrazzi/heros-quest-simulator/issues/new) contando o
   que você quer fazer. Assim a gente combina o caminho antes de você gastar tempo.
2. Faça um fork, crie uma branch com um nome que diga o que ela faz (`quest-cripta-do-relojoeiro`,
   `feitico-raio`) e mande um pull request quando estiver pronto.

## Rodando o projeto

Instale o [Godot 4.7](https://godotengine.org/download) (versão padrão, sem .NET), clone o
repositório e abra a pasta no Godot (F5 roda o jogo). Antes de mandar o PR, rode os testes:

```bash
godot --headless --path . --import
godot --headless --path . res://tests/rules_tests.tscn
godot --headless --path . res://tests/game_smoke.tscn
godot --headless --path . res://tests/campaign_smoke.tscn
godot --headless --path . res://tests/net_smoke.tscn
```

O [`AGENTS.md`](AGENTS.md) explica cada parte do código e as decisões de regra. Leia antes de
mexer no motor.

## Por onde contribuir

- **Quests**: um arquivo JSON em `data/quests/` (formato em
  [`docs/02-arquitetura-godot.md`](docs/02-arquitetura-godot.md) §5) e o id dela em
  `data/campaign.json`. Use `sandbox.json` como exemplo.
- **Regras** (`scripts/logic/`): classes puras, sem nada de 3D. Toda regra nova ganha um teste em
  `tests/rules_tests.gd`.
- **Arte e 3D** (`assets/`, `tools/blender/`): modelos, texturas, cartas e retratos.
- **Interface** (`scripts/view/`, `scenes/`): HUD, cartas, telas e câmera.

## Regras do código

- **Sorteio só pelo `Dice`.** A partida é reconstruída reaplicando os comandos a partir da mesma
  semente (save no meio da quest e jogo online dependem disso). Nada de `randi()` solto nem de
  `instance_id` em chave de estado.
- **Mudou regra, dado ou quest? Suba `Protocol.VERSION`** em `scripts/net/protocol.gd`, porque
  cliente e servidor precisam rodar exatamente as mesmas regras.
- **Dados ficam em JSON**, não no código. O JSON do Godot lê número como float: use `int()`.
- Comentários e textos do jogo em português.

## Conteúdo de terceiros

Este é um projeto de fã. **Não envie** texto, arte, cartas ou mapas copiados de livros, caixas ou
sites oficiais de HeroQuest ou de outros jogos comerciais, nem traduções deles. Mecânicas de jogo
podem ser reimplementadas; o conteúdo, não. Quests, heróis, monstros e ilustrações originais são
muito bem-vindos. Arte gerada por IA pode, desde que não use a arte oficial como referência de entrada.

Ao contribuir, você concorda que sua contribuição fica sob a [licença MIT](LICENSE) do projeto.
