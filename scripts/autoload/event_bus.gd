extends Node
## Autoload "EventBus" : signaux globaux pour découpler les systèmes.

signal time_advanced(points: float)
signal stamina_changed(current: float, maximum: float, time_penalty: float)
signal load_changed(weight: float, capacity: float)
signal health_changed(current: float, maximum: float)  # PV TOTAUX (somme des parties du corps)
signal action_performed(action_name: String, cost: float, stamina_delta: float)
signal message_logged(text: String)
signal monster_hovered(monster: Node)  # null quand on ne survole plus de monstre
signal hostile_spotted(monster: Node)  # un monstre vient d'entrer dans le champ de vision
signal inventory_requested  # touche i
signal ground_requested     # touche g : cases à portée contenant des objets
signal ground_all_requested # G (Maj+g) : les 9 cases à portée dans une seule liste
signal minimap_requested     # touche m : mini-carte de debug
signal character_requested   # touche c : écran du personnage (onglets : stats, corps...)
signal posture_requested     # touche | : menu de choix de la posture (marche / sprint / accroupi)
signal posture_changed(posture_name: String)
signal look_requested(direction: Vector2i)  # touche x (direction nulle) ou Maj + pavé numérique / flèches : mode regard
