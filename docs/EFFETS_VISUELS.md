# Effets visuels

Tout est PUREMENT visuel : la logique (cases, temps, tours, monstres) n'est jamais retardée. Code : `scripts/render/fx.gd` (`Fx`). Interrupteurs et réglages en haut du fichier : `SHADOWS`, `SMOOTH_MOVE`, `DUST`, `SPLASH`, `WIND`.

| Effet | Fonctionnement |
|---|---|
| Ombres | Ellipse sous joueur et monstres (rétrécit pendant le rebond, absente à la nage) ; ombre des arbres dessinée dans le sol du chunk (`Chunk._draw`, seconde passe). |
| Mouvement fluide | `position` glisse vers `grid_pos` (`MOVE_SMOOTHING`) ; la caméra, enfant du joueur, suit. Rebond (`HOP_HEIGHT`) pendant un pas, respiration (`BREATH`) à l'arrêt, ancrés au bas de la case. Téléportation > 3 cases : saut direct. |
| Poussière (`Fx.footstep`) | Sprint : tout sol sec (7 grains). Marche : sable et terre seulement (3). Accroupi : rien. Couleur par terrain (`Fx.dust_color`). |
| Éclaboussures | À chaque pas à la nage (gouttes + onde, bulles en eau profonde) et en sortant de l'eau. `CPUParticles2D` dans `World.fx` (z_index 5, sous le brouillard). |
| Vent | `shaders/tree_wind.gdshader` sur les arbres (matériau partagé `Fx.wind_material`) : tronc fixe, canopée balancée, phase selon la position, rafales lentes. |

Aucun nouveau sprite requis. Limites : pas de poussière des monstres (visible dans le brouillard) ; ombre d'arbre de taille fixe ; un sprite d'arbre sans transparence en haut peut se déformer (ajuster `WIND_AMPLITUDE`).
