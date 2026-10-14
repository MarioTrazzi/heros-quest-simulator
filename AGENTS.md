# AGENTS.md

## Projeto (HeroQuest Simulator — Godot)

Recriação 3D do jogo de tabuleiro **HeroQuest (1989)** em **Godot 4.7 (GDScript)**,
renderizador **Forward+**. Referência de regras em `docs/01-regras-heroquest.md`;
arquitetura e roteiro por fases em `docs/02-arquitetura-godot.md`.

## Organização

- **Dados** (`data/*.json`): heróis, monstros, armeria, feitiços, artefatos,
  móveis, baralho de tesouro e a planta do tabuleiro (`board.json`, zonas por
  quadrado). Lidos pelo autoload `GameData`. Campos `_uncertain` ainda precisam
  ser conferidos com o livro de regras. O JSON do Godot lê número como float: use `int()`.
- **Regras** (`scripts/logic/*.gd`): classes puras (`RefCounted`), sem nada de 3D.
  `Board` (paredes nas arestas), `Pathfinder` (BFS), `LineOfSight` (supercover),
  `Dice` (RNG com seed), `Unit`, `Combat`, `GameState` (turno), `ZargonAI`
  (monstros alertados: ataca se alcança → anda e ataca → avança pelo caminho mais curto),
  `Exploration` (procurar tesouro/armadilhas/portas secretas, armadilhas, baralho de
  tesouro, monstro errante, desarme e itens), `Magic` (escolas, alvos e efeitos dos
  feitiços, de heróis e do Caos).
  As ações devolvem **eventos** (Dictionary com `type`) para a apresentação animar.
- **Quests** (`data/quests/*.json`): montadas por `QuestLoader` (portas, portas
  secretas, móveis com `rot`, blocos, monstros com `override`, quadrados de início).
  Também armadilhas (`trap`: pit, spear, falling_block, chest), tesouro da quest por
  sala (`treasure`), `wandering_monster` e `theme` (chão/parede pintados, ver Arte). O baralho de tesouro é embaralhado com a
  seed da partida. `sandbox.json` é um mapa próprio de teste, não uma quest oficial.
- **Quests do HeroScribe**: `"heroscribe": "res://referencias/heroscribe/x.xml"` traz o
  mapa (`HeroScribeImporter`: base 1 → base 0, rotação, portas, portas secretas,
  `<dark>` → `board.dark`); a quest JSON só acrescenta o que o livro diz: `objective`,
  `wandering_monster`, `intro` e `letters` (A → `fake_door`, `treasure`, `monster`
  com override/`objective`). O XML não traz o texto das letras: as notas de
  `barak_tor.json` são provisórias e devem ser conferidas no livro. Ao exportar o
  jogo, inclua `*.xml` no filtro de recursos não importados.
  As 15 quests do livro base UE estão em `referencias/heroscribe/hqbase_eu/` (do repositório
  github.com/heroscribe/heroscribe); esses XML trazem a introdução (`<speech>`) e as notas
  das letras (`<note>`), que traduzimos para a quest JSON. Nota sem letra no mapa usa
  `"at": [x, y]` (base 0), como o Verag de `the_trial.json`. Letras também podem ter
  `carries` (o monstro leva um item da quest; quem o mata fica com ele, senão vira tesouro
  da sala), `awaken` (monstro surge quando um herói entra na sala; `at_letter` diz onde) e
  `captive` (prisioneiro do objetivo `escort`). Tesouro da quest aceita `items` (cartas que vão
  para o inventário; `quest_item: true` não volta ao baralho ao ser usada).
- **Objetivo**: `escape`, `kill` (monstros com `objective`), `kill_all`, `find`
  (tesouro com `objective_item` ou item carregado por monstro), `escort` (o aliado resgatado
  sai pela escada; se morrer, a quest falha na hora). Cumprido o objetivo, herói que chega à escada sai
  do tabuleiro; a quest acaba quando não sobra herói nele (vitória se alguém saiu).
  `HQ_QUEST=<id>` escolhe a quest quando `game.tscn` abre direto (padrão `barak_tor`).
