class_name InventoryLedger
extends RefCounted
## Suit les déplacements d'objets pendant qu'un écran d'inventaire est ouvert et calcule leur coût NET en temps.
## On compare l'état au début de la session (inventaire + cases à portée) à l'état actuel : un objet remis à sa place
## ne coûte rien, un objet déplacé plusieurs fois ne coûte que son déplacement final (origine -> destination).
## Chaque objet déplacé (chaque unité d'une pile) est une étape à part avec son propre coût.
##
## Emplacements : "ground:x,y", "loose" (sur soi), "slot:<emplacement>" (équipé), "in:<id d'un conteneur>".
## Type de coût selon le trajet : depuis le sol = ramassage ; équiper/retirer = habillage ; vers le sol depuis
## « sur soi » = gratuit ; tout le reste (ranger, sortir, poser depuis un conteneur) = manipulation.
##
## Permet aussi d'annuler les déplacements d'un objet (revert(clé)) ou tous (revert("")).

var _player: Player
var _cells: Array[Vector2i] = []
var _before: Dictionary = {}  # clé d'objet -> {emplacement -> quantité}
var _refs: Dictionary = {}    # clé d'objet -> Item (pour les poids et les noms)


func begin(player: Player) -> void:
	_player = player
	_cells = player.reach_cells()
	_refs.clear()
	_before = _snapshot()


## Clé d'un objet : les conteneurs sont uniques (leur contenu leur appartient), les autres se regroupent par id.
func key_of(item: Item) -> String:
	return item.id + ("#%d" % item.get_instance_id() if item.is_container() else "")


## {"cost": coût de base total, "moves": nombre d'étapes, "steps": [{text, cost, to, key}]} (une étape par objet).
func compute() -> Dictionary:
	var steps: Array[Dictionary] = []
	var total: float = 0.0
	for p: Dictionary in _pairs():
		var unit_cost: float = _pair_cost(String(p["from"]), String(p["to"]), float(p["unit"]))
		var text: String = _step_text(p)
		for i in int(p["n"]):
			steps.append({"text": text, "cost": unit_cost, "to": p["to"], "key": p["key"]})
			total += unit_cost
	return {"cost": total, "moves": steps.size(), "steps": steps}


func has_changes(key: String) -> bool:
	for p: Dictionary in _pairs():
		if p["key"] == key:
			return true
	return false


## Remet à leur place d'origine les objets de clé `key` (tous les objets si key == "").
func revert(key: String) -> void:
	for p: Dictionary in _pairs():
		if key != "" and p["key"] != key:
			continue
		var units: Array[Item] = _take_units(String(p["to"]), String(p["key"]), int(p["n"]))
		for unit: Item in units:
			_put_unit(String(p["from"]), unit)
	_player.refresh_inventory()


# --- Déplacements nets ---

## [{key, from, to, n, unit}] : `n` unités de poids `unit` sont passées de `from` à `to`.
func _pairs() -> Array[Dictionary]:
	var after: Dictionary = _snapshot()
	var keys: Dictionary = {}
	for k: String in _before:
		keys[k] = true
	for k: String in after:
		keys[k] = true
	var out: Array[Dictionary] = []
	for key: String in keys:
		var b: Dictionary = _before.get(key, {})
		var a: Dictionary = after.get(key, {})
		var locs: Dictionary = {}
		for l: String in b:
			locs[l] = true
		for l: String in a:
			locs[l] = true
		var losses: Array = []
		var gains: Array = []
		for loc: String in locs:
			var delta: int = int(a.get(loc, 0)) - int(b.get(loc, 0))
			if delta < 0:
				losses.append([loc, -delta])
			elif delta > 0:
				gains.append([loc, delta])
		var unit: float = _unit_weight(key)
		for loss: Array in losses:
			var left: int = loss[1]
			for gain: Array in gains:
				var n: int = mini(left, int(gain[1]))
				if n <= 0:
					continue
				gain[1] = int(gain[1]) - n
				left -= n
				out.append({"key": key, "from": loss[0], "to": gain[0], "n": n, "unit": unit})
	return out


func _pair_cost(from_loc: String, to_loc: String, weight: float) -> float:
	if from_loc.begins_with("ground:"):
		return _player.pickup_cost_for_weight(weight)
	if from_loc.begins_with("slot:") or to_loc.begins_with("slot:"):
		return _player.equip_cost_for_weight(weight)
	if to_loc.begins_with("ground:") and from_loc == "loose":
		return 0.0
	return _player.handle_cost_for_weight(weight)


