# Sprites du jalon 11 : ids UltiCa improvisés

Les ids ci-dessous sont des **noms logiques CDDA / UltiCa choisis sans pouvoir ouvrir `assets/tiles.json`** (fichier non accessible à Claude).
À vérifier par recherche dans `tiles.json`. Un id absent n'empêche pas de jouer : le mobilier est dessiné en carré de sa `color` (repli), et `test_worldgen_determinism.gd` affiche « AVERTISSEMENT - tuiles absentes du pack ». Pour corriger, il suffit de changer le champ `tile` dans `data/worldgen/furniture.json`.

## Mobilier ajouté (`furniture.json`, à la fin de la liste)
| id jeu | tuile demandée | confiance | remarque |
|---|---|---|---|
| `f_desk` | `f_desk` | haute | bureau |
| `f_bench` | `f_bench` | haute | bancs d'église, mairie, aéroport |
| `f_locker` | `f_locker` | haute | casiers, boîtes aux lettres |
| `f_glass_fridge` | `f_glass_fridge` | moyenne | frigo vitrine (épicerie, bar) ; repli possible : `f_fridge` |
| `f_safe` | `f_safe_c` | haute | coffre-fort de la banque |
| `f_altar` | `f_altar` | moyenne | autel de l'église |
| `f_crate` | `f_crate_c` | haute | caisses (port, quincaillerie, hangar) |
| `f_container` | `f_container` | **faible** | conteneur maritime ; si absent, essayer `f_dumpster` ou un `t_*` de conteneur |
| `f_machinery_heavy` | `f_machinery_heavy` | moyenne | grue du port, camions de pompiers, avions (provisoire) |

## Terrains
Aucun nouveau terrain : piste d'atterrissage = `t_pavement` + `t_pavement_y` (marquage), quai = `t_concrete`, barreaux des cellules du commissariat = `t_fence`.

## À prévoir plus tard (sprites dédiés)
- avion, camion de pompiers, grue, conteneur (aujourd'hui des `f_machinery_heavy` / `f_container` génériques) ;
- marquage de parking (`t_pavement_y` sert de repli) ;
- `t_helipad` reste sans sprite (jalon 10).