- **Campanha** (`Campaign`, `Armory`, autoload `Session`): menu → `campaign_hub` →
  `game` → `campaign_hub` (sair no meio guarda a quest para continuar). Save em `user://campaign.json` (`Session.save_path`; os
  testes usam outro arquivo). Entre quests: ficha e feitiços voltam ao máximo;
  sobrevivente guarda ouro e equipamento (poções não passam); morto recomeça do zero;
  3 quests = Campeão (+500, uma vez). Armeria: uma peça por espaço (substitui sem
  devolver ouro), artefatos nunca são trocados, restrições do Mago e do escudo × duas
  mãos. Ordem das quests em `data/campaign.json` (quest nova entra no fim de saves
  antigos). "Abandonar" (na campanha) joga fora a quest em andamento. `Session.host` (testes) põe as telas
  como filhas de um nó em vez de trocar a cena.
- **Partida por comandos** (`Match`, `scripts/logic/match.gd`): quest + seed + heróis do começo +
  log de comandos serializáveis (`{"type": "move", "to": [x, y]}` etc.). `apply(cmd)` valida, aplica
  no `GameState`, roda a vez de Zargon (`zargon_turn` com os eventos de cada monstro) e devolve os
  eventos; comando inválido devolve `[]` e não entra no log. Reaplicar o log (`from_dict`) chega ao
  mesmo estado (`state_hash()`): é o save no meio da quest (`Campaign.in_progress`, save versão 2;
  a armeria fecha enquanto há quest em andamento) e a sincronização online. Por isso: nada de RNG
  fora do `Dice` nem `instance_id` em chave de estado.
- **Online** (`server/`, `scripts/net/`, autoload `Net`): lobby público de salas; sala = campanha
  persistente com senha opcional (sal + SHA-256) e 4 assentos (um por herói, dono = token do
  aparelho em `user://identity.json`). `HqServer` (headless: `$G --headless --path . -- --server`,
  `PORT` e `HQ_DATA_DIR`) é autoritativo: valida a vez (`Room.can_control`: o dono presente joga o
  seu herói; o de quem faltou, qualquer um sentado), aplica no `Match`, grava (`RoomStore`: um JSON
  por sala + índice do lobby) e repassa `applied {seq, cmd, hash}`; cada cliente reaplica e confere
  o hash (diverge → `sync` e reabre a partida). Na sala cada jogador escolhe herói ("Escolher"; herói
  com dono fica indisponível para os outros); a quest só leva os heróis com dono, na ordem de
  `Match.roll_initiative` (1d6 cada, empate no maior rola de novo, quem tira mais começa, os outros em
  ordem sorteada), guardada em `Match.initiative` e mostrada na abertura da partida. Protocolo JSON sobre WebSocket em `Protocol`; suba
  `Protocol.VERSION` quando mudar regra, dado ou quest. Telas: `online_lobby` → `campaign_hub`
  (modo online, com assentos) → `game`. `Dockerfile` sobe o servidor (Railway/VPS, volume em `/data`).
