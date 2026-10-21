# Jalon 15 : rural et divers (à reporter dans la doc)

`GAME_DESIGN.md` et `WORLD_GEN.md` ne sont pas régénérés : coller les passages ci-dessous.

## WORLD_GEN.md
**§4.5 Lieux spéciaux**, ajouter : jalon 15 = 9 lieux ruraux / divers (tous `common: false`), plans dans `mapgen/rural.json` (14 plans, chargés après `naval.json`). Plusieurs sont **liés au climat** (champ `climates`) :
| Lieu | Empreinte | Climat / biomes | Accès |
|---|---|---|---|
| `ski_resort` | 2 × 1 (chalet + pistes avec remontées) | froid, toundra / taïga | piste ou route |
| `arctic_base` | 2 × 1 (bâtiment + héliport) | froid, toundra / taïga | piste ou héliport |
| `trapper_cabin` | 1 (plan `cabin` existant) | froid, taïga / toundra | piste |
| `oasis` | 1 (mare, palmiers, hutte) | chaud, désert | piste ou aucun |
| `jungle_temple` | 1 (temple à deux enceintes, autel) | chaud, jungle | piste |
| `nomad_camp` | 1 (trois tentes, feu) | chaud, désert / savane | piste ou route |
| `volcano_site` | 2 × 2 (cratère de 48 × 48 cases) | tous les biomes terrestres | aucun |
| `ancient_ruins` | 2 × 1 (enceinte en ruine, colonnes) | tous | aucun |
| `cave_entrance` | 1 (masse rocheuse en murs, entrée, petite cavité) | tous | piste |
Aucun changement de code hormis `MapgenDB.PATHS`. La lave du volcan est `t_reactor` (non praticable, couleur orange) ; les cendres sont `t_dirt`, le basalte `t_concrete`.

**§9 Jalons** : 15 = fait. Les jalons 11 à 15 (structures) sont terminés ; restent 6 (loot, monstres), 7 (sauvegarde), 8 (étages, toits, portes).
**§10 Tests** : `test_jalon15.gd`.
**Limites** : pas de neige (saisons) : les pistes de ski sont en mousse ; la grotte et les temples n'ont pas d'intérieur souterrain avant les étages ; le volcan est décoratif (lave infranchissable, pas de dégâts) ; l'oasis n'a pas d'eau douce spécifique (eau de la mare = `t_water_sh` / `t_water_dp`) ; `chance` / `attempts` réglés « à l'aveugle ».

## GAME_DESIGN.md
- Statut monde : jalons 1-5, 9, 9b, 10-15 faits ; restent 6 à 8.
- Architecture `worldgen/` : `mapgen_db` charge aussi `rural.json`.
- Tests : ajouter `test_jalon15`.
- Feuille de route : après la génération (jalons 1-5, 9-15), jalons 6-8 → combat plus riche → import complet d'UltiCa → jauge de suspense.
