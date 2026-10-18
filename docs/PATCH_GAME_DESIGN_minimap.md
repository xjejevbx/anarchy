# À reporter dans docs/GAME_DESIGN.md (je n'ai pas le fichier sur disque, seulement son texte)

Remplacer la ligne de l'architecture :

- `ui/minimap_ui.gd` (`MiniMapUI`) : mini-carte de debug (touche `m`), modale. Les routes entre villes s'y affichent jusqu'au zoom `ROUTES_MAX_ZOOM`
  (au-delà, le calcul de trop de régions serait long).

par :

- `ui/minimap_ui.gd` (`MiniMapUI`) : mini-carte de debug (touche `m`), modale. Grille ALIGNÉE sur des multiples du zoom, découpée en tuiles de
  16 x 16 échantillons mises en cache (statique, par zoom / x / y ; vidé si la seed change, survit à la fermeture). Calcul PROGRESSIF (budget
  `BUDGET_US` par frame, tuiles proches du centre d'abord, aperçu étiré d'un zoom plus large en attendant). Un seul replanning par frame (`_dirty`).
  Zooms : 16 à 4096 cases par échantillon (départ à 64). Routes et lieux spéciaux jusqu'au zoom `ROUTES_MAX_ZOOM` (16), villes jusqu'à
  `SETTLEMENTS_MAX_ZOOM` (256), biomes seuls au-delà.
