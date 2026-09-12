# apocalypse

Voiture post-apocalyptique, generee avec Tripo.

| | |
|---|---|
| Source | `assets/raw/vehicles/post apocalyptic car 3d model.glb` (21,5 Mo) |
| Modele prepare | `apocalypse.glb` (1,2 Mo) |
| Dimensions | 1,87 x 1,65 x 4,20 m |
| Triangles | 26 664 (683 000 a l'origine) |

## Traitement applique

```bash
# 1. Simplification : 683 000 -> 26 664 triangles
gltf-transform simplify brut.glb etape1.glb --ratio 0.035 --error 0.005
# 2. Textures ramenees a 1024 px
gltf-transform resize etape1.glb etape2.glb --width 1024 --height 1024
# 3. Doublons et donnees inutilisees
gltf-transform dedup etape2.glb etape3.glb && gltf-transform prune etape3.glb propre.glb
# 4. Echelle, orientation, origine, noeud Body
tools/prepare_vehicle.py propre.glb apocalypse.glb --forward=-X
```

Le modele brut mesurait 0,98 m et pointait vers -X. Il a ete agrandi d'un
facteur 4,279 et pivote de -90 degres.

## Limite connue : les roues ne tournent pas

Tripo a decoupe le modele en huit morceaux suivant son atlas de textures
(`tripo_part_0` a `tripo_part_7`), et non par piece mecanique : carrosserie et
roues appartiennent aux memes maillages.

Consequence : les roues sont bien visibles, mais elles ne peuvent ni tourner ni
braquer. Rien d'autre n'en souffre — la conduite, le reseau et les collisions
sont inchanges, puisqu'ils ne dependent que de la boite de collision.

Pour les animer, il faudra separer les roues de la carrosserie dans Blender et
les nommer `WheelFL`, `WheelFR`, `WheelRL`, `WheelRR`, origine au centre du
moyeu (voir `../README.md`). Le code les prendra alors automatiquement en
charge : `VehicleFactory.load_model()` les cherche deja.
