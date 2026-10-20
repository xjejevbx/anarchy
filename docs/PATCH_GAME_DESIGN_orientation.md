# À coller dans docs/GAME_DESIGN.md

## 1. Dans « Santé, monstres, effets », après la ligne « Monstres (`MonsterData`...) » :

- **Orientation des monstres** (`Monster.facing`, 4 directions : haut, droite, bas, gauche ; flèche rouge au sol, plus grande et plus vive quand le joueur est dans sa zone d'attaque) : un monstre ne frappe en mêlée que la case en face de lui et ses deux diagonales avant (`Monster.in_front_arc`). Si le joueur est à portée (orthogonale ou diagonale) mais sur son flanc ou dans son dos, il **pivote** : `TURN_STEPS_PER_ACTION` (1) quart de tour (90°) par action, pour `move_cost x TURN_COST_FACTOR` (1.0) secondes et la même variation de stamina qu'un pas. Se déplacer l'oriente dans le sens du pas (gratuit) ; un tir à distance l'oriente vers la cible (gratuit) ; orientation de départ au hasard.
- **Ordre des tours** : le joueur agit TOUJOURS en premier (il change de case, `update_fov()`), puis `GameClock.advance()` fait jouer les monstres dont le moment d'action est arrivé (`World._on_time_advanced`). Un monstre prêt à frapper ne frappe donc pas un joueur qui vient de s'éloigner.

## 2. Dans « Limites connues / à faire » :

- **Orientation** : tir à distance, hurlement et meute ignorent la zone d'attaque ; frapper un monstre ne le fait pas pivoter avant son prochain tour ; un monstre qui ne voit pas le joueur ne pivote pas (voir `take_turn`). Contourner un monstre en sprint n'est pas garanti : régler `TURN_COST_FACTOR` en jeu.
