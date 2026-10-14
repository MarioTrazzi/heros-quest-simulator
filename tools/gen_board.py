#!/usr/bin/env python3
"""Gera pela API de imagens da OpenAI a arte do tabuleiro: o tema de chão e
parede de cada quest e as faces pintadas dos móveis de papel (PaperFurniture).

    python3 tools/gen_board.py --themes               # todos os temas que faltam
    python3 tools/gen_board.py --themes barrow        # só um tema
    python3 tools/gen_board.py --paper                # todos os móveis que faltam
    python3 tools/gen_board.py --paper table throne   # só os pedidos
    python3 tools/gen_board.py --paper --force table  # refaz

Saída crua em assets/textures/raw/ (com .gdignore). Depois rode no Godot
    $G --headless --path . --script res://tools/prep_board_textures.gd
que recorta, põe a borda de papel, deixa a parede repetível, gera os normal maps
e grava em assets/textures/board/themes/<tema>/<parte>_{albedo,normal}.png e
assets/textures/furniture/paper/<id>_<top|front|side>.png.

A quest escolhe o tema com "theme" no JSON. Os móveis seguem o tamanho do
data/furniture.json e as alturas de PaperFurniture.HEIGHT (mesmos números aqui).

Provisório como as cartas: o estilo-alvo é o do Higgsfield (nano_banana_2).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_portraits  # noqa: E402  (mesma chave e chamada da API)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Saída crua numa pasta com .gdignore (o Godot não importa); o prep grava as finais.
RAW = os.path.join(ROOT, "assets", "textures", "raw")
OUT_THEME = os.path.join(RAW, "themes", "%s", "%s.png")
OUT_PAPER = os.path.join(RAW, "paper", "%s_%s.png")

# ---------------------------------------------------------------- temas

FLOOR_STYLE = ("Top-down orthographic view of %s. The tile fills the entire square image edge to edge, "
               "flat even lighting, no cast shadows, no perspective, painted in the style of a late-1980s "
               "fantasy board game printed board (gouache, fine ink outlines, muted warm colours). "
               "No text, no grid lines beyond the tile edge, no objects, no figures.")
WALL_STYLE = ("Seamless tileable texture of %s, straight-on front view, flat even lighting, no perspective, "
              "painted in the style of a late-1980s fantasy board game (gouache, fine ink outlines). "
              "The pattern continues across all edges. No text, no objects, no doors, no torches.")

# Cada piso é UM quadrado do tabuleiro (1 m); o Godot gira cada quadrado 0–3×90°.
THEMES = {
    # O Desafio: catacumbas de Verag, com o túmulo de Fellmarg. A arte atual veio do
    # Higgsfield (nano_banana_2, 1:1, 1k), com estas descrições e o estilo "oil painting,
    # rich textured brushstrokes, muted earthy colours" no lugar do guache.
    "ruins": {
        "floor_room": "one square floor tile of an ancient catacomb burial chamber: four large worn grey-brown "
                      "crypt flagstones with deep joints, fine cracks, bone dust and grit in the joints, "
                      "a faint chipped carved border",
        "floor_corridor": "one square floor tile of a narrow catacomb passage: old uneven dark grey cobblestones "
                          "and broken slabs packed with dark earth, dust and small grit",
        "wall": "an ancient catacomb wall: rough fitted grey-brown stone blocks of varied sizes with crumbling "
                "mortar, chips, cracks, old soot and a few dry roots",
    },
    # Sir Ragnar: masmorra dos orcs.
    "orc_dungeon": {
        "floor_room": "one square tile of dark grey dungeon flagstones, dirty, scattered straw, a few small bones, "
                      "dried mud stains",
        "floor_corridor": "one square tile of a rough dark stone dungeon corridor floor, packed dirt between "
                          "broken stones, scratches",
        "wall": "a crude dark grey dungeon wall of rough-cut stone blocks, soot stains and scratch marks",
    },
    # Barak Tor: túmulo do Rei Bruxo.
    "barrow": {
        "floor_room": "one square tile of cold grey-green tomb flagstones engraved with faint ancient runes "
                      "around the border, dust and thin cobwebs in the corners",
        "floor_corridor": "one square tile of a barrow passage floor, old cracked grey stone slabs half covered "
                          "in dark earth and dust",
        "wall": "a cold grey-green burial vault wall of fitted stone blocks with faint carved runes, dust and cobwebs",
    },
}

# ---------------------------------------------------------------- móveis de papel

PAPER_STYLE = ("A single piece of furniture painted as a printed cardboard punch-out piece of a late-1980s "
               "fantasy board game (gouache, bold ink outlines, rich warm colours, even lighting). %s "
               "Isolated object only, nothing else in the picture, no shadow, no floor, no text, no border.")
TOP = ("Seen straight from above (top-down orthographic, bird's-eye view, looking straight down): %s. "
       "Only the flat upper surface, it fills the entire image edge to edge.")
FRONT = ("Flat orthographic front elevation (no perspective) on a transparent background: %s. "
         "The object spans the full width of the image, standing on the bottom edge.")
SIDE = ("Flat orthographic side elevation (no perspective) on a transparent background: %s. "
        "The object spans the full width of the image, standing on the bottom edge.")

# Pegada (L × P em quadrados, data/furniture.json) e altura em m (PaperFurniture.HEIGHT).
# A arte da frente/lado é esticada no Godot para L × altura; pedir objetos largos e baixos.
PAPER = {
    "table": ((3, 2), 0.42, {
        "top": "a long wooden plank table top with a pewter plate, bread, a tankard and a candle",
        "front": "the long side of a sturdy low wooden table, thick plank top and four square legs, very wide and low",
        "side": "the short end of a sturdy low wooden table, plank top and two square legs",
    }),
    "sorcerers_table": ((3, 2), 0.42, {
        "top": "a dark wooden sorcerer's table covered with a purple cloth, a glowing arcane circle with a "
               "pentagram, a crystal ball, a skull, candles and an open grimoire",
        "front": "the long side of a low dark wooden table draped in a purple cloth with arcane symbols, very wide and low",
        "side": "the short end of a low dark wooden table draped in a purple cloth with arcane symbols",
    }),
    "alchemists_bench": ((3, 2), 0.42, {
        "top": "an alchemist's wooden workbench with glass flasks of coloured potions, a retort, a mortar and "
               "pestle and scattered herbs",
        "front": "the long side of a low wooden alchemist's bench with a shelf of coloured potion flasks on top, "
                 "very wide and low",
        "side": "the short end of a low wooden alchemist's bench with a potion flask on top",
    }),
    "tomb": ((2, 3), 0.5, {
        "top": "the stone lid of a tomb carved with the effigy of a knight lying with a sword on his chest",
        "front": "the head end of a carved stone sarcophagus with a skull relief",
        "side": "the long side of a carved stone sarcophagus with arches and runes, very wide and low",
    }),
    "rack": ((2, 3), 0.5, {
        "top": "a wooden torture rack bed with ropes, rollers and iron chains",
        "front": "the end of a wooden torture rack with a big roller and a winding handle",
        "side": "the long side of a wooden torture rack with ropes and iron chains, very wide and low",
    }),
    "bookcase": ((3, 1), 0.9, {
        "top": "the plain wooden top of a long bookcase",
        "front": "a tall wide wooden bookcase full of old leather books and scrolls, with a skull on a shelf",
        "side": "the plain wooden side panel of a bookcase",
    }),
    "cupboard": ((3, 1), 0.9, {
        "top": "plain wooden planks, the bare flat top board of a cupboard, no doors, no shelves",
        "front": "a wide wooden cupboard with two closed doors with iron hinges and open shelves with jars and bottles",
        "side": "the plain wooden side panel of a cupboard",
    }),
    "fireplace": ((3, 1), 0.7, {
        "top": "a bare flat wooden mantel shelf board with two candles, no fire, no stones",
        "front": "a wide stone fireplace with a burning log fire and a mantelpiece with candles",
        "side": "the narrow plain stone side wall of a fireplace, stacked blocks only, no fire, no opening",
    }),
    "weapons_rack": ((3, 1), 0.8, {
        "top": "plain wooden planks, the bare flat top board of a weapon rack, no weapons",
        "front": "a wide wooden weapon rack holding swords, axes, spears and shields",
        "side": "the wooden side of a weapon rack with a spear leaning on it",
    }),
    "throne": ((1, 1), 0.8, {
        "top": "a throne seen from above: red velvet cushion and the top of its tall carved back",
        "front": "a carved wooden and gold throne with a tall back and red velvet cushion",
        "side": "the side of a carved wooden and gold throne with a tall back",
    }),
    "treasure_chest": ((1, 1), 0.35, {
        "top": "the closed lid of an iron-bound wooden treasure chest",
        "front": "an iron-bound wooden treasure chest with a big lock, closed",
        "side": "the side of an iron-bound wooden treasure chest with an iron handle",
    }),
    # Peças de papelão chatas, como no jogo.
    "stairway": ((2, 2), 0.03, {
        "top": "a stone staircase descending into darkness, seen from above",
    }),
    "rubble": ((1, 1), 0.03, {
        "top": "a pile of fallen rocks and rubble blocking a dungeon square",
    }),
}


def _size(w: float, h: float) -> str:
    """Tamanho da API mais próximo do aspecto w:h."""
    if w / h > 1.25:
        return "1536x1024"
    if h / w > 1.25:
        return "1024x1536"
    return "1024x1024"


def gen_themes(names, key, force) -> None:
    for theme in names:
        for part, desc in THEMES[theme].items():
            path = OUT_THEME % (theme, part)
            if os.path.exists(path) and not force:
                print("já existe:", path, "(use --force para refazer)")
                continue
            os.makedirs(os.path.dirname(path), exist_ok=True)
            style = WALL_STYLE if part == "wall" else FLOOR_STYLE
            try:
                gen_portraits.generate_image(style % desc, path, key, "1024x1024", max_side=1024)
            except SystemExit as e:  # recusa da moderação etc.: avisa e segue
                print(e)


def gen_paper(names, key, force) -> None:
    os.makedirs(os.path.dirname(OUT_PAPER), exist_ok=True)
    for fid in names:
        (w, d), h, faces = PAPER[fid]
        for face, desc in faces.items():
            path = OUT_PAPER % (fid, face)
            if os.path.exists(path) and not force:
                print("já existe:", path, "(use --force para refazer)")
                continue
            if face == "top":
                prompt, size, bg = PAPER_STYLE % (TOP % desc), _size(w, d), ""
            else:
                width = w if face == "front" else d
                prompt = PAPER_STYLE % ((FRONT if face == "front" else SIDE) % desc)
                size, bg = _size(width, h), "transparent"
            try:
                gen_portraits.generate_image(prompt, path, key, size, background=bg, max_side=1024)
            except SystemExit as e:
                print(e)


def main() -> None:
    args = sys.argv[1:]
    force = "--force" in args
    names = [a for a in args if not a.startswith("--")]
    if "--themes" in args:
        table, run = THEMES, gen_themes
    elif "--paper" in args:
        table, run = PAPER, gen_paper
    else:
        sys.exit(__doc__)
    unknown = [n for n in names if n not in table]
    if unknown:
        sys.exit("Desconhecido: %s (use %s)" % (", ".join(unknown), ", ".join(table)))
    run(names or list(table), gen_portraits.api_key(), force)


if __name__ == "__main__":
    main()
