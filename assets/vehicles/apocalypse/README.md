# apocalypse

Voiture post-apocalyptique, generee avec Tripo.

| | Brut | Dans le jeu |
|---|---|---|
| Poids | 21,5 Mo | **1,4 Mo** |
| Triangles | 683 000 | **34 172** |
| Longueur | 0,98 m | **4,20 m** |
| Avant | vers -X | **vers -Z** |
| Roues | noyees dans le maillage | **quatre objets animes** |

## Traitement applique

```bash
# 1. Separation des roues, sur le modele BRUT : la simplification soude des
#    sommets et rendrait la decoupe moins nette.
tools/split_wheels.py brut.glb separe.glb --forward=-X

# 2. Allegement : 683 000 -> 34 000 triangles, textures a 1024 px
gltf-transform simplify separe.glb e1.glb --ratio 0.04 --error 0.004
gltf-transform resize e1.glb e2.glb --width 1024 --height 1024
gltf-transform dedup e2.glb e3.glb && gltf-transform prune e3.glb propre.glb

# 3. Echelle, orientation, origine au sol, pivots de roues
tools/prepare_vehicle.py propre.glb apocalypse.glb --forward=-X
```

L'ordre compte : separer AVANT de simplifier.

## Structure obtenue

```
Body                    carrosserie, orientee et mise a l'echelle
WheelFL, WheelFR        pivots avant  — tournent et braquent
WheelRL, WheelRR        pivots arriere — tournent seulement
```

Chaque pivot est place au centre du moyeu et **sans rotation** : c'est lui que
le jeu fait tourner. La geometrie orientee est son enfant. Si le pivot portait
lui-meme la rotation du modele, ses axes ne seraient plus ceux du vehicule et
la roue tournerait de travers.

## Comment les roues ont ete retrouvees

Tripo avait decoupe le modele en huit morceaux suivant son atlas de textures
(`tripo_part_0` a `tripo_part_7`), et non par piece mecanique. Quatre de ces
morceaux contenaient une roue, dont deux la partageaient avec un essieu.

`tools/split_wheels.py` les a isoles par la geometrie : ilots relies par leurs
aretes, decoupes la ou la matiere se rarefie, puis tries sur leur forme — une
roue est basse, a peu pres aussi haute que longue, et nettement plus etroite.

Verification automatique : `tools/tests/visuals_test.tscn` mesure que les roues
tournent avec la vitesse, que seules celles de l'avant braquent, et dans le bon
sens.
