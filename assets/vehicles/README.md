# Modeles de vehicules (.glb)

Ce dossier est **vide en phase 0** : la phase 0 n'utilise que des primitives Godot
(boites et cylindres) generees par le code.

## A partir de la phase 3

Depose ici les modeles exportes depuis Blender, un dossier par vehicule :

```
assets/vehicles/
├── coupe/
│   ├── coupe.glb
│   └── coupe.tres      # ressource VehicleModel (reglages propres a ce vehicule)
└── buggy/
    ├── buggy.glb
    └── buggy.tres
```

## Contraintes d'export attendues par le code

Le chargeur (`src/vehicle/vehicle_factory.gd`) cherche des noeuds nommes ainsi
dans le `.glb`. La carrosserie et les roues doivent etre des objets **separes** :

| Noeud dans le .glb | Role |
|---|---|
| `Body`            | carrosserie (maillage unique) |
| `WheelFL`         | roue avant gauche  (braque + tourne) |
| `WheelFR`         | roue avant droite  (braque + tourne) |
| `WheelRL`         | roue arriere gauche (tourne) |
| `WheelRR`         | roue arriere droite (tourne) |

- Origine du modele au **centre de la voiture, au niveau du sol**.
- Axe **-Z vers l'avant** (convention Godot).
- Origine de chaque roue **au centre de son moyeu**, sinon elle tournera de travers.
- Echelle : 1 unite Godot = 1 metre.
- Aucune marque ni modele de voiture reel.

Pour activer le chargement, il suffira de renseigner `model_path` dans la
ressource du vehicule : le code de repli en primitives reste en place.
