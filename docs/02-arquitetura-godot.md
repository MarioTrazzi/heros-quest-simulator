# Arquitetura proposta — HeroQuest em Godot 4 (3D)

## 1. Princípios
1. **Regras separadas da apresentação.** O motor de regras é GDScript puro, com classes que não herdam de `Node3D`. A cena 3D só *observa* o estado e anima. Isso permite testar as regras sem abrir a cena, ter replays, desfazer jogadas e, mais tarde, multiplayer.
2. **Tudo é dado.** Heróis, monstros, armas, feitiços, cartas e quests vêm de `data/*.json` ou de `Resource`s `.tres`. Nada fica hardcoded.
3. **RNG semeado.** Use um único `RandomNumberGenerator` com seed por partida. Os dados 3D físicos são cosméticos: o resultado é decidido pelo RNG e a animação mostra a face sorteada. Assim os rolls são reprodutíveis e ninguém pode trapacear.
4. **Grade com paredes nas arestas.** No HeroQuest, as paredes ficam *entre* quadrados, e não ocupando um quadrado.

## 2. Modelo de dados do tabuleiro
```gdscript
# Board.gd (RefCounted)
const W := 26
const H := 19
var zone: PackedInt32Array      # W*H; 0 = corredor, 1..22 = sala
var doors := {}                 # Edge -> {open: bool, secret: bool, found: bool}
var blocked := {}               # Vector2i -> true (móveis, blocos, falling block)
var revealed := {}              # Vector2i -> true (névoa de guerra)

func has_wall(a: Vector2i, b: Vector2i) -> bool:
    # a e b são vizinhos ortogonais
    if zone_at(a) == zone_at(b): return false
    var d = doors.get(edge(a, b))
    return d == null or not d.open
```
- `edge(a,b)` = par ordenado (min, max) usado como chave.
- **Pathfinding:** `AStarGrid2D` não sabe lidar com paredes em arestas. Use um **BFS próprio**, que já basta porque o movimento máximo é 12 e a grade tem 494 células. O BFS também gera a lista de quadrados alcançáveis para destacar na UI. Com o BFS, a regra de atravessar heróis aliados sem parar sobre eles fica fácil de implementar.
- **Linha de visão:** percorra as células com uma *supercover line* (DDA de Amanatides & Woo) do centro de A ao centro de B. A visão é bloqueada por: aresta com parede ou porta fechada entre células consecutivas, ou célula intermediária ocupada por uma figura. Exceção: na mesma sala a visão é sempre livre. ⚠️ Quando a linha passa exatamente por um canto, defina uma regra fixa (por exemplo, bloqueia se *qualquer um* dos dois lados bloquear).

## 3. Estado e fluxo de turno
```
GameState
 ├─ board: Board
 ├─ heroes: Array[Hero]      (stats, inventário, feitiços, ouro, posição)
 ├─ monsters: Array[Monster]
 ├─ treasure_deck: Array[Card]
 ├─ quest: QuestDef          (zonas, spawns ocultos, gatilhos, objetivo)
 └─ turn: TurnState          (atual, fase, movimento restante, ação usada)
```
**Máquina de estados do turno do herói:**
`START → (ROLL_MOVE) → MOVING ⇄ ACTION → END`, com a flag `moved_after_action` para impedir mover, agir e mover de novo.

**Comandos**, no padrão Command: `MoveCmd`, `AttackCmd`, `CastCmd`, `SearchTreasureCmd`, `SearchTrapsCmd`, `DisarmCmd`, `OpenDoorCmd`, `UsePotionCmd`, `EndTurnCmd`. Cada comando:
1. tem `validate(state) -> bool` para a UI saber o que está habilitado;
2. tem `execute(state) -> Array[Event]`, que muda o estado e emite **eventos** como `DiceRolled`, `Damaged`, `Revealed`, `TrapSprung`, `Died`, `CardDrawn`;
3. passa os eventos para o `Presenter3D`, que os anima **em fila** com `await`.

Esse desenho dá de graça log de partida, replay, undo nas fases de debug e uma base para rede no futuro.

## 4. IA do Mestre (Zargon)
Para cada monstro **revelado**, em ordem de distância até o herói mais próximo:
1. Se tem feitiço e um bom alvo, conjura.
2. Se está adjacente a um herói, ataca primeiro o de menos Corpo e depois se reposiciona se fizer sentido.
3. Se não está, faz BFS até o quadrado adjacente a um herói mais próximo, dentro do seu valor de Movimento, e ataca se chegar.
4. Monstros nunca abrem portas. Os não revelados ficam parados até a sala ser vista.

Vale incluir níveis de dificuldade: na IA "burra", cada monstro só persegue; na "tática", eles cercam, focam no Mago e bloqueiam portas.

