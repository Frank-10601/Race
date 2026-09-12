#!/usr/bin/env python3
"""Separe les roues d'un modele de vehicule livre d'un seul tenant.

    tools/split_wheels.py entree.glb sortie.glb --forward=-X
    tools/split_wheels.py entree.glb --report-only --forward=-X

Les generateurs 3D par IA livrent la voiture en un bloc, ou decoupee selon leur
atlas de textures. Les roues sont alors bien modelisees mais noyees dans le
maillage : impossible de les faire tourner ou braquer.

Methode, en trois temps :

1. ILOTS — les triangles relies entre eux par une arete forment un ilot. Une
   roue est presque toujours un ilot distinct, meme au sein d'une primitive
   partagee. Les sommets de meme position sont d'abord soudes : un exporteur
   les duplique souvent pour porter des coordonnees de texture differentes, ce
   qui couperait artificiellement l'ilot en morceaux.

2. DECOUPE — un ilot peut reunir une roue et une piece voisine (un essieu, par
   exemple). On cherche alors un etranglement dans la repartition des triangles
   le long de la largeur : la ou la matiere se rarefie, on coupe.

3. TRI — parmi les morceaux, une roue se reconnait a sa forme : a peu pres aussi
   haute que longue, nettement plus etroite, et situee en bas. Les quatre plus
   gros morceaux repondant a ces criteres sont les roues ; leur position donne
   leur nom (avant/arriere, gauche/droite).

La geometrie de chaque roue est enfin recentree sur son moyeu — sans quoi elle
tournerait autour d'un point arbitraire, ce qui est pire qu'une roue immobile.

Dependances : pip install pygltflib numpy scipy
"""

import argparse
import copy
import sys
from pathlib import Path

import numpy as np
from pygltflib import (GLTF2, Accessor, Attributes, Buffer, BufferView, Mesh,
                       Node, Primitive, Scene)
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

sys.path.insert(0, str(Path(__file__).resolve().parent))
from inspect_assets import walk, TYPE_COUNTS

# Une roue se situe sous cette fraction de la hauteur du vehicule.
WHEEL_HEIGHT_LIMIT = 0.70
# Rapport hauteur / longueur tolere pour une roue vue de profil.
WHEEL_ASPECT_RANGE = (0.55, 1.9)
# Une roue est plus etroite que haute.
WHEEL_MAX_WIDTH_RATIO = 1.15
# Un morceau doit peser au moins cette part du modele pour etre considere.
MIN_SHARE = 0.01
# Un creux sous cette fraction du pic marque une separation entre deux pieces.
VALLEY_THRESHOLD = 0.18
# Nombre de tranches utilisees pour reperer les etranglements.
SLICE_COUNT = 48

DTYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16,
          5123: np.uint16, 5125: np.uint32, 5126: np.float32}


def read_accessor(gltf, blob, index):
	accessor = gltf.accessors[index]
	view = gltf.bufferViews[accessor.bufferView]
	count = TYPE_COUNTS[accessor.type]
	start = (view.byteOffset or 0) + (accessor.byteOffset or 0)
	data = np.frombuffer(blob, dtype=DTYPES[accessor.componentType],
	                     count=accessor.count * count, offset=start)
	return data.reshape(accessor.count, count) if count > 1 else data


def load_parts(path):
	"""Toutes les primitives du modele, ramenees en coordonnees monde."""
	gltf = GLTF2().load(path)
	blob = gltf.binary_blob()
	collected = []
	scene = gltf.scenes[gltf.scene or 0]
	for root in scene.nodes:
		walk(gltf, root, np.eye(4), collected)

	parts = []
	for _node, world, mesh_index in collected:
		for primitive in gltf.meshes[mesh_index].primitives:
			if primitive.indices is None or primitive.attributes.POSITION is None:
				continue
			indices = read_accessor(gltf, blob, primitive.indices).astype(np.int64).reshape(-1, 3)
			positions = read_accessor(gltf, blob, primitive.attributes.POSITION).astype(np.float64)
			world_positions = (world @ np.c_[positions, np.ones(len(positions))].T).T[:, :3]
			normals = None
			if primitive.attributes.NORMAL is not None:
				raw = read_accessor(gltf, blob, primitive.attributes.NORMAL).astype(np.float64)
				normals = (world[:3, :3] @ raw.T).T
				lengths = np.linalg.norm(normals, axis=1, keepdims=True)
				normals = normals / np.where(lengths > 0, lengths, 1.0)
			uvs = None
			if primitive.attributes.TEXCOORD_0 is not None:
				uvs = read_accessor(gltf, blob, primitive.attributes.TEXCOORD_0).astype(np.float32)
			parts.append({
				"indices": indices,
				"positions": world_positions.astype(np.float32),
				"normals": None if normals is None else normals.astype(np.float32),
				"uvs": uvs,
				"material": primitive.material,
			})
	return gltf, parts


