#!/usr/bin/env python3
"""Prepare un modele brut de vehicule pour le jeu.

    tools/prepare_vehicle.py entree.glb sortie.glb --forward -X

Applique en une passe ce qu'attend le jeu (voir assets/vehicles/README.md) :
  - mise a l'echelle pour obtenir une longueur realiste ;
  - rotation pour que l'avant pointe vers -Z, la convention de Godot ;
  - origine ramenee au sol, centree ;
  - regroupement sous un noeud nomme `Body`.

Les modeles generes par IA sortent presque toujours a une echelle arbitraire et
dans une orientation quelconque : corriger cela dans le fichier, une fois pour
toutes, evite de disperser des facteurs correctifs dans le code du jeu.

Dependances : pip install pygltflib numpy
"""

import argparse
import sys

import numpy as np
from pygltflib import GLTF2, Node

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from inspect_assets import node_matrix, mesh_bounds, walk

# Longueur cible d'une voiture, en metres.
DEFAULT_LENGTH = 4.20

# Rotation a appliquer autour de l'axe vertical selon la direction vers laquelle
# pointe actuellement l'avant du modele, pour l'amener sur -Z.
FORWARD_TO_YAW = {"-Z": 0.0, "+Z": 180.0, "-X": -90.0, "+X": 90.0}


def quaternion_y(degrees):
    """Quaternion glTF (x, y, z, w) pour une rotation autour de l'axe vertical."""
    half = np.radians(degrees) / 2.0
    return [0.0, float(np.sin(half)), 0.0, float(np.cos(half))]


def world_bounds(gltf):
    collected = []
    scene = gltf.scenes[gltf.scene or 0]
    for root in scene.nodes:
        walk(gltf, root, np.eye(4), collected)

    minimum = np.array([np.inf] * 3)
    maximum = np.array([-np.inf] * 3)
    for _node, world, mesh_index in collected:
        low, high = mesh_bounds(gltf, mesh_index)
        if not np.isfinite(low).all():
            continue
        for corner in np.array(np.meshgrid(*zip(low, high))).T.reshape(-1, 3):
            point = (world @ np.array([*corner, 1.0]))[:3]
            minimum = np.minimum(minimum, point)
            maximum = np.maximum(maximum, point)
    return minimum, maximum


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--forward", choices=sorted(FORWARD_TO_YAW),
                        default="-Z", help="axe vers lequel pointe l'avant du modele brut")
    parser.add_argument("--length", type=float, default=DEFAULT_LENGTH,
                        help="longueur voulue, en metres")
    parser.add_argument("--name", default="Body", help="nom du noeud racine")
    arguments = parser.parse_args()

    gltf = GLTF2().load(arguments.source)
    minimum, maximum = world_bounds(gltf)
    if not np.isfinite(minimum).all():
        print("Aucun maillage exploitable.", file=sys.stderr)
        return 1

    size = maximum - minimum
    # La longueur est portee par l'axe de l'avant : X si l'avant pointe en X.
    length_axis = 0 if arguments.forward in ("+X", "-X") else 2
    scale = arguments.length / size[length_axis]

    print(f"  dimensions d'origine  {size[0]:.3f} x {size[1]:.3f} x {size[2]:.3f} m")
    print(f"  facteur d'echelle     {scale:.4f}")
    print(f"  rotation appliquee    {FORWARD_TO_YAW[arguments.forward]:+.0f} degres "
          f"(avant {arguments.forward} -> -Z)")

    # Le modele est recentre horizontalement et pose au sol AVANT la mise a
    # l'echelle : la translation est donc exprimee dans l'echelle d'origine.
    centre = (minimum + maximum) / 2.0
    offset = [-float(centre[0]), -float(minimum[1]), -float(centre[2])]

    scene = gltf.scenes[gltf.scene or 0]

    # Noeud de recentrage, puis noeud `Body` qui porte echelle et rotation.
    centring = Node(name="_centring", translation=offset, children=list(scene.nodes))
    gltf.nodes.append(centring)
    centring_index = len(gltf.nodes) - 1

    body = Node(
        name=arguments.name,
        scale=[scale, scale, scale],
        rotation=quaternion_y(FORWARD_TO_YAW[arguments.forward]),
        children=[centring_index],
    )
    gltf.nodes.append(body)
    scene.nodes = [len(gltf.nodes) - 1]

    gltf.save(arguments.destination)

    check = GLTF2().load(arguments.destination)
    low, high = world_bounds(check)
    final = high - low
    print(f"  dimensions finales    {final[0]:.3f} x {final[1]:.3f} x {final[2]:.3f} m")
    print(f"  bas du modele a       {low[1]:+.3f} m")
    print(f"  ecrit dans            {arguments.destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
