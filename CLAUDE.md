# Race — jeu de course arcade 3D multijoueur

Document de reference du projet. A lire avant toute modification.

---

## 1. Vision du jeu

Jeu de course **arcade** en 3D, Godot 4 + GDScript.

- **Conduite arcade, pas simulation.** Facile a prendre en main, derapages
  controles et amusants, vitesse ressentie elevee. Pas de boite de vitesses
  manuelle, pas de physique de pneus realiste. **La voiture doit etre amusante
  avant d'etre realiste.**
- **Circuits fermes** a plusieurs tours, avec points de passage, compteur de
  tours, chronometre et classement.
- **Multijoueur en ligne**, plusieurs joueurs sur le meme circuit en temps reel.
- **Style visuel** : vehicules stylises aux formes arrondies et lisibles,
  peinture usee, **aucune marque ni modele reel**. Modeles generes par IA
  (Meshy/Tripo), nettoyes dans Blender, exportes en `.glb`. Les roues sont des
  objets **separes** de la carrosserie, pour tourner et braquer.
- **Prevu plus tard** : plusieurs circuits, plusieurs voitures aux comportements
  differents, degats visuels, bonus de vitesse, contre-la-montre avec fantome,
  mode championnat.

### Plan des phases

| Phase | Contenu | Etat |
|---|---|---|
| **0** | Base technique : piste de test, une voiture pilotable, deux joueurs connectes, test web | **en cours** |
| 1 | Circuit complet : trace ferme, points de passage, tours, chronometre | a venir |
| 2 | Course : depart compte, classement en direct, arrivee, ecran de resultats | a venir |
| 3 | Voitures : plusieurs modeles `.glb`, reglages differents, roues separees animees | a venir |
| 4 | Ressenti : camera dynamique, effets de vitesse, poussiere, traces, sons | a venir |
| 5 | Collisions entre joueurs et remise en piste automatique | a venir |

---

## 2. Contraintes non negociables

1. **Serveur autoritaire des la premiere ligne.** Le serveur simule la physique
   des vehicules. Le client envoie **uniquement ses entrees** (accelerer,
   freiner, tourner, frein a main) et affiche le resultat.
   **Le client n'envoie JAMAIS sa position.**
2. **Trois modes de lancement** : hote (joue et heberge), serveur dedie sans
   affichage (headless, en ligne de commande), client web (navigateur).
3. **Code modulaire**, dossiers separes : reseau, vehicule, circuit, interface,
   et un dossier pour les systemes futurs.
4. **Aucun asset externe en phase 0.** Uniquement des primitives Godot (boites,
   cylindres) avec des materiaux de couleur unie. Le dossier
   `assets/vehicles/` et le chargement `.glb` sont prepares pour la phase 3,
   carrosserie et roues en objets distincts.
5. **GDScript type statiquement partout.**
6. **Tous les reglages dans un seul fichier** : `src/config/tuning.cfg`
   (acceleration, vitesse maximale, adherence, force de derapage, freinage,
   gravite, taux reseau). Modifier le ressenti ne doit jamais demander de
   toucher au code.
7. **Prevoir sans implementer** : l'architecture doit permettre plus tard
   plusieurs circuits, plusieurs modeles de voitures et **jusqu'a 12 joueurs**
   par course. Ne pas coder ces systemes maintenant, mais ne faire aucun choix
   qui les empecherait.

---

## 3. Decisions d'architecture

### 3.1 Physique du vehicule : personnalisee, pas `VehicleBody3D`

`VehicleBody3D` a ete ecarte pour une raison **reseau**, pas esthetique.

La prediction cote client impose de rejouer 9 a 18 pas de simulation dans une
seule frame quand l'etat serveur arrive. Cela demande (a) un etat entierement
serialisable et (b) de pouvoir avancer la simulation a la demande.
`VehicleBody3D` echoue sur les deux : son etat interne (compression de
suspension, rotation de chaque roue, impulsions du solveur) vit dans le moteur
physique et n'est ni lisible ni reinjectable, et Godot n'expose aucune API pour
avancer `PhysicsServer3D` manuellement. Sans cela, pas de reconciliation ; sans
reconciliation, la direction accuse la latence.

S'ajoutent : un modele arcade se regle directement (un reglage = un effet
ressenti), et le cout CPU est un ordre de grandeur plus faible — ce qui compte
quand le serveur simule 12 voitures a 60 Hz et que le client web tourne en
WebAssembly mono-thread.

**Modele retenu** (`src/vehicle/vehicle_physics.gd`) :

1. **Sol** : 4 raycasts (un par coin) → hauteur et normale moyenne.
2. **Vitesse avant** : scalaire, acceleration / frein / trainee / vitesse max.
3. **Braquage** : agit sur le lacet, attenue a haute vitesse.
4. **Adherence** : le vecteur vitesse rattrape l'axe avant de la voiture.
   `grip = 1` → sur rails, `grip = 0.1` → patinoire. **Coeur du ressenti.**
