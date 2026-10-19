# Effets visuels (premier lot)

Tout est PUREMENT visuel : la logique (cases, temps, tours, monstres) n'est jamais retardée ni modifiée. Code : `scripts/render/fx.gd` (`Fx`).
Chaque effet a un interrupteur (`SHADOWS`, `SMOOTH_MOVE`, `DUST`, `SPLASH`, `WIND`) et ses réglages en haut de `fx.gd`.

- **Ombres** : ellipse sombre sous le joueur et les monstres (rétrécit pendant le rebond, absente à la nage) ; ombre des arbres dessinée dans le sol du chunk (`Chunk._draw`, seconde passe).
- **Mouvement fluide** : `position` du joueur et des monstres glisse vers `grid_pos` (lissage exponentiel `MOVE_SMOOTHING`) ; la caméra, enfant du joueur, suit. Petit rebond (`HOP_HEIGHT`) pendant un pas, respiration (`BREATH`) à l'arrêt, ancrés au bas de la case (`draw_set_transform`). Une téléportation de plus de 3 cases saute directement.
- **Poussière** (`Fx.footstep`) : sprint sur tout sol sec (7 grains), marche sur sable et terre seulement (3), accroupi : rien. Couleur selon le terrain (`Fx.dust_color`).
- **Éclaboussures** : à chaque pas à la nage (gouttes + onde, plus des bulles en eau profonde) et en sortant de l'eau. Particules `CPUParticles2D` dans `World.fx` (z_index 5, sous le brouillard).
- **Vent** : `shaders/tree_wind.gdshader` sur les sprites d'arbres (matériau partagé `Fx.wind_material`). Le tronc reste fixe, la canopée se balance ; phase selon la position, rafales lentes.

Aucun nouveau sprite n'est nécessaire (rien à ajouter dans `MISSING_SPRITE.md` / `tiles.json`).
Limites : pas de poussière des monstres (elle apparaîtrait dans le brouillard) ; ombre d'arbre de taille fixe ; un sprite d'arbre sans transparence en haut peut se déformer un peu (ajuster `WIND_AMPLITUDE`).