- **Apresentação** (`scripts/view/`, `scenes/game.gd`): `BoardView` (piso, paredes,
  portas, móveis, marcas), `FigureView` (miniatura provisória de primitivos),
  `CameraRig`, `DiceTray`/`DieView`/`DiceSim` (dados 3D que caem do alto no próprio tabuleiro,
  perto da ação e do lado da câmera: `DiceSim` simula a física inteira de antemão — quicam no chão,
  batem nas peças à vista perto da queda (caixa de cada malha da cena; miniaturas, paredes e portas
  viram colunas altas) e entre si, estalo `die_hit` a cada batida — e a `DiceTray` reproduz a
  gravação; o valor vem do `Dice` e `DieView.show_face` gira só o desenho para a face sorteada ficar
  para cima; no combate o ataque cai primeiro e a defesa depois, jogada do outro lado), `Hud` (botões embaixo no
  centro, ficha e grupo no alto à direita, objetivo no alto à esquerda, cartas do inventário
  embaixo à esquerda, log pequeno embaixo à direita, carta de tesouro no alto).
  `GameCard` é toda carta de papel do jogo, como no original: tesouro, feitiço (dos heróis e do
  Caos), equipamento e artefato são cartas brancas de moldura marrom rasgada, título em cursiva,
  ilustração a nanquim (`cards/ink/<id>.png`, de `tools/gen_cards.py --ink`: cenas inspiradas nas
  cartas originais, desenhadas de novo — nunca a arte original como entrada; sem o arquivo, a
  pintura colorida passa pelo filtro `CardStyle.ink_material`) num quadro deitado,
  texto, linha de regra e (tesouro) a faixa "HeroQuest"; monstro é pergaminho com o selo redondo
  nos cantos, ilustração colorida e os atributos por extenso. `create_back` faz o verso (pintura +
  faixa com o nome do baralho): o tesouro achado aparece de costas e vira. Todas na proporção
  das cartas do jogo europeu de 1989 (≈ 54 × 80 mm, `GameCard.ASPECT`). Estreita (< 150 px) é
  carta de mão: cresce com o mouse e o clique usa o item/escolhe o feitiço. Aparece na mão do
  herói (itens em cima, feitiços embaixo, encavalados se não cabem), na escolha das escolas,
  grande no alto (tesouro, artefato, feitiço lançado, monstro avistado pela 1ª vez) e na armeria
  da campanha. O texto vem do campo `text` dos
  dados (feitiços, artefatos) ou é montado pelos campos (poções, equipamento). O livro de quests
  abre a partida: pergaminho com a introdução e o objetivo (`Hud.show_intro`, "Começar" chama
  `game._begin`). Arte em `assets/textures/cards/<id>.png` (`tools/gen_cards.py`; cartas parecidas
  dividem a arte por `GameCard.ART_ALIAS`); sem ela, mostra a inicial.
  Tema único (`CardStyle.theme()`, posto no tema padrão do Godot por `CardStyle.apply_theme()` no
  `Session._ready`, para valer também dentro de `CanvasLayer`/cenas 3D): botões de pergaminho com
  título em cursiva, painéis de couro escuro com borda dourada, campos e dicas em pergaminho.
  Menu, campanha e lobby usam `CardStyle.backdrop()` (pintura do baú escurecida), títulos
  `CardStyle.heading()` e faixas de pergaminho por quest/sala (selo `CardStyle.seal()`: Próxima,
  Cumprida, Em andamento, Bloqueada).
  O papel imita o HeroQuest europeu de 1989 (`CardStyle`: fontes livres em `assets/fonts` —
  Fondamento Italic nos títulos em cursiva, Crimson Text no texto —, pergaminho de bordas
  queimadas e carta branca de moldura rasgada gerados em código, filtro de esboço a nanquim).
  `HeroSheet` é a carta de personagem (54 × 80 mm, pergaminho): nome em cursiva, retrato
  grande na moldura dourada de fundo vermelho (recortado a partir do alto, `TopCrop`); a
  apresentação (`text` em `heroes.json`) aparece sobre ele com o mouse na carta. Ao lado, o herói
  de corpo inteiro (miniatura 3D num `SubViewport`, gira arrastando para os lados; o arco
  `TurnHint` nos pés avisa) com Mente e Corpo embaixo; atributos por extenso em três colunas
  ("Ataque — rola 3 dados de combate"); extra, equipamento e `footer()` ficam embaixo da carta. O Corpo é uma fileira de quadradinhos (`HeroSheet.BodyTrack`), riscados com um X a lápis a cada ponto perdido (o risco novo é traçado na hora; cura apaga). Na campanha a carta é
  clicável (`clickable`, `pressed`): abre a armeria do herói e fica com contorno dourado (`selected`);
  a tela inteira rola. A mesma carta é a ficha do monstro na partida (`Hud.show_monster`): clicar num
  monstro à vista abre a ficha à esquerda da do herói (e ataca, se dá); monstro ferido também a abre, com o
  Corpo de antes e o X traçado no golpe; clique na ficha ou Esc fecha. Retrato pintado em
  `assets/textures/ui/portrait_<id>.png` (gerados
  por IA: os quatro no Higgsfield com o `STYLE` de `tools/gen_portraits.py`; o script em si usa a
  OpenAI, com a chave em `OPENAI_API_KEY` ou `~/.openai_key`); sem ele, fotografa a miniatura.
  O estilo-alvo de toda arte pintada é o do Bárbaro e do Mago: Higgsfield `generate_image`,
  modelo `nano_banana_2`, `aspect_ratio` 3:4, `resolution` 1k, prompt `STYLE % descrição` dos
  scripts em `tools/`. O que veio da OpenAI (cartas, temas, móveis de papel) é provisório e será refeito lá.
  A moderação da OpenAI recusa algumas descrições (ex.: "lockpicks"); o script avisa e segue.
