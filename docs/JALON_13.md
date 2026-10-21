# Jalon 13 : lieux militaires et secrets (à reporter dans la doc)

`GAME_DESIGN.md` et `WORLD_GEN.md` ne sont pas régénérés : coller les passages ci-dessous.

## WORLD_GEN.md
**§4.5 Lieux spéciaux**, ajouter : jalon 13 = 9 lieux militaires / secrets (tous `common: false`), plans dans `mapgen/military.json` (16 plans, chargés après `urban.json`) :
| Lieu | Empreinte | Accès | Remarque |
|---|---|---|---|
| `military_base` | 3 × 2 (caserne, QG, armurerie / enclos, portail, parc auto) | route | priorité 71, clôtures, véhicules |
| `research_lab` | 2 × 1 (bâtiment + plateforme d'héliport) | piste ou héliport | `max_town_distance` -1 |
| `missile_silo` | 1 | piste (≤ 14) | trappe 4×4 (`f_machinery_heavy`), bunker de contrôle, générateurs |
| `supply_depot` | 2 × 1 (hangar à rayonnages + cour de conteneurs) | route | |
| `bunker` | 1 | piste | dalle de béton, deux salles |
| `radar_station` | 1 | piste (≤ 14) | antenne = `f_machinery_heavy` |
| `military_camp` | 1 (trois tentes) | route | |
| `military_outpost` | 1 (guérite + barrière + véhicules) | route | |
| `radio_tower` | 1 (mât + local technique, clôture) | piste ou route | |
Aucun changement de code hormis `MapgenDB.PATHS` ; accès `track` / `road` / `helipad` existants. Les plans à piste ont leur porte de façade en colonne 11 et un chemin `=` jusqu'au bord sud.

**§9 Jalons** : 13 = fait (surface seulement). Reste : sous-sols du bunker, du silo et du labo (avec les étages, jalon 8), loot militaire (jalon 6).
**§10 Tests** : `test_jalon13.gd`.
**Limites** : pas de sprite dédié (antenne, trappe de silo, radar = `f_machinery_heavy` / `f_machinery_light`, voir `MISSING_SPRITE_JALON13.md`) ; `bunker_entrance` (jalon 10) coexiste avec `bunker` ; réglages de `chance` / `attempts` « à l'aveugle », à valider avec la mini-carte et les avertissements du test.

## GAME_DESIGN.md
- Statut monde : jalons 1-5, 9, 9b, 10, 11, 12, **13** faits ; restent 6 à 8, 14, 15.
- Architecture `worldgen/` : `mapgen_db` charge aussi `military.json`.
- Tests : ajouter `test_jalon13`.