def islands_of(part):
	"""Indices de triangles regroupes par ilot connexe."""
	indices = part["indices"]
	positions = part["positions"]
	rounded = np.round(positions.astype(np.float64), 5)
	_unique, welded = np.unique(rounded, axis=0, return_inverse=True)
	welded_indices = welded[indices]

	edges = np.vstack([welded_indices[:, [0, 1]],
	                   welded_indices[:, [1, 2]],
	                   welded_indices[:, [2, 0]]])
	size = int(welded.max()) + 1
	graph = coo_matrix((np.ones(len(edges)), (edges[:, 0], edges[:, 1])), shape=(size, size))
	_count, labels = connected_components(graph, directed=False)

	triangle_labels = labels[welded_indices[:, 0]]
	groups = []
	for label in np.unique(triangle_labels):
		groups.append(np.flatnonzero(triangle_labels == label))
	return groups


def split_at_valleys(centres, triangle_indices, axis):
	"""Coupe un groupe la ou la matiere se rarefie le long d'un axe."""
	values = centres[triangle_indices, axis]
	low, high = values.min(), values.max()
	if high - low < 1e-6:
		return [triangle_indices]

	counts, edges = np.histogram(values, bins=SLICE_COUNT, range=(low, high))
	peak = counts.max()
	if peak == 0:
		return [triangle_indices]

	# Une tranche presque vide separe deux pieces distinctes.
	empty = counts < peak * VALLEY_THRESHOLD
	pieces, start = [], 0
	for index in range(1, SLICE_COUNT):
		if empty[index] and not empty[index - 1] and index > start:
			boundary = edges[index]
			mask = (values >= edges[start]) & (values < boundary)
			if mask.any():
				pieces.append(triangle_indices[mask])
			start = index
	mask = values >= edges[start]
	if mask.any():
		pieces.append(triangle_indices[mask])
	return pieces if len(pieces) > 1 else [triangle_indices]


def bounds_of(centres, triangle_indices):
	points = centres[triangle_indices]
	return points.min(axis=0), points.max(axis=0)


def looks_like_wheel(extent, forward_axis, side_axis):
	length, height, width = extent[forward_axis], extent[1], extent[side_axis]
	if length <= 1e-6 or height <= 1e-6:
		return False
	aspect = height / length
	return (WHEEL_ASPECT_RANGE[0] <= aspect <= WHEEL_ASPECT_RANGE[1]
	        and width / height <= WHEEL_MAX_WIDTH_RATIO)


