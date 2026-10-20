# À coller dans la documentation

## docs/GAME_DESIGN.md

1. « Déplacement, diagonales, vue » : remplacer « Idem pour les monstres (A* 4 directions). » par :
   « Les monstres se déplacent aussi en diagonale (`PathFinder`, A* à 8 directions) : un pas diagonal est permis si l'une des deux cases de l'angle est praticable, déplace le monstre tout de suite sur la case en diagonale et lui coûte le temps et la stamina de DEUX pas (comme le déplacement automatique du joueur). À temps égal, A* préfère la diagonale à l'escalier. »
2. « Architecture » : `path_finder` = « A* borné 1500 cases / rayon 40, 8 directions ».
3. « Tests » : ajouter `test_pathfinder`.

## docs/WORLD_GEN.md §6

`PathFinder` : A* borné à la demande (8 directions, diagonale = 2 pas, règle de l'angle), sans grille globale.
