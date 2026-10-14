# HeroQuest — Referência de Regras e Dados

Referência compilada para recriar o HeroQuest em Godot 3D. A base é a **edição europeia de 1989 (Milton Bradley + Games Workshop)**, com notas sobre a edição norte-americana (1990) e o remake da **Hasbro/Avalon Hill (2021)**.

Legenda de confiança:
- ✅ confirmado em mais de uma fonte
- ⚠️ valor varia entre edições ou só foi encontrado em uma fonte. Confira com o livro de regras físico antes de fixar.

Os dados prontos para o código estão em [`/data`](../data).

---

## 1. Visão geral

| Item | Valor |
|---|---|
| Jogadores | 2–5 (1 Mestre "Morcar"/"Zargon" + até 4 heróis). O remake aceita 1–5 com app |
| Tabuleiro | Grade de **26 × 19** quadrados ✅ |
| Dados de movimento | 2 × d6 comuns (vermelhos) ✅ |
| Dados de combate | d6 especiais: **3 caveiras, 2 escudos brancos (herói), 1 escudo preto (monstro)** ✅ |
| Quests no livro base | 14 ✅ |
| Miniaturas (UE 1989) | 35: 4 heróis, 8 Orcs, 6 Goblins, 3 Fimir, 4 Chaos Warriors, 1 Chaos Warlock, 1 Gargoyle, 4 Esqueletos, 2 Zumbis, 2 Múmias ✅ |
| Portas | 21 ✅ |
| Móveis | 15 peças ✅ |

**Nomes no remake de 2021:** Morcar → Zargon, Fimir → *Abomination*, Chaos → *Dread* (Chaos Warrior → Dread Warrior, Chaos Warlock → Dread Sorcerer, Chaos Spells → Dread Spells). Os stats continuam os mesmos.

---

## 2. Preparação

1. Um jogador é o Mestre (Morcar/Zargon). Ele controla monstros, armadilhas e o livro de quests.
2. Cada herói recebe a ficha com Ataque, Defesa, Corpo e Mente.
3. **Escolha de magias:** os 12 feitiços dos heróis se dividem em 4 escolas (Ar, Fogo, Água, Terra), com 3 feitiços em cada. O **Mago escolhe 1 escola**, o **Elfo escolhe 1**, e o Mago fica com as **2 restantes**. No fim, o Mago tem 9 feitiços e o Elfo tem 3.
4. O baralho de tesouro é embaralhado e fica com a face para baixo.
5. Monta-se a quest. No início só a escada (ou o ponto de entrada) e o que estiver visível dali ficam no tabuleiro.

---

## 3. Ordem de turno ✅

1. Os heróis jogam um de cada vez, começando à esquerda do Mestre e seguindo no sentido horário. **No digital, use ordem fixa: Bárbaro → Anão → Elfo → Mago.**
2. Depois que todos os heróis jogam, o Mestre move e age com **cada** monstro.
3. Repete.

### Turno do herói
**Mover e depois agir** ou **agir e depois mover**. Não é permitido mover, agir e mover de novo.

Ações (apenas 1 por turno):
1. **Atacar** um alvo adjacente ortogonal, ou à distância com arma de projétil
2. **Lançar feitiço** (só Mago e Elfo)
3. **Procurar tesouro**
4. **Procurar armadilhas e portas secretas**
5. **Desarmar armadilha**, com Kit de Ferramentas ou se for o Anão

Ações livres, que não gastam a ação do turno:
- **Abrir porta**: basta estar no quadrado em frente a ela. Não gasta movimento. A porta fica aberta pelo resto da quest.
- **Beber poção**: pode ser feito a qualquer momento, inclusive ao chegar a 0 de Corpo, para evitar a morte.

### Turno do monstro
Cada monstro move até seu valor fixo de Movimento (sem rolar dados) e faz 1 ação: **atacar** ou **lançar feitiço do Caos/Dread** (só monstros especiais). Pode mover antes ou depois de agir. Monstros **não abrem portas, não procuram, não ativam armadilhas** e não se movem em diagonal.

---

## 4. Movimento ✅
- O herói rola **2d6** (com Armadura de Placas, só **1d6**) e move **até** esse número de quadrados. Não precisa usar tudo.
- **Sem diagonais.** Não pode passar duas vezes pelo mesmo quadrado na mesma jogada.
- Não pode atravessar paredes, monstros ou quadrados bloqueados e móveis.
- Pode atravessar o quadrado de outro herói **se ele permitir**, mas não pode parar ali.
- Só se entra ou sai de salas por **portas abertas** (ou portas secretas já descobertas).
- **Armadilha ativada** encerra o movimento na hora. O herói não faz mais nada até o próximo turno.