def find_wheels(parts, forward_axis, side_axis, verbose=True):
	all_centres = np.vstack([p["positions"][p["indices"]].mean(axis=1) for p in parts])
	low, high = all_centres.min(axis=0), all_centres.max(axis=0)
	height = high[1] - low[1]
	ceiling = low[1] + height * WHEEL_HEIGHT_LIMIT
	total = sum(len(p["indices"]) for p in parts)

	if verbose:
		print(f"  vehicule : {high[0]-low[0]:.3f} x {height:.3f} x {high[2]-low[2]:.3f} m")
		print(f"  roues recherchees sous {ceiling:.3f} m")

	candidates = []
	for part_index, part in enumerate(parts):
		centres = part["positions"][part["indices"]].mean(axis=1)
		for island in islands_of(part):
			for piece in split_at_valleys(centres, island, side_axis):
				if len(piece) < total * MIN_SHARE:
					continue
				piece_low, piece_high = bounds_of(centres, piece)
				if piece_high[1] > ceiling:
					continue
				extent = piece_high - piece_low
				if not looks_like_wheel(extent, forward_axis, side_axis):
					continue
				candidates.append({
					"part": part_index,
					"triangles": piece,
					"low": piece_low,
					"high": piece_high,
					"centre": (piece_low + piece_high) / 2,
					"count": len(piece),
				})

	candidates.sort(key=lambda c: -c["count"])
	if verbose:
		print(f"  {len(candidates)} morceau(x) en forme de roue :")
		for candidate in candidates[:8]:
			extent = candidate["high"] - candidate["low"]
			centre = candidate["centre"]
			print(f"    {candidate['count']:>7} triangles   "
			      f"{extent[0]:.3f} x {extent[1]:.3f} x {extent[2]:.3f}   "
			      f"centre {centre[0]:+.3f} {centre[1]:+.3f} {centre[2]:+.3f}")
	return candidates[:4], (low, high)


def name_wheels(wheels, bounds, forward_axis, side_axis, forward_sign, left_is_positive):
	low, high = bounds
	middle_forward = (low[forward_axis] + high[forward_axis]) / 2
	middle_side = np.mean([w["centre"][side_axis] for w in wheels])
	for wheel in wheels:
		ahead = (wheel["centre"][forward_axis] - middle_forward) * forward_sign > 0
		side = wheel["centre"][side_axis] - middle_side
		left = side > 0 if left_is_positive else side < 0
		wheel["name"] = "Wheel" + ("F" if ahead else "R") + ("L" if left else "R")
	return wheels


