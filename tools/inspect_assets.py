#!/usr/bin/env python3
"""Inspecte les modeles deposes dans assets/raw/ et dit ce qu'il faut corriger.

    tools/inspect_assets.py                 inspecte tout assets/raw/
    tools/inspect_assets.py chemin.glb      inspecte un fichier precis

Le rapport repond aux questions qui decident du travail a faire :
l'echelle est-elle bonne, le modele regarde-t-il dans le bon sens, les roues
sont-elles des objets separes, le poids est-il tenable dans un navigateur.

Dependances : pip install pygltflib numpy
"""

import json
import struct
import sys
from pathlib import Path

try:
    import numpy as np
    from pygltflib import GLTF2
except ImportError:
    print("Dependances manquantes :  pip install pygltflib numpy", file=sys.stderr)
    sys.exit(2)

# --- Conventions du projet (voir assets/vehicles/README.md) -------------------

# Noms de noeuds attendus dans un modele de vehicule.
VEHICLE_NODES = ["Body", "WheelFL", "WheelFR", "WheelRL", "WheelRR"]

# Longueur plausible d'une voiture, en metres. Hors de cet intervalle,
# l'echelle du modele est certainement fausse.
CAR_LENGTH_RANGE = (2.5, 6.5)

# Au-dela, le modele est trop lourd pour douze voitures dans un navigateur.
TRIANGLE_BUDGET = 25_000

# Taille de texture raisonnable pour le web.
TEXTURE_SIZE_BUDGET = 1024

COMPONENT_SIZES = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def node_matrix(node):
    """Matrice locale d'un noeud glTF, depuis `matrix` ou translation/rotation/scale."""
    if node.matrix:
        # glTF stocke les matrices en colonnes.
        return np.array(node.matrix, dtype=float).reshape(4, 4).T

    matrix = np.eye(4)
    if node.scale:
        matrix = matrix @ np.diag([*node.scale, 1.0])
    if node.rotation:
        x, y, z, w = node.rotation
        rotation = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
            [0, 0, 0, 1],
        ])
        matrix = rotation @ matrix
    if node.translation:
        translation = np.eye(4)
        translation[:3, 3] = node.translation
        matrix = translation @ matrix
    return matrix


def mesh_bounds(gltf, mesh_index):
    """Boite englobante d'un maillage, lue dans les bornes des accesseurs."""
    minimum = np.array([np.inf] * 3)
    maximum = np.array([-np.inf] * 3)
    for primitive in gltf.meshes[mesh_index].primitives:
        position = primitive.attributes.POSITION
        if position is None:
            continue
        accessor = gltf.accessors[position]
        if accessor.min and accessor.max:
            minimum = np.minimum(minimum, accessor.min)
            maximum = np.maximum(maximum, accessor.max)
    return minimum, maximum


def triangle_count(gltf, mesh_index):
    total = 0
    for primitive in gltf.meshes[mesh_index].primitives:
        if primitive.indices is not None:
            total += gltf.accessors[primitive.indices].count // 3
        elif primitive.attributes.POSITION is not None:
            total += gltf.accessors[primitive.attributes.POSITION].count // 3
    return total


def walk(gltf, node_index, parent, collected):
    """Parcourt la hierarchie en cumulant les transformations."""
    node = gltf.nodes[node_index]
    world = parent @ node_matrix(node)
    if node.mesh is not None:
        collected.append((node, world, node.mesh))
    for child in node.children or []:
        walk(gltf, child, world, collected)


def world_bounds(gltf, collected):
    """Boite englobante de tout le modele, en coordonnees monde."""
    minimum = np.array([np.inf] * 3)
    maximum = np.array([-np.inf] * 3)
    for _node, world, mesh_index in collected:
        local_min, local_max = mesh_bounds(gltf, mesh_index)
        if not np.isfinite(local_min).all():
            continue
        # Les huit coins, pour que la rotation soit prise en compte.
        for corner in np.array(np.meshgrid(*zip(local_min, local_max))).T.reshape(-1, 3):
            point = (world @ np.array([*corner, 1.0]))[:3]
            minimum = np.minimum(minimum, point)
            maximum = np.maximum(maximum, point)
    return minimum, maximum


def texture_report(gltf, path):
    """Dimensions des images embarquees, lues dans leurs en-tetes."""
    report = []
    blob = None
    if path.suffix.lower() == ".glb":
        blob = gltf.binary_blob()

    for image in gltf.images or []:
        size = None
        if image.bufferView is not None and blob is not None:
            view = gltf.bufferViews[image.bufferView]
            data = blob[view.byteOffset or 0:(view.byteOffset or 0) + view.byteLength]
            size = image_size(data)
        report.append((image.name or image.mimeType or "image", size))
    return report


