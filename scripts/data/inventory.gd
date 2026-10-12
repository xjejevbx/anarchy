class_name Inventory
extends RefCounted
## Inventaire du joueur : objets « sur soi » (poids plein) + équipement (un objet par emplacement).
## Les conteneurs (sacs, poches), équipés ou non, réduisent le poids de leur contenu.

var loose: Array[Item] = []
var equipment: Dictionary = {}  # emplacement -> Item


## Poids total porté (kg), réductions de conteneurs équipés comprises.
func total_weight() -> float:
	var total: float = 0.0
	for it: Item in loose:
		total += it.carried_weight()
	for slot: String in equipment:
		total += (equipment[slot] as Item).carried_weight()
	return total


func capacity_bonus() -> float:
	var total: float = 0.0
	for slot: String in equipment:
		total += (equipment[slot] as Item).capacity_bonus()
	return total


func equipped_containers() -> Array[Item]:
	var out: Array[Item] = []
	for slot: String in ItemDB.SLOTS:
		var it := equipment.get(slot) as Item
		if it != null and it.is_container():
			out.append(it)
	return out


## Meilleur conteneur équipé pouvant recevoir l'objet (plus forte réduction de poids d'abord).
func find_container_for(item: Item) -> Item:
	if item.is_container():
		return null  # un sac ramassé reste sur soi (pour pouvoir l'équiper) ; on le range à la main
	var best: Item = null
	for c: Item in equipped_containers():
		if c.can_hold(item) != "":
			continue
		if best == null or c.weight_ratio() > best.weight_ratio():
			best = c
	return best


## Raison pour laquelle l'objet ne peut aller dans aucun conteneur équipé ("" si possible).
func why_no_container(item: Item) -> String:
	var containers: Array[Item] = equipped_containers()
	if containers.is_empty():
		return "aucun conteneur équipé"
	if find_container_for(item) != null:
		return ""
	return containers[0].can_hold(item)


## Range l'objet dans le meilleur conteneur, sinon sur soi. Renvoie le conteneur (null = sur soi).
func auto_add(item: Item) -> Item:
	var c: Item = find_container_for(item)
	if c != null:
		c.add_content(item)
	else:
		add_loose(item)
	return c


func add_loose(item: Item) -> void:
	for it: Item in loose:
		if it.can_merge(item):
			it.count += item.count
			return
	loose.append(item)


## Conteneur qui contient directement `item` (équipé ou non), null sinon.
func find_holder(item: Item) -> Item:
	for it: Item in loose:
		if it.contents.has(item):
			return it
	for slot: String in equipment:
		if (equipment[slot] as Item).contents.has(item):
			return equipment[slot] as Item
	return null


## Diviseur de poids appliqué à `item` (1.0 s'il n'est dans aucun conteneur).
func effective_ratio(item: Item) -> float:
	var holder: Item = find_holder(item)
	return holder.weight_ratio() if holder != null else 1.0


func is_loose(item: Item) -> bool:
	return loose.has(item)


func slot_of(item: Item) -> String:
	for slot: String in equipment:
		if equipment[slot] == item:
			return slot
	return ""


## Retire l'objet de partout (sur soi, équipement, contenu d'un conteneur).
func remove(item: Item) -> void:
	loose.erase(item)
	for slot: String in equipment.keys():
		if equipment[slot] == item:
			equipment.erase(slot)
	for it: Item in loose:
		it.contents.erase(item)
	for slot: String in equipment:
		(equipment[slot] as Item).contents.erase(item)


## Équipe l'objet ; l'ancien objet de l'emplacement repasse sur soi.
func equip(item: Item) -> String:
	var slot: String = item.slot()
	if slot.is_empty():
		return "ne peut pas être porté"
	remove(item)
	var old := equipment.get(slot) as Item
	if old != null:
		equipment.erase(slot)
		add_loose(old)
	equipment[slot] = item
	return ""


func unequip(slot: String) -> void:
	var it := equipment.get(slot) as Item
	if it != null:
		equipment.erase(slot)
		add_loose(it)


## Détache `qty` unités de `item` (tout si qty < 0 ou >= count) de leur emplacement et les renvoie.
func detach(item: Item, qty: int) -> Item:
	if qty < 0 or qty >= item.count:
		remove(item)
		return item
	return item.split(qty)


## "" si `qty` unités de `item` peuvent entrer dans `container`, sinon la raison du refus.
## Un conteneur rangé dans un autre conteneur ne peut rien recevoir ; un conteneur ne se range que vide.
func can_store(item: Item, qty: int, container: Item) -> String:
	if find_holder(container) != null:
		return "ce conteneur est lui-même dans un conteneur"
	if container.contents.has(item):
		return "déjà dans ce conteneur"
	var probe: Item = item if qty < 0 or qty >= item.count else Item.create(item.id, qty)
	return container.can_hold(probe)


## Range `qty` unités de `item` dans `container`. Renvoie "" ou la raison du refus.
func store(item: Item, container: Item, qty: int = -1) -> String:
	var reason: String = can_store(item, qty, container)
	if reason != "":
		return reason
	container.add_content(detach(item, qty))
	return ""


## Sort `qty` unités d'un conteneur : elles passent « sur soi ».
func take_out(item: Item, qty: int = -1) -> void:
	add_loose(detach(item, qty))