## 5. Quests: formato e importação
O formato próprio da quest é um JSON por quest:
```json
{
  "id": "q01_the_trial", "name": "The Trial",
  "start": [[1,13]], "exit": "stairway",
  "objective": {"type": "kill", "target": "verag"},
  "objects": [
    {"type": "door", "a": [4,2], "b": [4,3]},
    {"type": "monster", "id": "orc", "pos": [5,6]},
    {"type": "monster", "id": "gargoyle", "pos": [12,8], "override": {"body": 3, "name": "Verag"}},
    {"type": "furniture", "id": "table", "pos": [7,6], "rot": 0},
    {"type": "trap", "id": "pit", "pos": [10,1], "hidden": true},
    {"type": "secret_door", "a": [9,4], "b": [10,4]},
    {"type": "treasure", "zone": 5, "items": [{"gold": 84}]}
  ],
  "blocked_zones": [3, 7],
  "wandering_monster": "orc",
  "notes": {"A": "Texto do livro..."}
}
```
**Importador HeroScribe:** a comunidade tem centenas de quests (oficiais e de fãs) em **HeroScribe XML**; há um exemplo em `referencias/heroscribe/`. O formato é:
- `<object id="Orc" left="5.0" top="6.0" rotation="downward"/>`, com coordenadas **base 1**. Subtraia 1.
- Uma `Door` ocupa 1×2 *atravessando* a parede: `rotation` diz de que lado fica a parede.
- `<dark .../>` marca quadrados inexistentes na quest, ou seja, área preta e bloqueada.
- Letras (`LetterA`…) são marcadores de notas do livro.

Escreva `tools/import_heroscribe.gd`, um `EditorScript`, para converter XML em JSON. ⚠️ Valide a convenção de rotação das portas comparando com a imagem renderizada do HeroScribe.

## 6. Cena 3D
```
Main (Node)
 ├─ GameController           (dono do GameState, recebe input → comandos)
 ├─ World (Node3D)
 │   ├─ BoardView            (piso 26×19, 1 célula = 1 m; paredes geradas a partir de zone[])
 │   ├─ DoorViews / FurnitureViews / TrapViews
 │   ├─ FigureViews          (miniaturas, AnimationPlayer: idle/walk/attack/hit/die)
 │   ├─ FogOfWar             (salas não reveladas: escuras + paredes baixadas)
 │   ├─ Highlights           (MultiMesh: alcance de movimento, alvos válidos)
 │   └─ DiceTray             (RigidBody3D dos dados; face final é forçada pelo resultado)
 ├─ CameraRig                (órbita isométrica, zoom, foco no ator do turno)
 └─ UI (CanvasLayer)         (ficha do herói, cartas, log, botões de ação, armeria)
```
- **Geração de paredes:** percorra todas as arestas e, onde `zone` muda, instancie um segmento de parede. Use `MultiMeshInstance3D` ou `GridMap` com um tile de parede alinhado à aresta. As portas substituem segmentos.
- **Névoa de guerra:** quando uma sala é revelada, o tween sobe a parede e clareia o piso. Os monstros fazem *spawn* com animação.
- **Visual do tabuleiro:** dá para seguir o visual de "jogo de tabuleiro" (piso pintado, minis de plástico, paredes de papelão) ou de "dungeon real" (paredes altas com câmera que esconde as da frente, como em *Descent*/*HeroQuest Legacy*). O estilo tabuleiro é mais barato e reforça a nostalgia.
- **Dados:** os de movimento são d6 comuns. Os de combate são d6 com textura de 3 caveiras, 2 escudos brancos e 1 escudo preto. Para mostrar o resultado sorteado, rode o mesh para que a face certa termine para cima. A técnica comum é simular, ver qual face caiu e trocar os UVs.

## 7. Roteiro sugerido (MVP primeiro)
| Fase | Entrega |
|---|---|
| **0. Protótipo de regras** | `GameState`, Board, BFS, LOS, combate e testes com GUT, sem 3D |
| **1. Tabuleiro 3D** | Piso, paredes geradas, portas, câmera, clicar para mover 1 herói |
| **2. Combate** | Monstros, IA simples, dados 3D, morte |
| **3. Exploração** | Névoa de guerra, procurar, armadilhas, baralho de tesouro, monstro errante |
| **4. Magia** | Escolha das escolas, 12 feitiços, alvos com LOS |
| **5. Quest 1 completa** | "The Trial" jogável do início ao fim, com escada e vitória/derrota |
| **6. Campanha** | Armeria, ouro, save/load, as 14 quests (importador HeroScribe) |
| **7. Polimento** | Animações, áudio, 4 heróis locais (hot-seat), Feitiços do Caos, dificuldade |
| **8+. Extras** | Online, expansões, editor de quests |

## 8. Ferramentas e assets
- **Godot 4.7.2** (instalado em `~/Applications/Godot.app`, mesma versão do projeto `dolrath-godot`)
- **GUT** (Godot Unit Test) para testar as regras
- Modelos low-poly CC0: **KayKit Dungeon Remastered**, **KayKit Adventurers** e **Skeletons** (Kay Lousberg), **Quaternius**. Eles combinam muito com o estilo HeroQuest.
- Texturas: **ambientCG** e **Poly Haven** (CC0)

## 9. Aviso legal ⚠️
"HeroQuest" é marca registrada da **Hasbro**. Fimir, Chaos Warrior e o mundo de *Warhammer* são da **Games Workshop**. Arte, textos de cartas e mapas das quests oficiais têm direitos autorais. As regras em si (mecânicas) não são protegidas por copyright.
- Para **uso pessoal ou estudo**, não há problema prático.
- Para **publicar ou distribuir**, use nome próprio, arte original, textos reescritos e quests originais, e deixe o importador HeroScribe como recurso para o usuário carregar os próprios arquivos.