- **Som e opções**: `Sfx` sintetiza os efeitos em código (`Sfx.play("hit")`);
  `Settings` guarda velocidade (Engine.time_scale) e volume em `user://settings.json`.
  Nos testes, chame `Sfx.stop_all()` e espere ~0,1 s antes de `quit()` (som tocando
  na saída deixa reprodução vazada).
- **Arte (Fase 8)**: modelos feitos no Blender via MCP por scripts em
  `tools/blender/` (funções comuns em `hq_common.py`; rode no Blender:
  `g = {}; exec(open(".../build_x.py").read(), g); g["run"]()`, com `run(only=[...], do_export=False)`
  + `preview(caminho)` para só ver). Frente da peça em -Y do Blender = +Z no Godot, apoio em z = 0.
  - `build_figures.py` → `assets/models/figures/<def_id>.glb`. Miniatura por IA (o Bárbaro já é assim):
    retrato → corpo inteiro de frente no Higgsfield (`nano_banana_2` com o retrato como referência, fundo
    cinza liso) → `generate_3d` com `tripo_h3_1_image_to_3d` (textura `detailed`, sem PBR, 20 mil faces)
    → `fit_ai_figure.py` no Blender em segundo plano (`-- bruto.glb saida.glb ALTURA --turn -90 --preview x.png`:
    frente em -Y, pés em z = 0, 12 mil faces, textura até 1024 px). Rodar `build_figures.py` sobrescreve esses .glb. `FigureView` carrega o .glb
    (senão monta a figura de primitivos), pisca com `material_overlay` e vira para onde anda/ataca.
  - `build_furniture.py` → `assets/models/furniture/<id>.glb` (+ `rubble` dos quadrados
    bloqueados). A peça vem no tamanho sem giro do `furniture.json`; `BoardView` gira por
    `rot` (0..3 = virada para baixo/esquerda/cima/direita, costas na parede oposta, como no
    HeroScribe). Estante, armário, lareira e suporte de armas que o mapa deixar de frente
    para a parede viram 180° (o giro do HeroScribe varia entre mapas). Sem .glb, cai na
    caixa colorida. A lareira ganha uma luz que bruxuleia.
  - `build_board.py` → texturas assadas (Cycles) em `assets/textures/board/` (`floor_room`,
    `floor_corridor`, `wall`: `_albedo` + `_normal`) e `assets/models/board/` (`door`, `secret_door`
    com a dobradiça na origem e a folha em +X; `door_frame` centrado na aresta). `BoardView`
    usa triplanar (piso local, girado 0–3×90° por quadrado; paredes no mundo), tinge cada sala
    e faz a névoa com a mesma textura escurecida. Sem os arquivos, volta às cores lisas.
  - `build_dice.py` → `assets/models/dice/combat.glb` e `d6.glb` (cubo 1 × 1, símbolos em relevo;
    as faces seguem `DieView.NORMALS`: +Y, -Y, +X, -X, +Z, -Z do Godot = +Z, -Z, +X, -X, -Y, +Y do
    Blender, com as marcas na ordem de `COMBAT_FACES`/`D6_FACES`). Sem o .glb, o `DieView` desenha as faces.
  - Tema por quest e móveis de papel (OpenAI): `tools/gen_board.py --themes|--paper [ids]` grava a
    arte crua em `assets/textures/raw/` (`.gdignore`); `$G --headless --path . --script
    res://tools/prep_board_textures.gd [--force]` prepara (parede repetível, normal map pelo brilho,
    recorte com borda branca de papel) e depois `--import`. Tema: `board/themes/<tema>/<parte>_albedo|normal.png`,
    escolhido por `"theme"` na quest (`ruins`, `orc_dungeon`, `barrow`); sem ele, texturas do Blender.
    `PaperFurniture` monta o móvel como cartão dobrado (tampo visto de cima, frente/costas e lados
    recortados; escada e entulho são placas finas) com `furniture/paper/<id>_<top|front|side>.png`;
    ordem de reserva no `BoardView`: papel → .glb → caixa. Alturas em `PaperFurniture.HEIGHT` (iguais
    no `gen_board.py`). Provisório como as cartas: o estilo-alvo é o do Higgsfield.
  Arte nova entra só nas views, sem tocar em `scripts/logic/`. `game.gd` traduz clique em ação do `GameState` e anima o evento
  devolvido (`_play`); nunca decide regra. Enquanto anima, `busy` trava a entrada.