---

## 5. Combate ✅
- **Corpo a corpo:** o alvo precisa estar em um dos **4 quadrados ortogonais** (frente, trás ou lados). Algumas armas permitem atacar na **diagonal**: Bastão, Lança, Espada Longa (2021) e Cajado do Mago.
- O atacante rola N dados de combate (o valor de Ataque). Cada **caveira** é 1 acerto.
- O defensor rola M dados (o valor de Defesa):
  - herói: cada **escudo branco** bloqueia 1 acerto (chance de 2/6)
  - monstro: cada **escudo preto** bloqueia 1 acerto (chance de 1/6)
- Dano = acertos − bloqueios (mínimo 0). Cada ponto tira 1 de **Corpo**.
- **Arma de projétil (Besta):** o alvo precisa estar **visível**, sem limite de alcance, mas **não pode** estar adjacente.
- **Armas arremessáveis** (Machadinha, Lança, Adaga): o ataque é à distância e a arma se perde depois do arremesso.
- Com **0 de Corpo**, a figura morre e sai do tabuleiro. Um herói pode beber poção de cura ou receber cura antes do fim do turno para se salvar.
- **Herói morto:** outros heróis **na mesma sala** podem recolher os itens dele. Senão, os monstros ficam com tudo e os itens saem do jogo.

Probabilidades úteis para o balanceamento:
- P(caveira) = 1/2
- P(escudo branco) = 1/3
- P(escudo preto) = 1/6

---

## 6. Linha de visão ✅
- Figuras na **mesma sala** sempre se veem.
- Fora disso, só há visão se uma **linha reta** entre o centro dos dois quadrados não passar por parede, porta fechada **ou outra figura**.
- Feitiços exigem que o alvo esteja visível. Um feitiço lançado sobre alvo que não está visível é desperdiçado. O conjurador sempre pode lançar em si mesmo.
- **Revelação (névoa de guerra):** ao abrir uma porta ou olhar por um corredor, o Mestre coloca no tabuleiro os monstros, móveis, portas e blocos que ficaram visíveis. Armadilhas e portas secretas **não** aparecem nesse momento.

---

## 7. Procurar ✅
- Só pode procurar se **não houver monstro visível**, ou seja, nenhum monstro na mesma sala ou à vista no corredor.
- Procurar cobre a **sala inteira** ou **todos os quadrados visíveis do corredor**.
- **Armadilhas e portas secretas:** revela todas na área. Isso inclui baús com armadilha.
- **Tesouro:** só em salas. Cada herói procura tesouro **uma vez por sala por quest**. Se a quest define um tesouro para a sala, ele é entregue. Se não define, o herói compra uma carta do baralho de tesouro. Gold e joias vão para a ficha, poções vão para o inventário, e cartas de armadilha ou monstro errante são resolvidas na hora. Depois de resolvida, a carta volta para o **fundo** do baralho.
- Procurar tesouro não revela armadilhas, e procurar armadilhas não revela tesouro.
- **Porta secreta:** pode ser encontrada procurando de qualquer um dos lados da parede. Depois de encontrada, fica aberta.

### Monstro errante (carta de tesouro)
O monstro errante indicado na quest aparece **adjacente** ao herói que procurou e **ataca imediatamente**. Se não houver espaço adjacente, ele aparece em qualquer quadrado livre da mesma sala ou corredor. Se todas as miniaturas daquele tipo já estiverem em jogo, usa-se outro monstro da mesma cor. Nos turnos seguintes, ele age normalmente.

---

## 8. Armadilhas ✅

| Tipo | Ao ser ativada | Depois |
|---|---|---|
| **Fosso (Pit)** | 1 de dano em Corpo; o herói cai no fosso | O fosso fica no tabuleiro. Dentro dele, o herói rola **1 dado a menos** em ataque e defesa ⚠️. Pode ser **pulado** ou **desarmado** |
| **Lança (Spear)** | Rola 1 dado de combate: **caveira = 1 de dano**, escudo = escapou | É removida. O quadrado fica seguro |
| **Bloco que cai (Falling Block)** | Rola **3 dados de combate**, cada caveira é 1 de dano, **sem defesa** | Vira **parede permanente** no quadrado (quadrado bloqueado). Não pode ser pulada nem desarmada |
| **Baú ou móvel com armadilha** | Efeito definido pela quest (gás, veneno, dardo) | Pode ser desarmada antes de procurar |

