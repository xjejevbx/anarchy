# Jalon 14 : mer et eau (à reporter dans la doc)

`GAME_DESIGN.md` et `WORLD_GEN.md` ne sont pas régénérés : coller les passages ci-dessous.

## WORLD_GEN.md
**§4.5 Lieux spéciaux**, ajouter : jalon 14 = 9 lieux maritimes (tous `common: false`), plans dans `mapgen/naval.json` (19 plans, chargés après `military.json`) :
| Lieu | Empreinte | Zone / accès | Remarque |
|---|---|---|---|
| `aircraft_carrier` | 14 × 2 | `open_ocean` (4 cellules de large), héliport | proue pointue, pont `t_pavement` + marquage, tour de contrôle (porte), aéronefs, héliport |
| `research_station` | 1 | `open_ocean`, héliport | plate-forme, labo, héliport |
| `pirate_base` | 2 × 1 | `coast`, jetée | fort clôturé (porte vers l'eau) + pontons |
| `marina` | 1 | terre (mer ou lac), jetée | capitainerie + pontons |
| `hydro_dam` | 2 × 1 | biomes rivière / plaine / forêt, piste ou aucun | crête de barrage + centrale |
| `cargo_wreck` | 2 × 1 | `coast`, `ocean_shallow`, aucun | coque trouée, conteneurs, cabine, sans porte |
| `shipwreck_field` | 2 × 1 | `coast`, `ocean_shallow`, aucun | débris dispersés |
| `island_village` | 2 × 2 | `island` (≥ 5 cellules), aucun | plans de maison existants (`cabin`, `shed`, `house_small`) |
| `lighthouse_island` | 1 | `island`, jetée | réutilise le plan `lighthouse` |
Aucun changement de code hormis `MapgenDB.PATHS`. Les plans ouverts (`.`) laissent l'eau profonde en pleine mer : le porte-avions est une dalle de béton / asphalte posée sur l'océan.

**§9 Jalons** : 14 = fait. Reste : bateaux (hors périmètre), ferries, cales et sous-sols (étages, jalon 8), loot (jalon 6).
**§10 Tests** : `test_jalon14.gd`.
**Limites** : le porte-avions est lisse (pas de rambarde : on y monte depuis l'eau en nageant) ; `hydro_dam` n'est pas orienté selon le courant de la rivière (la crête peut longer l'eau au lieu de la barrer) ; l'empreinte du porte-avions est coûteuse à valider (28 cellules, zone `open_ocean`) : surveiller le temps de génération d'une région ; `lighthouse_island` ajoute des cellules `SPECIAL` sur de petites îles (peut retirer un spot au scénario « île » : `_island_spot` les ignore) ; chances et `attempts` réglés « à l'aveugle ».

## GAME_DESIGN.md
- Statut monde : jalons 1-5, 9, 9b, 10-14 faits ; restent 6 à 8 et 15.
- Architecture `worldgen/` : `mapgen_db` charge aussi `naval.json`.
- Tests : ajouter `test_jalon14`.