def image_size(data):
    """Dimensions d'un PNG ou d'un JPEG, sans decoder l'image."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        width, height = struct.unpack(">II", data[16:24])
        return width, height
    if data[:2] == b"\xff\xd8":
        offset = 2
        while offset < len(data) - 9:
            if data[offset] != 0xFF:
                offset += 1
                continue
            marker = data[offset + 1]
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                height, width = struct.unpack(">HH", data[offset + 5:offset + 9])
                return width, height
            offset += 2 + struct.unpack(">H", data[offset + 2:offset + 4])[0]
    return None


def inspect(path):
    print(f"\n{'=' * 70}\n{path.name}\n{'=' * 70}")
    size_mb = path.stat().st_size / 1e6
    print(f"  Poids            {size_mb:.1f} Mo")

    try:
        gltf = GLTF2().load(str(path))
    except Exception as error:
        print(f"  ILLISIBLE : {error}")
        return ["Fichier illisible : verifier qu'il s'agit bien d'un glTF valide."]

    collected = []
    scene = gltf.scenes[gltf.scene or 0] if gltf.scenes else None
    for root in (scene.nodes if scene else range(len(gltf.nodes or []))):
        walk(gltf, root, np.eye(4), collected)

    triangles = sum(triangle_count(gltf, index) for _n, _w, index in collected)
    print(f"  Objets           {len(collected)}")
    print(f"  Triangles        {triangles:,}".replace(",", " "))
    print(f"  Materiaux        {len(gltf.materials or [])}")

    textures = texture_report(gltf, path)
    if textures:
        for name, size in textures:
            dimensions = f"{size[0]}x{size[1]}" if size else "taille inconnue"
            print(f"  Texture          {name} ({dimensions})")

    minimum, maximum = world_bounds(gltf, collected)
    problems = []

    if np.isfinite(minimum).all():
        dimensions = maximum - minimum
        print(f"  Dimensions       {dimensions[0]:.2f} x {dimensions[1]:.2f} x {dimensions[2]:.2f} m"
              f"  (largeur x hauteur x longueur)")
        print(f"  Origine en Y     {minimum[1]:+.2f} m sous le modele")

        length = max(dimensions[0], dimensions[2])
        if not CAR_LENGTH_RANGE[0] <= length <= CAR_LENGTH_RANGE[1]:
            factor = 4.2 / length if length > 0 else 1.0
            problems.append(
                f"Echelle a corriger : {length:.2f} m de long. Une voiture fait "
                f"environ 4,2 m. Facteur a appliquer : {factor:.3f}")
        if dimensions[0] > dimensions[2]:
            problems.append(
                "Orientation a corriger : le modele est plus large que long. "
                "L'avant doit pointer vers -Z.")
        if abs(minimum[1]) > 0.15:
            problems.append(
                f"Origine a corriger : le bas du modele est a {minimum[1]:+.2f} m "
                "au lieu de 0. L'origine doit etre au sol, centree.")

    # Noms des noeuds : c'est ce qui permet d'animer les roues.
    names = [node.name for node, _w, _m in collected if node.name]
    print(f"  Noms des objets  {', '.join(names[:8]) if names else '(aucun)'}"
          + (" ..." if len(names) > 8 else ""))

    missing = [expected for expected in VEHICLE_NODES if expected not in names]
    if missing == VEHICLE_NODES:
        problems.append(
            "Aucun objet nomme Body / WheelFL / WheelFR / WheelRL / WheelRR. "
            "Si ce modele est une voiture, les roues ne pourront ni tourner ni "
            "braquer tant qu'elles ne sont pas des objets SEPARES portant ces "
            "noms (voir assets/vehicles/README.md).")
    elif missing:
        problems.append(f"Objets manquants : {', '.join(missing)}")

    if len(collected) == 1:
        problems.append(
            "Le modele ne contient qu'un seul objet : carrosserie et roues sont "
            "fusionnees. Il faut les separer dans Blender pour pouvoir animer "
            "les roues.")

    if triangles > TRIANGLE_BUDGET:
        problems.append(
            f"{triangles:,} triangles".replace(",", " ") +
            f" : au-dela de {TRIANGLE_BUDGET:,} ".replace(",", " ") +
            "par voiture, douze voitures a l'ecran deviennent lourdes dans un "
            "navigateur. Simplification recommandee.")

    for name, size in textures:
        if size and max(size) > TEXTURE_SIZE_BUDGET:
            problems.append(
                f"Texture {name} en {size[0]}x{size[1]} : "
                f"{TEXTURE_SIZE_BUDGET}x{TEXTURE_SIZE_BUDGET} suffit pour le web "
                "et allege nettement le telechargement.")

    print()
    if problems:
        print("  A CORRIGER")
        for problem in problems:
            print(f"    - {problem}")
    else:
        print("  Rien a signaler : le modele respecte les conventions du projet.")
    return problems


def main():
    targets = []
    if len(sys.argv) > 1:
        targets = [Path(argument) for argument in sys.argv[1:]]
    else:
        raw = Path(__file__).resolve().parent.parent / "assets" / "raw"
        targets = sorted(
            path for path in raw.rglob("*")
            if path.suffix.lower() in (".glb", ".gltf"))

    if not targets:
        print("Aucun modele dans assets/raw/.")
        print("Depose tes fichiers dans assets/raw/vehicles/ ou assets/raw/tracks/,")
        print("puis relance cette commande.")
        return 0

    total = 0
    for path in targets:
        if not path.exists():
            print(f"Introuvable : {path}", file=sys.stderr)
            continue
        total += len(inspect(path))

    print(f"\n{'=' * 70}")
    print(f"{len(targets)} modele(s) inspecte(s), {total} point(s) a corriger.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
