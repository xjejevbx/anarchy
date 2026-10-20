# À reporter dans docs/GAME_DESIGN.md (déplacement automatique)

Remplacer la puce « **Double-clic** » par :

- **Déplacement automatique** (double-clic sur une case VISIBLE et praticable à pied, ou touche `*` du mode regard) : un vrai pas par action, les monstres jouent. Le chemin (`AutoPath`, 8 directions) peut contenir des **diagonales** : un pas diagonal déplace directement le joueur sur la case en diagonale (sans passer par la case intermédiaire) mais compte pour DEUX déplacements (temps, stamina, les monstres peuvent agir entre les deux), comme `7 9 1 3`. Une diagonale exige qu'au moins une des deux cases « de l'angle » soit libre. Il s'arrête si un ennemi apparaît, si le joueur est blessé, si le chemin est bloqué ou à la moindre touche.
- **Case ciblée** : un clic gauche (ou le curseur du mode regard) entoure la case d'un carré BLANC et pose des points sur les cases du trajet que suivrait le déplacement automatique (`World.show_target`, `Player.set_target`). Le carré passe au VERT quand le déplacement est lancé ; pendant le déplacement les points montrent le reste du chemin ; la case disparaît à l'arrivée. Dans le mode regard, quitter avec x / Échap efface l'aperçu.

Dans « Architecture » : `world/auto_path.gd` (`AutoPath`) : Dijkstra à seaux 8 directions (diagonale = coût 2, chemin le plus proche de la ligne droite) pour le double-clic / `*` ; BFS 4 directions pour la touche maintenue. `world/world.gd` : calque `_target_overlay` (carré + points de la case ciblée).

Dans « Diagonales » : préciser que la règle « deux pas orthogonaux » reste celle du CLAVIER (`7 9 1 3`) ; le déplacement automatique saute directement en diagonale.

---
# Lot 2 : touche maintenue et esquive du décor

Remplacer, dans « Touche maintenue », la phrase « La répétition s'arrête quand un ennemi apparaît dans la vue ou quand le joueur est blessé » par :
« La répétition s'arrête quand le joueur est blessé (l'apparition d'un ennemi ne l'arrête PLUS ; elle arrête toujours le déplacement automatique du double-clic / de `*`). »

Ajouter une règle **Esquive automatique du décor** (option du menu `|`, OUI par défaut, `Player.avoid_scenery`) :
- Un appui sur une direction ORTHOGONALE bloquée par le décor (arbre, mur, meuble, fenêtre...) contourne l'obstacle : détour d'au plus 6 pas (`DODGE_MAX_STEPS`), à au plus 3 cases de côté (`DODGE_RADIUS`), qui finit une case plus loin dans la direction demandée, sans reculer. Chaque pas est un vrai déplacement (temps, stamina, monstres). Le côté du dernier détour est essayé en premier.
- Fonctionne avec un simple appui comme avec la touche maintenue, et utilise le terrain RÉEL : il n'est pas nécessaire d'avoir la vue derrière l'obstacle.
- Jamais d'entrée dans l'eau si on n'y est pas déjà ; pas de détour si un monstre est devant (le coup part) ; le détour s'arrête si un monstre apparaît ou si le joueur est blessé.
- Touche maintenue : on avance tant que la case devant est libre (même inconnue) ; décor devant -> détour ; détour impossible, monstre devant ou eau profonde depuis la rive -> la répétition s'arrête. Option NON : ancien comportement (chemin sur cases connues).
- Menu `|` : 3 postures + ligne de l'option (8 / 2 pour y aller, Entrée ou 4 / 6 pour basculer, le menu reste ouvert).
- Les diagonales du clavier (7 9 1 3) ne sont pas concernées.