- **Encontrar armadilha** com uma busca: spear é desarmada automaticamente. Pit e falling block são colocados no tabuleiro como marcadores visíveis.
- **Desarmar** (Anão ou Kit de Ferramentas, herói adjacente): o Anão desarma automaticamente ⚠️. Com o Kit, rola 1 dado de combate: **escudo = sucesso, caveira = ativa a armadilha** (2021).
- **Pular armadilha conhecida** (2021): precisa de **2 ou mais** pontos de movimento restantes. Rola 1 dado de combate: escudo = passa (gasta 2 de movimento), caveira = ativa.

---

## 9. Fim da quest e campanha ✅
- A quest termina quando todos os heróis saem pela **escada** (ou pela saída indicada) ou morrem.
- Sucesso exige **cumprir o objetivo e voltar à escada**.
- Entre quests: Corpo e Mente são restaurados por completo e os feitiços voltam.
- O herói **mantém** o ouro, os itens de Quest/Artefatos e as poções não usadas ⚠️. As cartas comuns de tesouro voltam ao baralho.
- **Armeria:** entre quests, o ouro serve para comprar equipamento.
- Depois de completar **3 quests**, o herói vira **Campeão** e recebe **500 de ouro** (regra da UE 1989).
- **Herói morto** morre de vez. O jogador começa um herói novo com o equipamento inicial.

---

## 10. Heróis ✅

| Herói | Ataque | Defesa | Corpo | Mente | Movimento | Equip. inicial | Especial |
|---|---|---|---|---|---|---|---|
| **Bárbaro** | 3 | 2 | **8** | 2 | 2d6 | Espada Larga (Broadsword) | Mais forte, sem magia |
| **Anão** | 2 | 2 | **7** | 3 | 2d6 | Espada Curta | Desarma armadilhas sem kit |
| **Elfo** | 2 | 2 | **6** | 4 | 2d6 | Espada Curta | 1 escola de magia (3 feitiços) |
| **Mago** | 1 | 2 | **4** | 6 | 2d6 | Adaga | 3 escolas (9 feitiços). Não usa armadura pesada nem armas grandes |

**Restrições do Mago:** não pode usar Espada Curta, Espada Larga, Machado de Batalha, Besta, Machadinha, Lança, Escudo, Elmo, Cota de Malha nem Armadura de Placas. Pode usar Adaga, Bastão, Manto de Proteção, Braceletes ⚠️ e Kit de Ferramentas.

**Heróis extras de expansões de 2021+:** Knight, Rogue Heir (Rogue), Monk, Berserker, Druid, Warlock, Bard, entre outros. Bons candidatos para DLC/v2.

---

## 11. Monstros ✅

| Monstro (UE 1989) | Nome 2021 | Mov | Ataque | Defesa | Corpo | Mente |
|---|---|---|---|---|---|---|
| Goblin | Goblin | 10 | 2 | 1 | 1 | 1 |
| Orc | Orc | 8 | 3 | 2 | 1 | 2 |
| Fimir | Abomination | 6 | 3 | 3 | 2 | 3 |
| Chaos Warrior | Dread Warrior | 7 | 4 ⚠️ (3 em algumas tabelas UE) | 4 | 3 | 3 |
| Gargoyle | Gargoyle | 6 | 4 | 5 | 3 | 4 |
| Skeleton | Skeleton | 6 | 2 | 2 | 1 | 0 |
| Zombie | Zombie | 5 | 2 | 3 | 1 | 0 |
| Mummy | Mummy | 4 | 3 | 4 | 2 | 0 |
| Chaos Warlock | Dread Sorcerer | 8 ⚠️ | 2 ⚠️ | 3 ⚠️ | ⚠️ (por quest) | ⚠️ |

- **Mortos-vivos** (Esqueleto, Zumbi, Múmia): têm Mente 0, são afetados por Água Benta e pela Spirit Blade.
- **Chefes nomeados** (Ulag, Gulthor, Sir Ragnar, Witch Lord, Karlen…) usam o modelo de um monstro comum com stats próprios definidos na quest. Por isso, no código, a quest deve poder **sobrescrever stats** de um monstro.
- **Expansões:** Ogros (*Against the Ogre Horde*: Ogre Warrior, Champion, Chieftain, Lord), Ice Gremlin, Yeti, Polar Warbear, Frozen Horror (*Frozen Horror*), Elven Archer/Warrior, Giant Wolf (*Mage of the Mirror*), Mercenários (*Wizards of Morcar*).