def build_gltf(parts, wheels, destination, source_gltf, source_blob):
	"""Ecrit un glTF ou chaque roue est un noeud distinct, centre sur son moyeu.

	Materiaux, textures et images sont repris du modele d'origine : sans eux le
	vehicule ressortirait entierement gris.
	"""
	assignment = {}
	for wheel in wheels:
		for triangle in wheel["triangles"]:
			assignment[(wheel["part"], int(triangle))] = wheel["name"]

	# Un groupe par (nom de noeud, materiau) : une primitive ne porte qu'un materiau.
	groups = {}
	for part_index, part in enumerate(parts):
		for triangle_index in range(len(part["indices"])):
			name = assignment.get((part_index, triangle_index), "Body")
			key = (name, part["material"])
			groups.setdefault(key, []).append((part_index, triangle_index))

	origins = {wheel["name"]: wheel["centre"] for wheel in wheels}
	origins["Body"] = np.zeros(3)

	gltf = GLTF2()
	gltf.scenes = [Scene(nodes=[])]
	gltf.scene = 0
	blob = bytearray()
	views, accessors, meshes, nodes = [], [], [], []

	def add_view(data, target):
		offset = len(blob)
		blob.extend(data)
		while len(blob) % 4:
			blob.append(0)
		views.append(BufferView(buffer=0, byteOffset=offset,
		                        byteLength=len(data), target=target))
		return len(views) - 1

	# Apparence : materiaux, textures et echantillonneurs sont repris tels
	# quels ; seules les images demandent un travail, leurs octets vivant dans
	# le tampon binaire du fichier d'origine.
	gltf.materials = source_gltf.materials or []
	gltf.textures = source_gltf.textures or []
	gltf.samplers = source_gltf.samplers or []
	gltf.images = []
	for image in (source_gltf.images or []):
		copied = copy.deepcopy(image)
		if image.bufferView is not None:
			view = source_gltf.bufferViews[image.bufferView]
			start = view.byteOffset or 0
			copied.bufferView = add_view(
				bytes(source_blob[start:start + view.byteLength]), None)
			copied.uri = None
		gltf.images.append(copied)

	by_node = {}
	for (name, material), members in sorted(groups.items(), key=lambda kv: str(kv[0])):
		positions, normals, uvs, indices = [], [], [], []
		lookup = {}
		origin = origins[name]
		for part_index, triangle_index in members:
			part = parts[part_index]
			for vertex in part["indices"][triangle_index]:
				key = (part_index, int(vertex))
				if key not in lookup:
					lookup[key] = len(positions)
					positions.append(part["positions"][vertex] - origin)
					if part["normals"] is not None:
						normals.append(part["normals"][vertex])
					if part["uvs"] is not None:
						uvs.append(part["uvs"][vertex])
				indices.append(lookup[key])

		positions = np.asarray(positions, dtype=np.float32)
		indices = np.asarray(indices, dtype=np.uint32)
		attributes = Attributes()

		view = add_view(positions.tobytes(), 34962)
		accessors.append(Accessor(bufferView=view, componentType=5126,
		                          count=len(positions), type="VEC3",
		                          min=positions.min(axis=0).tolist(),
		                          max=positions.max(axis=0).tolist()))
		attributes.POSITION = len(accessors) - 1

		if len(normals) == len(positions):
			array = np.asarray(normals, dtype=np.float32)
			view = add_view(array.tobytes(), 34962)
			accessors.append(Accessor(bufferView=view, componentType=5126,
			                          count=len(array), type="VEC3"))
			attributes.NORMAL = len(accessors) - 1
		if len(uvs) == len(positions):
			array = np.asarray(uvs, dtype=np.float32)
			view = add_view(array.tobytes(), 34962)
			accessors.append(Accessor(bufferView=view, componentType=5126,
			                          count=len(array), type="VEC2"))
			attributes.TEXCOORD_0 = len(accessors) - 1

		view = add_view(indices.tobytes(), 34963)
		accessors.append(Accessor(bufferView=view, componentType=5125,
		                          count=len(indices), type="SCALAR"))
		primitive = Primitive(attributes=attributes, indices=len(accessors) - 1,
		                      material=material)
		by_node.setdefault(name, []).append(primitive)

	for name, primitives in by_node.items():
		meshes.append(Mesh(primitives=primitives, name=name + "_mesh"))
		nodes.append(Node(name=name, mesh=len(meshes) - 1,
		                  translation=origins[name].tolist()))
		gltf.scenes[0].nodes.append(len(nodes) - 1)

	gltf.bufferViews = views
	gltf.accessors = accessors
	gltf.meshes = meshes
	gltf.nodes = nodes
	gltf.buffers = [Buffer(byteLength=len(blob))]
	gltf.set_binary_blob(bytes(blob))
	gltf.save(destination)
	return by_node


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("source")
	parser.add_argument("destination", nargs="?")
	parser.add_argument("--forward", choices=["+X", "-X", "+Z", "-Z"], default="-Z")
	parser.add_argument("--report-only", action="store_true")
	arguments = parser.parse_args()

	source_gltf, parts = load_parts(arguments.source)
	source_blob = source_gltf.binary_blob()
	forward_axis = 0 if arguments.forward in ("+X", "-X") else 2
	side_axis = 2 if forward_axis == 0 else 0
	forward_sign = -1.0 if arguments.forward.startswith("-") else 1.0
	# Apres reorientation vers -Z, la gauche du conducteur correspond a X negatif.
	left_is_positive = arguments.forward in ("-X", "+Z")

	wheels, bounds = find_wheels(parts, forward_axis, side_axis)
	if len(wheels) < 4:
		print("\n  Moins de quatre roues trouvees : modele laisse tel quel.", file=sys.stderr)
		return 1

	name_wheels(wheels, bounds, forward_axis, side_axis, forward_sign, left_is_positive)
	names = sorted(w["name"] for w in wheels)
	print(f"\n  roues : {', '.join(names)}")
	if len(set(names)) != 4:
		print("  Les quatre roues n'ont pas pu etre distinguees.", file=sys.stderr)
		return 1

	if arguments.report_only or not arguments.destination:
		return 0

	by_node = build_gltf(parts, wheels, arguments.destination, source_gltf, source_blob)
	print(f"  noeuds ecrits : {', '.join(sorted(by_node))}")
	print(f"  ecrit dans {arguments.destination}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
