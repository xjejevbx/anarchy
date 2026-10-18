#!/usr/bin/env python3
"""Construit le "pack" UltiCa minimal utilisé par le jeu.

UltiCa (dossier gfx/UltimateCataclysm du dépôt I-am-Erk/CDDA-tilesets) est stocké sous
forme de milliers de PNG individuels. Ce script ne copie que les sprites des ids listés
ci-dessous et écrit un manifeste tiles.json lu par scripts/render/ultica_tiles.gd.

Usage :
    python3 build_ultica_pack.py <chemin>/gfx/UltimateCataclysm <projet>/assets/ultica

Pour ajouter un objet ou un monstre : ajoute son id dans IDS et relance le script.
"""
import json
import re
import shutil
import sys
from pathlib import Path

# Ids CDDA dont on veut le rendu (fg/bg) ; leurs sprites sont copiés automatiquement.
IDS = [
    "t_grass_dead", "t_grass_long", "t_moss",
]

# Dossiers dont on copie TOUS les sprites, pour les utiliser directement par nom
# (murs : on choisit nous-mêmes le sprite selon les voisins, voir world.gd).
EXTRA_SPRITE_DIRS = ["pngs_normal_32x32/terrain/t_wall"]

FOLDER_RE = re.compile(r"pngs_(.+)_(\d+)x(\d+)$")


def is_filler(folder: str) -> bool:
    return "filler" in folder or "incomplete" in folder


def normalize_layer(layer):
    """fg/bg peut être une chaîne, une liste de chaînes ou une liste {sprite, weight}."""
    if not layer:
        return []
    if isinstance(layer, str):
        return [{"sprite": layer, "weight": 1}]
    out = []
    for v in layer:
        if isinstance(v, str):
            out.append({"sprite": v, "weight": 1})
        elif isinstance(v, dict) and isinstance(v.get("sprite"), str):
            out.append({"sprite": v["sprite"], "weight": v.get("weight", 1)})
    return out


def main(src: Path, out: Path) -> None:
    tile_info = json.loads((src / "tile_info.json").read_text(encoding="utf-8"))
    settings = {}
    for entry in tile_info[1:]:
        for fname, cfg in entry.items():
            settings[fname.removesuffix(".png")] = cfg

    # Index des PNG : nom de sprite -> (fichier, décalage). Les dossiers "filler" passent en dernier.
    sprites_index = {}
    pngs = [p for p in src.glob("pngs_*/**/*.png")]
    pngs.sort(key=lambda p: (is_filler(p.relative_to(src).parts[0]), str(p)))
    for png in pngs:
        folder = png.relative_to(src).parts[0]
        m = FOLDER_RE.match(folder)
        if not m or png.stem in sprites_index:
            continue
        cfg = settings.get(m.group(1), {})
        offset = [cfg.get("sprite_offset_x", 0), cfg.get("sprite_offset_y", 0)]
        sprites_index[png.stem] = (png, offset)

    # Entrées de tuiles (id -> fg/bg), en préférant les dossiers non-filler.
    tiles = {}
    jsons = sorted(src.glob("pngs_*/**/*.json"), key=lambda p: (is_filler(p.relative_to(src).parts[0]), str(p)))
    for js in jsons:
        try:
            data = json.loads(js.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        for entry in data if isinstance(data, list) else [data]:
            if not isinstance(entry, dict):
                continue
            ids = entry.get("id")
            for tid in ids if isinstance(ids, list) else [ids]:
                if tid in IDS and tid not in tiles:
                    tiles[tid] = {"fg": normalize_layer(entry.get("fg")), "bg": normalize_layer(entry.get("bg"))}

    missing = [i for i in IDS if i not in tiles]
    if len(missing) > len(IDS) // 2:
        sys.exit(f"Trop d'ids introuvables (dossier non récupéré ?) : {missing}")
    if missing:
        print(f"AVERTISSEMENT : ids introuvables dans UltiCa (le jeu dessinera un repli coloré) : {missing}")

    wanted = set()
    for t in tiles.values():
        for layer in ("fg", "bg"):
            wanted.update(v["sprite"] for v in t[layer])
    for d in EXTRA_SPRITE_DIRS:
        wanted.update(p.stem for p in (src / d).glob("*.png"))

    (out / "sprites").mkdir(parents=True, exist_ok=True)
    manifest_sprites = {}
    for name in sorted(wanted):
        if name not in sprites_index:
            print(f"AVERTISSEMENT : sprite introuvable : {name}")
            continue
        png, offset = sprites_index[name]
        shutil.copy2(png, out / "sprites" / f"{name}.png")
        manifest_sprites[name] = {"file": f"sprites/{name}.png", "offset": offset}

    manifest = {"tile_size": 32, "sprites": manifest_sprites, "tiles": tiles}
    (out / "tiles.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"{len(manifest_sprites)} sprites, {len(tiles)} tuiles écrits dans {out}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