---

## 12. Feitiços dos heróis ✅ (cada um pode ser usado 1 vez por quest)

### Ar
| Feitiço | Efeito |
|---|---|
| **Genie** | Abre qualquer porta e revela o que há atrás dela **ou** ataca um monstro visível com **5 dados de combate** |
| **Swift Wind** | Um herói rola o **dobro de dados** no próximo movimento |
| **Tempest** | Um monstro **perde o próximo turno** |

### Fogo
| Feitiço | Efeito |
|---|---|
| **Fire of Wrath** | 1 de dano em Corpo de um monstro, exceto se ele tirar 5 ou 6 em 1d6 |
| **Courage** | Um herói rola **+2 dados de ataque** no próximo ataque ⚠️ (UE: enquanto houver monstro visível) |
| **Ball of Flame** | 2 de dano em Corpo. O monstro rola 2d6, e cada 5 ou 6 reduz 1 de dano |

### Água
| Feitiço | Efeito |
|---|---|
| **Water of Healing** | Restaura até **4 de Corpo**, sem passar do máximo |
| **Sleep** | Um monstro não move, não ataca e não defende. A cada turno, ele rola 1d6 por ponto de Mente e **um 6 quebra** o feitiço (monstros com Mente 0 nunca acordam) |
| **Veil of Mist** | Um herói pode atravessar quadrados ocupados por monstros no próximo movimento ⚠️ |

### Terra
| Feitiço | Efeito |
|---|---|
| **Heal Body** | Restaura até **4 de Corpo** |
| **Pass Through Rock** | Um herói atravessa **paredes** no próximo movimento |
| **Rock Skin** | **+1 dado de defesa** até o herói sofrer 1 de dano |

### Feitiços do Caos/Dread (só para o Mestre e monstros conjuradores)
A lista UE tem 11 cartas: Ball of Flame, Cloud of Chaos, Command, Firestorm, Rust, Sleep, Summon Greenskins (Summon Orcs), Summon Undead, Tempest, Terror, Thunderbolt. A versão US tem 12, incluindo Escape, Fear, Lightning Bolt e Rest.

| Feitiço | Efeito |
|---|---|
| Ball of Flame | 2 de dano. O herói rola 2d6, e cada 5 ou 6 reduz 1 |
| Sleep / Tempest | Iguais às versões dos heróis, com alvo em um herói (Sleep usa a Mente do herói para quebrar) |
| Command | O herói passa a ser controlado pelo Mestre. Ele rola 1d6 por ponto de Mente a cada turno, e um 6 quebra o efeito |
| Cloud of Chaos | Paralisa todos os heróis na mesma sala ou corredor: não movem, não atacam, não defendem ⚠️ |
| Firestorm | 3 de dano em todos na sala do conjurador (exceto ele) ⚠️ |
| Summon Orcs/Undead | Invoca monstros adjacentes ao conjurador ⚠️ (quantidade por 1d6) |
| Rust, Terror, Thunderbolt, Escape, Fear, Lightning Bolt, Rest | ⚠️ efeitos ainda não confirmados. Consulte o cartão original |

---

## 13. Armeria (equipamento) — UE 1989 ⚠️ preços variam por edição

| Item | Preço (ouro) | Efeito | Mago? |
|---|---|---|---|
| Adaga (Dagger) | 25 (2021) | Ataque 1. Pode ser arremessada (perde-se) | ✅ |
| Bastão (Staff) | 100 | Ataque 1, **ataca na diagonal**, duas mãos | ✅ |
| Espada Curta (Shortsword) | 150 | Ataque 2 | ❌ |
| Machadinha (Hand Axe) | 150 | Ataque 2. Pode ser arremessada (perde-se) | ❌ |
| Lança (Spear) | 150 | Ataque 2, diagonal, pode ser arremessada | ❌ |
| Espada Larga (Broadsword) | 250 | Ataque 3 | ❌ |
| Besta (Crossbow) | 350 | Ataque 3 à distância, não pode alvo adjacente, munição infinita | ❌ |
| Machado de Batalha (Battle Axe) | 400 | Ataque 4, duas mãos (sem escudo) | ❌ |
| Escudo (Shield) | 100 | +1 defesa. Não combina com arma de duas mãos | ❌ |
| Elmo (Helmet) | 120 | +1 defesa | ❌ |
| Braceletes (Bracers) | 220 ⚠️ | +1 defesa | ✅ ⚠️ |
| Manto de Proteção (Cloak of Protection) | 350 | +1 defesa | só o Mago |
| Cota de Malha (Chain Mail) | 450 | +1 defesa | ❌ |
| Armadura de Placas (Plate Armour) | 850 | +2 defesa, movimento só **1d6** | ❌ |
| Kit de Ferramentas (Tool Kit) | 250 | Permite desarmar armadilhas | ✅ |

