# À reporter dans GAME_DESIGN.md (santé par parties du corps + mode regard)

## À ajouter dans « Règles de jeu décidées »
- **Santé par parties du corps (style CDDA)** : plus de PV globaux. `data/body_parts.json` (`BodyPartDB`) : Tête 40, Torse 60, Bras g./d. 40,
  Jambes g./d. 50 (total 280, valeurs « à l'aveugle » à régler en jeu). **Mort quand la tête ou le torse tombe à 0 PV** (champ `vital`).
  Un membre à 0 PV est « hors d'usage » mais n'a PAS encore d'effet (à venir : bras = dégâts de mêlée, jambes = vitesse). Les PV d'une
  partie ne descendent pas sous 0 ; l'excédent est perdu. `Player.body` (id -> PV), `part_hp()`, `total_hp()`, `take_damage(montant, partie)`.
  Le HUD affiche les PV TOTAUX (signal `health_changed`). La noyade blesse le torse.
- **Attaques de monstres localisées** : `MonsterData.attack_zones` / `special_zones` = poids par partie du corps (lus comme des %).
  Zombie, Griffure : Tête 10, Torse 36, Bras 20/20, Jambes 7/7 ; Morsure : Tête 20, Torse 26, Bras 22/22, Jambes 5/5. Le message du journal
  donne la partie touchée. Les probabilités sont visibles en observant le monstre (survol ou mode regard) : `Monster.get_tooltip_lines()`.
- **Mode regard** (`LookUI`, touche `x`, ou `Maj` + pavé numérique / flèches depuis le monde) : la CAMÉRA se déplace, pas le joueur ; aucun temps
  ne passe (jeu en pause) ; rien n'est révélé (FOV et brouillard inchangés : `FogLayer.look_offset` étend seulement la zone dessinée). Un curseur
  surligne la case (calque de choix de case de `World`, `show_pick_overlay`), distance max 40 cases. Panneau à droite : case VISIBLE = biome,
  ville / lieu, terrain, mobilier, praticabilité, objets au sol, monstre (PV, coûts, probabilités de toucher) ; case VUE (mémoire) = terrain et
  mobilier seulement ; case JAMAIS VUE = rien. Dans le mode : pavé / flèches (avec ou sans Maj) déplacent le curseur, `5` recentre, `*` quitte le mode et lance le déplacement automatique vers la case ciblée (même système que le double-clic : `Player.travel_to`, case visible et praticable à pied requise), `+` / `-` zoom,
  `x` / Échap quittent (la caméra revient sur le joueur).

## À ajouter dans « Contrôles »
`x` ou `Maj` + pavé numérique / flèches = mode regard (voir ci-dessus). `c` = écran du personnage, onglets « Stats » et « Corps » (4 / 6 ou flèches
pour changer d'onglet) ; l'onglet Corps affiche une barre de vie par partie du corps.

## À ajouter dans « Architecture (scripts/) »
- `data/body_parts.json` + `data/body_part_db.gd` (`BodyPartDB`) : parties du corps, PV max, vital, tirage pondéré (`pick`), texte des probabilités (`zone_lines`).
- `ui/look_ui.gd` (`LookUI`) : mode regard. `worldgen/terrain_db.gd` : ajout de `name_of(index)`.
- `entities/player.gd` : `body`, `take_damage(montant, partie)`, `try_zoom()`, signal `look_requested` (EventBus).
- `tests/test_body.gd` : test des parties du corps et des zones des monstres.

## À ajouter dans « Limites connues »
- Membres à 0 PV sans effet ; pas de soin ni de régénération par partie ; PV max fixes (pas liés à la Force).
- Mode regard : sous Windows, `Maj` + pavé numérique avec VerrNum actif peut ne pas arriver comme « Maj enfoncé » (Windows simule un relâchement
  de Maj) ; dans ce cas utiliser `x`, puis le pavé sans Maj.
- Les objets et monstres hors de vue ne sont pas mémorisés : le mode regard n'en dit rien.
