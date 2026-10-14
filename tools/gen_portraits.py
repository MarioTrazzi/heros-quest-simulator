#!/usr/bin/env python3
"""Gera os retratos pintados dos heróis (HeroSheet) pela API de imagens da OpenAI.

    python3 tools/gen_portraits.py dwarf elf      # só os pedidos
    python3 tools/gen_portraits.py --force wizard # refaz um que já existe

A chave vem de OPENAI_API_KEY ou do arquivo ~/.openai_key (fora do repositório).
Salva em assets/textures/ui/portrait_<id>.png, 3:4, reduzido para 600 px de altura.
"""
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "ui", "portrait_%s.png")
MODEL = "gpt-image-1"

# Os quatro retratos atuais vieram do Higgsfield: generate_image, modelo
# nano_banana_2, aspect_ratio 3:4, resolution 1k e este prompt (STYLE % descrição),
# reduzidos com sips -Z 600. Ficam melhores que os da OpenAI: este script é reserva.
STYLE = ("Painted fantasy portrait in the style of late-1980s fantasy board game card art "
         "(oil painting, dramatic warm candlelight, dark dungeon stone background, rich textured "
         "brushstrokes). %s, waist-up, centered. No text, no border, no logo.")

HEROES = {
    "barbarian": "A muscular barbarian hero with long blond hair, fur loincloth and leather straps, "
                 "holding a huge broadsword, fierce expression",
    "dwarf": "A stocky dwarf hero with a long braided red beard, horned iron helmet, chainmail, "
             "holding a short sword, stern expression",
    "elf": "A slender elf hero with pointed ears and long fair hair, green tunic and cloak, "
           "holding a short sword, alert noble expression",
    "wizard": "An old wizard hero with a long white beard, deep blue hooded robes covered in silver "
              "stars, holding a glowing staff, a dagger at the belt, wise intense gaze",
}


def api_key() -> str:
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    path = os.path.expanduser("~/.openai_key")
    if not key and os.path.exists(path):
        with open(path) as f:
            key = f.read().strip()
    if not key:
        sys.exit("Sem chave: defina OPENAI_API_KEY ou crie ~/.openai_key")
    return key


def generate_image(prompt: str, path: str, key: str, size: str = "1024x1536",
                   background: str = "", max_side: int = 600) -> None:
    """Gera a imagem (2:3 em pé por padrão; "1536x1024" deitada, "1024x1024"
    quadrada) e grava em path, reduzida para max_side px no lado maior.
    background="transparent" pede PNG com fundo transparente."""
    params = {
        "model": MODEL,
        "prompt": prompt,
        "size": size,
        "quality": "medium",
        "n": 1,
    }
    if background:
        params["background"] = background
    body = json.dumps(params).encode()
    req = urllib.request.Request("https://api.openai.com/v1/images/generations", data=body, headers={
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        sys.exit("%s: erro %d — %s" % (os.path.basename(path), e.code, e.read().decode()[:500]))
    with open(path, "wb") as f:
        f.write(base64.b64decode(data["data"][0]["b64_json"]))
    # 1024×1536 → 400×600 (o resto do projeto usa até 600 px no lado maior).
    subprocess.run(["sips", "-Z", str(max_side), path], check=True, capture_output=True)
    print("ok:", path)


def generate(hero: str, key: str) -> None:
    generate_image(STYLE % HEROES[hero], OUT % hero, key)


def main() -> None:
    args = sys.argv[1:]
    force = "--force" in args
    heroes = [a for a in args if a != "--force"] or list(HEROES)
    unknown = [h for h in heroes if h not in HEROES]
    if unknown:
        sys.exit("Herói desconhecido: %s (use %s)" % (", ".join(unknown), ", ".join(HEROES)))
    key = api_key()
    for hero in heroes:
        if os.path.exists(OUT % hero) and not force:
            print("já existe:", OUT % hero, "(use --force para refazer)")
            continue
        generate(hero, key)


if __name__ == "__main__":
    main()