**Regras de acumulação:** o herói usa **1 arma** por vez e o Ataque é o valor dessa arma (substitui o base). Itens de defesa **somam** ao valor base de 2, com uma armadura de corpo + elmo + escudo + braceletes. O remake de 2021 acrescenta Espada Longa (3, diagonal) e outros itens.

---

## 14. Baralho de tesouro — UE 1989 (24 cartas) ✅

| Carta | Qtd | Efeito |
|---|---|---|
| Ouro (vários valores) | 5 | ⚠️ valores sugeridos: 10, 20, 25, 50 e 1d6×10 |
| Gema (Gem) | 1 | 35 ⚠️ de ouro |
| Joias (Jewels) | 1 | 50 ⚠️ de ouro |
| Tesouro (Treasure Horde) | 1 | 100 ⚠️ de ouro |
| Poção de Cura | 2 | Restaura 1d6 de Corpo (2021) ou até 4 (UE) ⚠️ |
| Poção de Força (Strength) | 1 | +2 dados no próximo ataque |
| Poção de Resiliência (Resilience) | 1 | +2 dados na próxima defesa |
| Poção de Velocidade (Speed) | 1 | Dobra os dados do próximo movimento |
| Heroic Brew | 1 | 2 ataques no próximo turno |
| Água Benta (Holy Water) | 1 | Em vez de atacar, **destrói** um morto-vivo adjacente |
| Armadilha: flecha escondida | 2 | 1 de dano |
| Armadilha: fosso | 1 | 1 de dano e o herói fica no fosso |
| Monstro Errante | 5 | Veja §7 |
| Nada | 1 | — |

O baralho US tem 24 cartas, com 10 negativas. No código, trate o baralho como **dado configurável**, como em `data/treasure_deck.json`.

---

## 15. Artefatos / tesouros de quest ✅

| Artefato | Efeito |
|---|---|
| **Borin's Armour** | Defesa 4 sem penalidade de movimento. Não serve para o Mago |
| **Spirit Blade** | Ataque 3, ou 4 contra mortos-vivos. Não serve para o Mago |
| **Orc's Bane** | Ataque 2 e **ataca duas vezes** contra Orcs. Não serve para o Mago |
| **Talisman of Lore** | +1 de Mente |
| **Wand of Magic** (Wand of Recall) | Lança 2 feitiços diferentes no mesmo turno (Mago/Elfo) |
| **Wizard's Cloak** | +1 de defesa, só para o Mago |
| **Wizard's Staff** | Ataque 2, diagonal, só para o Mago |
| **Ring of Return** | 1 uso. Leva todos os heróis visíveis de volta à escada |
| **Elixir of Life** | 1 uso. Ressuscita um herói morto com Corpo e Mente cheios |
| **Spell Ring** | Repete 1 feitiço escolhido no início da quest |

---

## 16. As 14 quests do livro base (UE) ✅
1. The Trial (A Prova)
2. The Rescue of Sir Ragnar
3. Lair of the Orc Warlord
4. Prince Magnus' Gold
5. Melar's Maze
6. Legacy of the Orc Warlord
7. The Lost Wizard (US: The Stone Hunter)
8. The Fire Mage
9. Race Against Time
10. Castle of Mystery
11. Bastion of Chaos
12. Barak Tor – Barrow of the Witch Lord
13. Quest for the Spirit Blade
14. Return to Barak Tor

**Expansões clássicas** (com quests e regras novas): *Kellar's Keep* (10 quests), *Return of the Witch Lord* (10 quests), *Against the Ogre Horde*, *Wizards of Morcar*, *Adventure Design Kit*.

**Expansões 2021+:** *The Frozen Horror*, *Mage of the Mirror*, *Rise of the Dread Moon*, *Prophecy of Telor*, *Spirit Queen's Torment*, *Jungles of Delthrak*, *First Light* (2025), além de packs de heróis.