- Coordenadas base 0, `Vector2i(coluna, linha)`; o quadrado (x, y) fica em
  `Vector3(x + 0.5, 0, y + 0.5)` (1 quadrado = 1 m).
- Textos e comentários em português.

## Decisões de regra (onde o livro é ambíguo)

- Reta de visão que passa exatamente numa quina: bloqueia se qualquer lado
  estiver fechado (`LineOfSight.CORNER_STRICT`).
- Heróis atravessam heróis e monstros atravessam monstros (sem parar em cima).
- Ataque diagonal (bastão etc.) exige visão entre os dois.
- Arma de projétil não ataca corpo a corpo; o herói carrega uma arma equipada por vez.
- Névoa (`GameState.update_visibility`): sala é revelada inteira quando qualquer
  quadrado dela é visto; corredor, quadrado a quadrado. Para revelar, figuras não
  tapam a visão. Monstro em quadrado revelado fica alertado e passa a agir.
- Armadilha escondida só dispara em herói (monstros passam por cima). Disparar
  encerra o turno. Fosso conhecido bloqueia o caminho de todos (pular: fase futura).
  Bloco que cai: 3 dados de dano sem defesa, o herói recua e o quadrado vira parede.
- Magia: o Mago escolhe 1 escola, o Elfo 1 das restantes e o Mago fica com as outras 2.
  Lançar gasta a ação; cada feitiço vale uma vez por quest; o alvo precisa estar à
  vista (figuras tapam a visão). Sono não pega em morto-vivo. Dormindo: não age nem
  defende, e no início de cada turno rola 1d6 por ponto de Mente (6 acorda).
  Tempestade: perde o próximo turno. Gênio: 5 dados de ataque ou abre porta à vista.
  Do Caos só estão implementados Bola de Fogo, Sono e Tempestade (Chaos Warlock
  prefere Bola de Fogo no herói mais fraco; Sono/Tempestade no que bate mais forte).
- Pular fosso conhecido (regra de 2021): 2+ de movimento, colado no fosso, mira o
  quadrado logo depois; 1 dado: escudo passa (gasta 2), caveira cai (1 de dano, fim do turno).
- Herói que morre deixa ouro e poções para um aliado na mesma sala; sem ninguém
  na sala, os monstros ficam com tudo (`GameState.after_damage` — use em todo dano).
