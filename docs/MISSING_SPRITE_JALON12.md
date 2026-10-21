# Sprites du jalon 12

**Aucun nouvel id de tuile** : le jalon 12 réutilise des terrains et du mobilier existants (donc rien à ajouter à `assets/tiles.json`).

Détournements provisoires à remplacer le jour où des sprites dédiés existent :
- **barrières** de péage, de barrage et de poste-frontière = `t_fence` (tuile `t_chainfence`, déjà utilisée par les clôtures) ; piste : `t_barricade_road` / `f_barricade_road` si on veut un vrai sprite ;
- **véhicules** (voitures du barrage, camions du relais routier, file d'attente du poste-frontière) = `f_machinery_heavy` (déjà ajouté au jalon 11, id de tuile à vérifier) ;
- **conteneurs** du poste-frontière = `f_container` (jalon 11, id **faible**) ;
- **pompes** du relais routier = `t_gas_pump` (déjà dans le pack) ;
- **tables de pique-nique** de l'aire de repos = `f_table` + `f_chair`.

Les meubles posés sur la route reposent sur un carreau `t_floor` (règle des plans : le mobilier est toujours sur du sol), donc un carré de plancher apparaît sous chaque véhicule.