> Os mapas de cada quest (posição exata de monstros, portas, armadilhas e móveis) são conteúdo protegido do livro de quests. Para obtê-los, use seu livro físico ou os arquivos de fãs no formato **HeroScribe XML** (ver `docs/02-arquitetura-godot.md` §5). Há um exemplo em `referencias/heroscribe/`.

---

## 17. Tabuleiro: planta exata

A grade tem **26 colunas × 19 linhas**. As coordenadas são **base 0** (x = coluna, y = linha). `.` = corredor, letras = salas (22 no total).

```
   01234567890123456789012345
 0 ..........................
 1 .AAAABBBBCCC..FFFGGGGHHHH.
 2 .AAAABBBBCCC..FFFGGGGHHHH.
 3 .AAAABBBBCCC..FFFGGGGHHHH.
 4 .DDDDEEEECCC..FFFGGGGHHHH.
 5 .DDDDEEEECCC..FFFIIIIJJJJ.
 6 .DDDDEEEE........IIIIJJJJ.
 7 .DDDDEEEE.KKKKKK.IIIIJJJJ.
 8 .DDDDEEEE.KKKKKK.IIIIJJJJ.
 9 ..........KKKKKK..........
10 .LLLLMMNN.KKKKKK.RRRRTTTT.
11 .LLLLMMNN.KKKKKK.RRRRTTTT.
12 .LLLLMMNN........RRRRTTTT.
13 .LLLLPPPPQQQ..SSSSRRRTTTT.
14 .OOOOPPPPQQQ..SSSSUUUVVVV.
15 .OOOOPPPPQQQ..SSSSUUUVVVV.
16 .OOOOPPPPQQQ..SSSSUUUVVVV.
17 .OOOOPPPPQQQ..SSSSUUUVVVV.
18 ..........................
```

- **K** é a sala central de 6×5. Em várias quests ela é a sala da escada ou do chefe.
- **S** tem formato de L: ela ocupa o quadrado (17,13).
- **Regra de paredes:** entre dois quadrados vizinhos há parede **se e somente se** eles pertencem a zonas diferentes (sala ≠ sala ou sala ≠ corredor). Corredor com corredor não tem parede. **Portas** abrem passagem em uma dessas arestas.
- Fontes: os corredores vêm do `Objects.xml` do HeroScribe; as salas vêm da implementação open source em C++ [hghero/HeroQuest](https://github.com/hghero/HeroQuest), extraída da imagem do tabuleiro. ⚠️ Valide visualmente contra uma foto do tabuleiro antes de modelar em 3D.

### Móveis (tamanho em quadrados, do HeroScribe) ✅
| Móvel | L×A | Móvel | L×A |
|---|---|---|---|
| Escada (Stairway) | 2×2 (andável) | Mesa (Table) | 3×2 |
| Mesa do Feiticeiro | 3×2 | Bancada do Alquimista | 3×2 |
| Túmulo (Tomb) | 2×3 | Rack de Tortura (Rack) | 2×3 |
| Estante (Bookcase) | 3×1 | Armário (Cupboard) | 3×1 |
| Lareira (Fireplace) | 3×1 | Rack de Armas | 3×1 |
| Trono (Throne) | 1×1 | Baú (Treasure Chest) | 1×1 |
| Bloco simples | 1×1 | Bloco duplo | 2×1 |

Todos os móveis, exceto a escada, **bloqueiam** movimento. ⚠️ Em geral **não bloqueiam linha de visão**; confirme isso por quest.

---

## Fontes
- [Wikipedia — HeroQuest](https://en.wikipedia.org/wiki/HeroQuest)
- [RulesPal — HeroQuest rulebook (2021)](https://rulespal.com/heroquest/rulebook)
- Universal Head / Headless Hollow — *HeroQuest Rules Summary v1* (UE 1989), via [orderofgamers.com](https://www.orderofgamers.com/downloads/Heroquest_v1.pdf)
- [Ye Olde Inn — Game System (componentes UE)](https://english.yeoldeinn.com/system.php)
- [Elvyler — HeroQuest Field Guide](https://elvyler.com/heroquest/game-system)
- [people.wku.edu — tabelas de stats e artefatos](https://people.wku.edu/charles.plemons/heroquest.html)
- [HeroScribe Basic Game page (lista de quests)](https://www.heroscribe.org/baloban/MainGame.htm)
- [HeroScribe (GitHub, adelolmo)](https://github.com/adelolmo/heroscribe), [Heroscribe2](https://github.com/Anderas2/Heroscribe2)
- [hghero/HeroQuest — implementação C++ open source](https://github.com/hghero/HeroQuest)