func _step_text(p: Dictionary) -> String:
	var item_name: String = "objet"
	var ref := _refs.get(p["key"]) as Item
	if ref != null:
		item_name = ref.display_name()
	var from_loc: String = p["from"]
	var to_loc: String = p["to"]
	if to_loc.begins_with("ground:"):
		return "Dépôt de %s au sol (case %d)" % [item_name, _digit_of(to_loc)]
	if to_loc.begins_with("slot:"):
		return "Équipement de %s" % item_name
	if from_loc.begins_with("slot:"):
		return "Retrait de %s" % item_name
	if to_loc.begins_with("in:"):
		var holder := instance_from_id(int(to_loc.substr(3))) as Item
		return "Rangement de %s dans %s" % [item_name, holder.display_name() if holder != null else "un conteneur"]
	if from_loc.begins_with("in:"):
		return "Sortie de %s" % item_name
	return "Déplacement de %s" % item_name


## Chiffre du pavé numérique correspondant à une case « ground:x,y » (7 8 9 / 4 5 6 / 1 2 3).
func _digit_of(ground_loc: String) -> int:
	var parts: PackedStringArray = ground_loc.substr(7).split(",")
	var offset := Vector2i(int(parts[0]), int(parts[1])) - _player.grid_pos
	return 5 + offset.x - 3 * offset.y


# --- Annulation ---

## Retire jusqu'à `n` unités de clé `key` de l'emplacement `loc` ; renvoie les unités détachées.
func _take_units(loc: String, key: String, n: int) -> Array[Item]:
	var out: Array[Item] = []
	var inv: Inventory = _player.inventory
	var candidates: Array[Item] = []
	if loc == "loose":
		candidates.assign(inv.loose)
	elif loc.begins_with("slot:"):
		var worn := inv.equipment.get(loc.substr(5)) as Item
		if worn != null:
			candidates.append(worn)
	elif loc.begins_with("in:"):
		var holder := instance_from_id(int(loc.substr(3))) as Item
		if holder != null:
			candidates.assign(holder.contents)
	elif loc.begins_with("ground:"):
		for d: Dictionary in _player.pending_drops:
			if key_of(d["item"] as Item) == key:
				var item := d["item"] as Item
				var take: int = mini(n, item.count)
				var unit: Item = item.split(take)
				if unit == item:
					_player.pending_drops.erase(d)
				out.append(unit)
				n -= take
				if n <= 0:
					break
		return out
	for it: Item in candidates:
		if n <= 0:
			break
		if key_of(it) != key:
			continue
		var take: int = mini(n, it.count)
		out.append(inv.detach(it, take))
		n -= take
	return out


func _put_unit(loc: String, unit: Item) -> void:
	var inv: Inventory = _player.inventory
	if loc.begins_with("slot:"):
		inv.equip(unit)
	elif loc.begins_with("in:"):
		var holder := instance_from_id(int(loc.substr(3))) as Item
		if holder != null:
			holder.add_content(unit)
		else:
			inv.add_loose(unit)
	elif loc.begins_with("ground:"):
		_player.world.add_ground_item(_player.grid_pos, unit)
	else:
		inv.add_loose(unit)


# --- Instantané ---

func _unit_weight(key: String) -> float:
	var ref := _refs.get(key) as Item
	if ref == null:
		return 0.0
	return ref.real_weight() if ref.count <= 1 else ref.unit_weight()


func _snapshot() -> Dictionary:
	var snap: Dictionary = {}
	for cell: Vector2i in _cells:
		for it: Item in _player.world.get_ground_items(cell):
			_add(snap, "ground:%d,%d" % [cell.x, cell.y], it)
	for d: Dictionary in _player.pending_drops:
		var drop_cell: Vector2i = d["cell"]
		_add(snap, "ground:%d,%d" % [drop_cell.x, drop_cell.y], d["item"] as Item)
	for it: Item in _player.inventory.loose:
		_add(snap, "loose", it)
	for slot: String in _player.inventory.equipment:
		_add(snap, "slot:" + slot, _player.inventory.equipment[slot] as Item)
	return snap


func _add(snap: Dictionary, loc: String, item: Item) -> void:
	var key: String = key_of(item)
	_refs[key] = item
	var per_loc: Dictionary = snap.get(key, {})
	per_loc[loc] = int(per_loc.get(loc, 0)) + item.count
	snap[key] = per_loc
	var inner: String = "in:%d" % item.get_instance_id()
	for c: Item in item.contents:
		_add(snap, inner, c)
