class_name WorldRng
extends RefCounted
## Aléatoire DÉTERMINISTE de la génération du monde (docs/WORLD_GEN.md §3).
## Règle : jamais de randi() / randf() / shuffle() globaux dans la génération. Tout vient de
## mix(seed, couche, x, y, z) : la même seed donne le même monde, quel que soit l'ordre d'exploration.
## Les entiers GDScript sont sur 64 bits avec retour à zéro en cas de dépassement (même résultat partout).
## Jalon 6b : une 4e coordonnée optionnelle `d` (0 = ignorée : les résultats existants ne changent PAS) sert à séparer des flux
## indépendants quand `c` est déjà pris par l'étage (z).

# Couches de génération : entiers CONSTANTS, ne jamais renuméroter (ajouter à la suite).
const LAYER_TERRAIN: int = 1
const LAYER_BIOME: int = 2
const LAYER_TOWN: int = 3
const LAYER_ROAD: int = 4
const LAYER_SPECIAL: int = 5
const LAYER_MAPGEN: int = 6
const LAYER_LOOT: int = 7
const LAYER_SPAWN: int = 8

const _GOLDEN: int = -7046029254386353131    # 0x9E3779B97F4A7C15
const _MUL_A: int = -4658895280553007687     # 0xBF58476D1CE4E5B9
const _MUL_B: int = -7723592293110705685     # 0x94D049BB133111EB
const _FNV_OFFSET: int = -3750763034362895579  # 0xCBF29CE484222325
const _FNV_PRIME: int = 1099511628211


## Décalage à droite LOGIQUE (sans extension de signe).
static func _lsr(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64 - n)) - 1)


static func _finalize(value: int) -> int:
	var z: int = (value ^ _lsr(value, 30)) * _MUL_A
	z = (z ^ _lsr(z, 27)) * _MUL_B
	return z ^ _lsr(z, 31)


## Mélange la seed, une couche et jusqu'à quatre coordonnées en un entier 64 bits bien réparti (d = 0 : ignorée).
static func mix(world_seed: int, layer: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0) -> int:
	var h: int = _finalize(world_seed + _GOLDEN)
	h = _finalize(h + _GOLDEN + layer)
	h = _finalize(h + _GOLDEN + a)
	h = _finalize(h + _GOLDEN + b)
	h = _finalize(h + _GOLDEN + c)
	if d != 0:
		h = _finalize(h + _GOLDEN + d)
	return h


## Réel dans [0, 1) dérivé d'un entier (53 bits de précision).
static func unit(hash_value: int) -> float:
	return float(hash_value & 0x1FFFFFFFFFFFFF) / 9007199254740992.0


## Vrai avec la probabilité `probability`, décidé uniquement par (seed, couche, x, y, z).
static func chance(world_seed: int, layer: int, a: int, b: int, c: int, probability: float) -> bool:
	return unit(mix(world_seed, layer, a, b, c)) < probability


## Générateur local (PCG32 de Godot) pour une zone : à créer par zone, jamais partagé.
static func rng_for(world_seed: int, layer: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(world_seed, layer, a, b, c, d)
	return rng


## Seed saisie par le joueur : un entier tel quel, sinon un texte haché (FNV-1a 64 bits, stable d'une version à l'autre).
static func seed_from_text(text: String) -> int:
	var clean: String = text.strip_edges()
	if clean.is_valid_int():
		return clean.to_int()
	var h: int = _FNV_OFFSET
	for byte: int in clean.to_utf8_buffer():
		h = (h ^ byte) * _FNV_PRIME
	return h