- Caos: Tempestade de Fogo (3 em todos na área, menos o conjurador) e Nuvem do Caos
  (paralisa como o Sono) seguem a carta; Comando é simplificado (o herói perde os
  turnos até tirar 6, mas defende) e Invocar usa tabela provisória (2–4 monstros).
- Desarmar: Anão sempre consegue; com Kit, 1 dado (escudo = desarma, caveira = 1 de dano).
- Procurar exige nenhum monstro revelado na mesma sala/à vista. Tesouro: uma busca
  por herói por sala; tesouro da quest primeiro, depois o baralho. Baú com armadilha
  não achada dispara antes. Poções ficam no inventário (ação livre); Água Benta gasta
  a ação. Herói a 0 de Corpo bebe a poção de cura sozinho, se tiver.
- IA prefere o herói com menos Corpo, depois menos Defesa; monstros não abrem portas.
- Tags de monstro: `spirit_blade_only` (só fere quem tem a Lâmina Espiritual; os dados rolam,
  o dano é 0) e `spell_immune` (não é alvo de feitiço). Rei Bruxo (`witch_lord`) tem as duas
  e usa a miniatura do Bruxo do Caos (`FigureView.MODEL_ALIAS`).
- Escolta (Sir Ragnar): o prisioneiro vira aliado (`Unit.escort`) quando um herói vê o
  quadrado dele, e joga logo depois de quem o achou (no livro, esse jogador rola 1 dado por ele).
  Anda 1 dado; não ataca, não procura, não usa item e não entra na campanha; pode sair pela
  escada antes do objetivo (a recompensa vai para quem o achou). Ao achá-lo, o alarme revela
  o mapa, abre todas as portas (menos secretas e falsas) e alerta todos os monstros.
- Barak Tor: o desmoronamento da letra C é a armadilha comum de bloco que cai (o livro fecha
  a volta depois que o último herói passa).

## Testes

```bash
G=~/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --import                      # registra classes/importa
$G --headless --path . res://tests/rules_tests.tscn  # sai com código ≠ 0 se falhar
$G --headless --path . res://tests/game_smoke.tscn   # abre a partida e joga por código
$G --headless --path . res://tests/campaign_smoke.tscn  # menu → campanha → armeria → quest → save
$G --headless --path . res://tests/net_smoke.tscn    # servidor + 2 clientes: lobby, senha, assentos, sync, queda, reinício
$G --path . --write-movie /tmp/f.png res://tests/game_smoke.tscn  # o mesmo, gravando quadros
$G --path .                                          # jogar (menu inicial)
```

Servidor online local em Docker (no Mac o `docker` fica em `~/.docker/bin`). Refaça a imagem
sempre que mudar regra/quest (cliente e servidor precisam do mesmo código); as salas ficam no volume `hq-data`:

```bash
docker build -t heroquest-server .
docker rm -f heroquest-server; docker run -d --name heroquest-server -p 8765:8765 -v hq-data:/data --restart unless-stopped heroquest-server
docker logs -f heroquest-server                      # no jogo: Jogar online → ws://localhost:8765
```

Executáveis para os amigos (presets em `export_presets.cfg`; modelos de exportação do 4.7.2 instalados
em `~/Library/Application Support/Godot/export_templates/4.7.2.stable`; saída em `build/`, fora do git):

```bash
$G --headless --path . --export-release "macOS" build/mac/HeroQuest.zip        # universal, assinatura ad-hoc
$G --headless --path . --export-release "Windows" build/windows/HeroQuest.exe  # .pck embutido
```

Erro de parse num script de teste deixa o Godot parado (o nó fica sem script):
se travar, rode com timeout (`perl -e 'alarm 60; exec @ARGV' $G ...`) e leia o erro.

Teste novo de regra: crie um `_test_*() -> bool` em `tests/rules_tests.gd` que
termine com `return true` e ponha na lista do `_ready` (erro de script aborta só
a função; quem não devolve true conta como falha). Não dependa do valor de uma
rolagem (seeds mudam quando a ordem das rolagens muda). Lembre que figuras tapam
a linha de visão ao montar cenários de teste.
