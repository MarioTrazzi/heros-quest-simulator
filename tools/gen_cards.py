#!/usr/bin/env python3
"""Gera a arte das cartas (GameCard: tesouro, feitiços, Caos, equipamento,
artefatos e monstros) pela API de imagens da OpenAI.

    python3 tools/gen_cards.py                    # todas as que faltam
    python3 tools/gen_cards.py potion_healing gem # só as pedidas
    python3 tools/gen_cards.py --force gold       # refaz uma que já existe

Salva em assets/textures/cards/<id>.png (3:4, 600 px de altura). O id é o da
carta/feitiço/item/monstro em data/*.json; cartas parecidas usam a mesma arte
(GameCard.ART_ALIAS no Godot).

Com --ink, gera as ilustrações a nanquim das cartas brancas (tesouro, feitiço,
equipamento, artefato) em assets/textures/cards/ink/<id>.png, deitadas (3:2),
no traço das cartas europeias de 1989: bico de pena preto e branco com hachura,
cenas inspiradas no que cada carta original mostra (sem copiar a arte). As
pinturas coloridas continuam nos versos e nas cartas de monstro.

    python3 tools/gen_cards.py --ink              # todas as de nanquim que faltam

Provisório: a OpenAI não ficou no estilo do Bárbaro e do Mago. O alvo é refazer
no Higgsfield com a mesma configuração deles: generate_image, modelo
nano_banana_2, aspect_ratio 3:4, resolution 1k, com STYLE % descrição abaixo.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_portraits  # noqa: E402  (mesma chave e chamada da API)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "cards", "%s.png")
OUT_INK = os.path.join(ROOT, "assets", "textures", "cards", "ink", "%s.png")

INK_STYLE = ("Black and white pen and ink illustration in the style of late-1980s fantasy board game card art: "
             "fine crisp ink lines, dense cross-hatching for shadows, stippling, pure white paper, no color, "
             "no gray wash, detailed and expressive like a classic fantasy book engraving. Wide landscape scene: %s. "
             "No text, no border, no frame, no logo.")

# Cena de cada carta branca (o que a carta original mostra, com outro desenho).
INK_CARDS = {
    "gold": "an adventurer's gloved hand lifting a heavy leather purse spilling gold coins in a dungeon room",
    "gem": "a hero holding up a large faceted gemstone to the light of a candle, eyes wide in wonder",
    "jewels": "a pile of rings, necklaces and jewels spilling from a small broken casket on a stone floor",
    "treasure_horde": "an open treasure chest overflowing with coins, goblets and jewels in a vaulted dungeon",
    "potion_healing": "an adventurer drinking from a small round potion flask, wounds closing, a bandage on his arm",
    "potion_strength": "a muscular warrior drinking a potion and flexing, bending an iron bar with his hands",
    "potion_resilience": "a warrior drinking a potion while arrows bounce harmlessly off his chest",
    "potion_speed": "a hero drinking a potion and running at great speed down a dungeon corridor, motion lines",
    "heroic_brew": "a dwarf drinking deeply from a foaming tankard, a battle axe on the table beside him",
    "holy_water": "a small glass vial of holy water with a cross stopper, held up as a skeleton recoils in fear",
    "trap_arrow": "an arrow shooting from a hidden slot in a dungeon wall towards a startled adventurer",
    "trap_pit": "an adventurer falling into a pit trap as the stone floor gives way beneath him",
    "wandering_monster": "an orc warrior with a scimitar leaping out of the darkness at a surprised adventurer",
    "nothing": "a disappointed dwarf adventurer shrugging with empty open hands, a quiver of arrows on his back",
    "chest": "a closed iron-bound wooden treasure chest with a heavy lock, cobwebs, in a dungeon room",
    "genie": "a towering genie of swirling smoke rising from a brass lamp, arms crossed",
    "swift_wind": "a hero running carried by a magical gust of wind, cloak and hair streaming",
    "tempest": "a small furious storm cloud with lightning and rain whirling over a cowering goblin",
    "fire_of_wrath": "a wizard's outstretched hand hurling a jet of flame at an orc",
    "courage": "a hero raising a sword high, surrounded by a halo of fiery light, determined face",
    "ball_of_flame": "a great ball of fire hurtling down a corridor towards a chaos warrior",
    "water_of_healing": "an elf pouring shining water from cupped hands over a wounded comrade",
    "sleep": "an orc slumped asleep against a wall, a mist of magic drifting around its head",
    "veil_of_mist": "a hero walking unseen through a thick mist past a group of goblins",
    "heal_body": "a wizard laying glowing hands on the chest of a wounded barbarian",
    "pass_through_rock": "a ghostly translucent hero stepping through a solid stone wall",
    "rock_skin": "a warrior whose skin is turning to cracked stone as a sword shatters against him",
    "c_command": "an evil sorcerer controlling a hero with chains of dark magic coming from his staring eyes",
    "c_cloud_of_chaos": "a swirling cloud of chaos smoke engulfing heroes who stand frozen and paralysed",
    "c_firestorm": "a storm of fire raining down on a dungeon room, heroes shielding themselves",
    "c_summon_orcs": "orc warriors emerging from a magic circle drawn on the floor by a chaos sorcerer",
    "c_summon_undead": "skeletons and zombies clawing up through the flagstones around a chaos sorcerer",
    "dagger": "a single steel dagger with one straight blade and a leather-wrapped hilt, held upright "
              "in an adventurer's hand, only one weapon in the picture",
    "staff": "a long wooden quarterstaff with iron bands leaning against a stone wall",
    "shortsword": "a single short sword with one straight blade and a simple crossguard, hanging point-down "
                  "from a hook on a stone wall, only one weapon in the picture",
    "hand_axe": "a small hand axe stuck in a wooden block",
    "spear": "a long spear with a leaf-shaped head leaning against a weapon rack",
    "broadsword": "a large broadsword with a wide blade and ornate crossguard on a table",
    "crossbow": "a heavy crossbow with a quiver of bolts on a wooden table",
    "battle_axe": "a huge double-headed battle axe with a long haft",
    "shield": "a round wooden shield with an iron rim and boss, painted with a heraldic emblem",
    "helmet": "a steel helmet with a nose guard on a wooden stand",
    "bracers": "a pair of engraved leather and steel bracers",
    "cloak_of_protection": "a hooded cloak embroidered with protective runes hanging on a peg",
    "chain_mail": "a shirt of chain mail hanging on a wooden armour stand",
    "plate_armour": "a full suit of plate armour on an armour stand",
    "tool_kit": "an open leather tool roll with small pliers, chisels, a little hammer and coils of wire",
    "borins_armour": "a magnificent suit of dwarven plate armour engraved with runes, on a stand",
    "spirit_blade": "a sword with a ghostly glowing blade surrounded by wisps of spirit light",
    "orcs_bane": "an elven short sword with runes on the blade, an orc helmet split in two beside it",
    "talisman_of_lore": "an ornate amulet with a large gem on a chain, ancient symbols around it",
    "wand_of_magic": "a slender carved wand crackling with sparks of magic",
    "wizards_cloak": "a wizard's cloak covered in stars and moons, billowing",
    "wizards_staff": "a tall gnarled wizard's staff topped with a glowing orb",
    "ring_of_return": "a ring on a hand, a swirling portal opening in the air before it",
    "elixir_of_life": "an ornate crystal flask of elixir held over a fallen hero who begins to rise",
    "spell_ring": "a ring set with a gem crackling with magic, a spell scroll beside it",
}

STYLE = ("Painted fantasy illustration in the style of late-1980s fantasy board game card art "
         "(oil painting, dramatic warm candlelight, dark dungeon stone background, rich textured "
         "brushstrokes). %s, centered, filling the frame. No text, no border, no logo.")

CARDS = {
    "gold": "A small leather pouch spilling a pile of shining gold coins onto a stone floor",
    "gem": "A single large faceted red ruby glowing softly on a stone ledge",
    "jewels": "A heap of jewels, gold rings, pearl necklaces and sparkling gemstones",
    "treasure_horde": "An open iron-bound wooden treasure chest overflowing with gold coins, goblets and jewels",
    "potion_healing": "A round glass potion flask filled with glowing ruby-red liquid, cork stopper, wax seal",
    "potion_strength": "A tall glass potion bottle with glowing orange liquid, iron fittings, a faint aura of power",
    "potion_resilience": "A sturdy stoppered glass vial with glowing blue liquid, wrapped in leather and iron bands",
    "potion_speed": "A slender glass potion bottle with swirling glowing green liquid, a feather tied to its neck",
    "heroic_brew": "A battered pewter tankard of foaming golden brew, steam rising, on a wooden table",
    "holy_water": "A small crystal vial of shining holy water with a silver cross-shaped stopper, radiating white light",
    "trap_arrow": "A hidden arrow shooting out of a slit in a dungeon wall, motion blur, dust",
    "trap_pit": "A dark pit trap opening in the flagstones of a dungeon corridor, broken stones falling in",
    "wandering_monster": "A snarling green orc warrior with a rusty scimitar lunging out of the darkness of a corridor",
    "nothing": "An empty open wooden chest with cobwebs and dust, nothing inside",
    "chest": "A closed iron-bound wooden treasure chest with a heavy lock in a dark dungeon room",
    # Feitiços dos heróis (Ar, Fogo, Água, Terra).
    "genie": "A huge blue genie made of swirling smoke and air rising from an ornate brass lamp, arms crossed",
    "swift_wind": "A magical gust of silver-white wind with swirling leaves rushing down a dungeon corridor",
    "tempest": "A small furious storm cloud with lightning and rain whirling inside a dungeon room",
    "fire_of_wrath": "A burst of crimson magical fire shooting from an open hand, sparks and embers",
    "courage": "A glowing golden flame of courage burning above a raised sword hilt",
    "ball_of_flame": "A roaring ball of orange fire hurtling through the air, trailing flames and smoke",
    "water_of_healing": "Glowing blue healing water pouring from cupped hands, droplets of light",
    "sleep": "A gentle cloud of blue sleeping mist with drifting stars and a crescent moon glow",
    "veil_of_mist": "A thick shimmering veil of pale blue magical mist filling a dungeon corridor",
    "heal_body": "Warm green-gold healing light glowing around an open palm, soft rays",
    "pass_through_rock": "A ghostly translucent figure stepping through a solid stone wall, ripples in the rock",
    "rock_skin": "A forearm covered in hard grey stone plates like living rock, glowing cracks",
    # Feitiços do Caos (Zargon). Bola de Fogo, Sono e Tempestade usam a arte dos heróis.
    "c_command": "A sinister purple glowing eye with chains of dark magic reaching out, mind control",
    "c_cloud_of_chaos": "A churning cloud of purple and green chaos smoke with crackling dark lightning",
    "c_firestorm": "A raging storm of fire raining down flaming meteors inside a dungeon hall",
    "c_summon_orcs": "Green orc warriors emerging from a glowing purple summoning circle on the floor",
    "c_summon_undead": "Skeletons and zombies clawing up from a glowing green summoning circle on the floor",
    # Equipamento da armeria.
    "dagger": "A steel dagger with a leather-wrapped hilt lying on a wooden table",
    "staff": "A long wooden quarterstaff with iron bands, leaning on a stone wall",
    "shortsword": "A short steel sword with a simple crossguard on a wooden table",
    "hand_axe": "A small single-bladed hand axe with a wooden handle",
    "spear": "A long spear with a leaf-shaped steel head and leather grip",
    "broadsword": "A large broadsword with a wide blade and ornate crossguard",
    "crossbow": "A heavy wooden crossbow with steel bow and a quiver of bolts",
    "battle_axe": "A huge double-headed battle axe with a long wooden haft",
    "shield": "A round wooden shield with iron rim and boss, painted with a heraldic emblem",
    "helmet": "A steel helmet with a nose guard and leather lining",
    "bracers": "A pair of engraved leather and steel bracers",
    "cloak_of_protection": "A deep blue cloak embroidered with protective silver runes, faintly glowing",
    "chain_mail": "A shirt of chain mail hanging on a wooden armour stand",
    "plate_armour": "A full suit of polished steel plate armour on an armour stand",
    "tool_kit": "An open leather tool roll with small pliers, chisels, a little hammer and coils of wire, a craftsman's kit",
    # Artefatos.
    "borins_armour": "A magnificent suit of dwarven plate armour with golden runes, glowing softly",
    "spirit_blade": "A sword with a ghostly glowing white-blue blade surrounded by spirit wisps",
    "orcs_bane": "An elven short sword with green runes on the blade, glowing menacingly",
    "talisman_of_lore": "A golden amulet with a glowing blue gem on a chain, ancient symbols",
    "wand_of_magic": "A slender carved wand with a glowing crystal tip, sparkles of magic",
    "wizards_cloak": "A midnight-blue wizard's cloak covered in silver stars and moons",
    "wizards_staff": "A tall gnarled wizard's staff topped with a glowing orb",
    "ring_of_return": "A golden ring with a swirling portal glowing inside its gem",
    "elixir_of_life": "An ornate crystal flask of shimmering golden elixir, radiant light",
    "spell_ring": "A silver ring set with a glowing violet gem crackling with magic",
    # Monstros.
    "goblin": "A small wiry green goblin with a jagged curved sword, snarling, crouched",
    "orc": "A brutish green orc warrior in crude armour with a heavy scimitar",
    "fimir": "A one-eyed reptilian Fimir monster with a bony tail club and horned head",
    "chaos_warrior": "A towering Chaos Warrior in black spiked full plate armour with a great sword",
    "gargoyle": "A winged stone gargoyle demon with horns and claws, crouching on a pedestal",
    "skeleton": "An undead skeleton warrior with a rusty sword and cracked shield",
    "zombie": "A shambling rotten zombie in tattered clothes, reaching forward",
    "mummy": "An ancient mummy wrapped in dirty bandages, glowing eyes, arms outstretched",
    "chaos_warlock": "A sinister Chaos Warlock sorcerer in dark purple robes and horned helm, casting dark magic",
    "witch_lord": "An undead Witch Lord king with a rusted crown, skeletal face and black regal robes on a throne",
}


def main() -> None:
    args = sys.argv[1:]
    force = "--force" in args
    ink = "--ink" in args
    table, out, style, size = (INK_CARDS, OUT_INK, INK_STYLE, "1536x1024") if ink else (CARDS, OUT, STYLE, "1024x1536")
    cards = [a for a in args if not a.startswith("--")] or list(table)
    unknown = [c for c in cards if c not in table]
    if unknown:
        sys.exit("Carta desconhecida: %s (use %s)" % (", ".join(unknown), ", ".join(table)))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    key = gen_portraits.api_key()
    for card in cards:
        path = out % card
        if os.path.exists(path) and not force:
            print("já existe:", path, "(use --force para refazer)")
            continue
        try:
            gen_portraits.generate_image(style % table[card], path, key, size)
        except SystemExit as e:  # recusa da moderação etc.: avisa e segue para a próxima
            print(e)


if __name__ == "__main__":
    main()
