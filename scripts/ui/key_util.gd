class_name KeyUtil
extends RefCounted
## Détection d'une touche « lettre » indépendante de la disposition du clavier (AZERTY, QWERTY...).
## On teste, dans l'ordre : le code de la touche, son étiquette, puis le CARACTÈRE réellement tapé (le plus fiable :
## c'est ce que l'OS produit pour la disposition active). Les touches d'action « physiques » (pavé numérique, flèches,
## i, g, e, r, t, u...) restent détectées par position ; seules w et m passent par ici car leur position change en AZERTY.


## `letter` : une lettre (« m », « w »...), majuscule ou minuscule. Valable pour un événement « touche enfoncée ».
static func is_letter(event: InputEventKey, letter: String) -> bool:
	var code: int = letter.to_upper().unicode_at(0)  # KEY_A..KEY_Z valent le code ASCII majuscule
	if event.keycode == code or event.key_label == code:
		return true
	return event.unicode == code or event.unicode == letter.to_lower().unicode_at(0)