5. **Frein a main** : effondre l'adherence laterale, ajoute du lacet, puis
   retour progressif en adherence.
6. **Murs** : `move_and_collide` avec glissement.

> **Determinisme** : la seule dependance du replay au monde exterieur est la
> piste, qui est **statique**. Rejouer N pas donne donc exactement le meme
> resultat sur le client et sur le serveur. Toute l'architecture reseau repose
> sur cette propriete — **ne jamais introduire de dependance dynamique dans
> `vehicle_physics.gd`** (pas de `randf()`, pas de lecture d'un autre vehicule,
> pas de `Time.get_ticks_msec()`).

### 3.2 Reseau

**Transport interchangeable**, interface `NetworkTransport` :
`WebSocketTransport` par defaut (seul transport utilisable par un client web),
`ENetTransport` en option pour le bureau (`--transport enet`). Un serveur Godot
n'ecoute qu'avec **un seul transport a la fois**.

**Consequence du TCP** : aucune sur la voiture locale (la prediction la rend
insensible a la latence) ; sur les autres voitures, le blocage de tete de file
peut creer un trou, absorbe par le tampon d'interpolation de 100 ms.

**Boucle** :

```
CLIENT (60 Hz)                         SERVEUR (60 Hz)
1. echantillonne l'entree → seq N
2. envoie {seq N, entree}        ───►  file par joueur (tampon anti-gigue)
3. APPLIQUE IMMEDIATEMENT              consomme 1 entree/tick, simule
4. historise (seq, entree, etat)       memorise last_seq[joueur]
                                 ◄───  DIFFUSE A 20 Hz : etat de chaque
                                       voiture + last_seq du destinataire
5. RECONCILIATION (voiture locale) :
   ecart = |etat_serveur − historique[last_seq]|
   • sous le seuil → ne rien faire
   • sinon → repartir de l'etat serveur, rejouer les entrees ]last_seq … N]
6. LISSAGE : l'ecart est reporte sur le noeud VISUEL et resorbe en ~120 ms
```

> **Regle** : on corrige la **simulation d'un coup**, l'**image progressivement**.
> Le corps de collision est a la bonne place immediatement ; la carrosserie le
> rejoint sans que l'oeil percoive un saut.

**Autres joueurs** : buffer d'instantanes horodates, rendus a
`temps_serveur − 100 ms`, interpolation **cubique de Hermite** (position +
vitesse — le lineaire coupe les virages en cordes visibles a 20 Hz), `slerp`
pour l'orientation.

**Coherence des reglages** : le serveur **envoie `tuning.cfg` au client a la
connexion**. Une seule source de verite ; sinon le client predit avec des
valeurs differentes et se fait corriger a chaque paquet.

---

## 4. Conventions de code

### Langue

- **Code en anglais** : noms de fichiers, variables, fonctions, classes, signaux.
- **Commentaires en francais**, ainsi que la documentation et les messages de
  commit.
- **Texte affiche a l'ecran en francais.**

### Style GDScript

- **Typage statique obligatoire, partout.** Variables, parametres, retours.
  `var speed: float = 0.0`, `func step(state: VehicleState) -> VehicleState:`.
  Jamais de `var x = ...` non type. Les avertissements de typage sont actifs
  dans `project.godot` — **le projet doit compiler sans aucun avertissement**.
- `class_name` en `PascalCase`, fichiers en `snake_case.gd`.
- Fonctions et variables en `snake_case`, constantes en `SCREAMING_SNAKE_CASE`.
- Membres prives prefixes d'un `_`.
- Ordre dans un fichier : `class_name` → `extends` → docstring → signaux →
  constantes → `@export` → variables publiques → variables privees →
  `_ready`/`_process` → methodes publiques → methodes privees.
- Preferer les signaux aux appels directs entre systemes eloignes.
- Aucune valeur de reglage en dur dans le code : tout passe par `Tuning`.

### Reseau

- Tout RPC est annote explicitement :
  `@rpc("any_peer", "call_remote", "unreliable_ordered", 0)`.
- Les RPC recus cote serveur **valident systematiquement l'emetteur**
  (`multiplayer.get_remote_sender_id()`).
- Aucune donnee de position ne remonte du client vers le serveur.

### Git

- Un commit par etape fonctionnelle, message en francais, a l'imperatif.
  Exemple : `Ajoute la piste de test et le materiau de reperes au sol`.

---

## 5. Hors perimetre de la phase 0

Pas de tours, chronometre, classement, depart compte, circuits multiples,
modeles de voitures multiples, degats, bonus, sons, ni assets externes.
Toute idee utile pour plus tard va dans `docs/NOTES.md`, **sans etre codee**.
