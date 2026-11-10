class_name Item
extends RefCounted
## Un objet concret (instance). Les caractéristiques viennent d'ItemDB ; l'instance ne garde
## que son id, sa quantité (objets empilables) et son contenu (conteneurs).
##
## Poids (style Project Zomboid) : le contenu d'un conteneur pèse contenu / weight_ratio,
## qu'il soit équipé ou simplement porté sur soi.

var id: String = ""
var count: int = 1
var contents: Array[Item] = []


static func create(item_id: String, n: int = 1) -> Item:
	var it := Item.new()
	it.id = item_id
	it.count = maxi(n, 1)
	return it


func def() -> Dictionary:
	return ItemDB.get_def(id)


func display_name() -> String:
	return String(def().get("name", id))


func unit_weight() -> float:
	return float(def().get("weight", 0.0))


func tile_id() -> String:
	return String(def().get("tile", ""))


func worn_tile() -> String:
	return String(def().get("worn_tile", ""))


func slot() -> String:
	return String(def().get("slot", ""))


func capacity_bonus() -> float:
	return float(def().get("capacity_bonus", 0.0))


func container_def() -> Dictionary:
	return def().get("container", {})


func is_container() -> bool:
	return not container_def().is_empty()


func is_stackable() -> bool:
	return bool(def().get("stackable", not is_container() and slot().is_empty()))


## x = grand côté, y = petit côté (cm) : l'objet peut être tourné pour entrer.
func size_dims() -> Vector2:
	var s: Array = def().get("size", [10, 10])
	return Vector2(maxf(float(s[0]), float(s[1])), minf(float(s[0]), float(s[1])))


func weight_ratio() -> float:
	return maxf(float(container_def().get("weight_ratio", 1.0)), 0.01)


func weight_limit() -> float:
	return float(container_def().get("weight_limit", 0.0))


func own_weight() -> float:
	return unit_weight() * count


func contents_real_weight() -> float:
	var total: float = 0.0
	for c: Item in contents:
		total += c.real_weight()
	return total


## Poids réel (balance) : l'objet + tout son contenu.
func real_weight() -> float:
	return own_weight() + contents_real_weight()


## Poids ressenti par le joueur : l'objet + son contenu réduit par le ratio du conteneur.
func carried_weight() -> float:
	return own_weight() + contents_real_weight() / weight_ratio()


func can_merge(other: Item) -> bool:
	return id == other.id and is_stackable() and other.is_stackable()


## "" si `item` peut entrer dans ce conteneur, sinon la raison du refus.
func can_hold(item: Item) -> String:
	if not is_container():
		return "n'est pas un conteneur"
	if item == self:
		return "impossible de se ranger soi-même"
	if item.is_container() and not item.contents.is_empty():
		return "le conteneur doit être vide pour être rangé"
	var cd: Dictionary = container_def()
	var dims: Vector2 = item.size_dims()
	var max_l: float = float(cd.get("max_length", 0.0))
	var max_w: float = float(cd.get("max_width", 0.0))
	if dims.x > max_l or dims.y > max_w:
		return "trop grand (%d×%d cm, max %d×%d)" % [dims.x, dims.y, max_l, max_w]
	if contents_real_weight() + item.real_weight() > weight_limit() + 0.0001:
		return "trop lourd (limite %.1f kg, déjà %.1f)" % [weight_limit(), contents_real_weight()]
	return ""


## Détache `n` unités de la pile : renvoie l'objet lui-même si n >= count, sinon une nouvelle pile.
func split(n: int) -> Item:
	if n >= count:
		return self
	count -= n
	return Item.create(id, n)


## Ajoute sans vérifier (voir can_hold), en fusionnant les piles.
func add_content(item: Item) -> void:
	for c: Item in contents:
		if c.can_merge(item):
			c.count += item.count
			return
	contents.append(item)


## Sérialisation récursive (conteneurs inclus) pour les sauvegardes.
func to_dict() -> Dictionary:
	var data: Dictionary = {"id": id, "count": count}
	if not contents.is_empty():
		var list: Array = []
		for c: Item in contents:
			list.append(c.to_dict())
		data["contents"] = list
	return data


static func from_dict(data: Dictionary) -> Item:
	var item := Item.create(String(data.get("id", "")), int(data.get("count", 1)))
	var list: Array = data.get("contents", [])
	for entry: Variant in list:
		if entry is Dictionary:
			item.contents.append(Item.from_dict(entry))
	return item
