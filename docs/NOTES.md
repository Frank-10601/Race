# Notes, decisions et idees reportees

Journal du projet. Les idees notees ici ne sont **pas** codees : elles attendent
leur phase.

---

## Decisions prises

### Physique du vehicule — personnalisee (phase 0)

`VehicleBody3D` ecarte. Motif principal : la reconciliation cote client exige
un etat serialisable et la possibilite d'avancer la simulation a la demande ;
`VehicleBody3D` n'offre ni l'un ni l'autre (etat de suspension et de roues
enferme dans le moteur physique, pas d'API de pas manuel sur `PhysicsServer3D`).
Motifs secondaires : reglage arcade direct, cout CPU bien plus faible pour le
serveur (12 voitures a 60 Hz) et pour le navigateur (WebAssembly mono-thread).

Cout accepte : les collisions entre joueurs devront etre ecrites a la main en
phase 5. Ce n'est pas une perte : une resolution arcade a base d'impulsions
simples est plus previsible et plus agreable qu'une resolution rigide realiste.

### Transport reseau — WebSocket par defaut, ENet en option (phase 0)

WebSocket est le seul transport utilisable depuis un navigateur. ENet reste
disponible en ligne de commande pour comparer la latence sur bureau.

### Rendu — `gl_compatibility` partout (phase 0)

Forward+ ne tourne pas en WebGL2. Utiliser le meme moteur de rendu sur bureau et
sur web evite les ecarts visuels et les surprises de performance. A reconsiderer
si WebGPU devient exploitable dans Godot.

### Gravite

`physics/3d/default_gravity = 0` dans `project.godot` : le vehicule applique sa
propre gravite, lue dans `tuning.cfg`. Une seule source de verite. Si un
`RigidBody3D` est ajoute plus tard, il faudra lui donner sa gravite explicitement.

---

## Limites connues de la phase 0

- **Un seul transport a la fois cote serveur.** Une `MultiplayerAPI` racine ne
  porte qu'un `MultiplayerPeer`. Faire ecouter WebSocket **et** ENet simultanement
  demanderait deux `MultiplayerAPI` sur deux sous-arbres distincts
  (`get_tree().set_multiplayer()`), avec deux arbres de vehicules a synchroniser.
  Reportable tant que le WebSocket suffit aux deux publics.
- **L'hote est avantage** : 0 ms de latence pour lui, pas pour les autres.
  Inherent au mode hote. Le serveur dedie est la reponse propre pour une course
  serieuse.
- **Pas de validation des entrees.** Un client modifie peut envoyer « accelerer »
  en permanence. Sans consequence en phase 0 (aucun classement), a traiter avant
  tout mode competitif : borner les valeurs recues et limiter le debit d'entrees.
- **Pas de correction de la derive d'horloge.** `net_clock.gd` estime le decalage
  a la connexion puis le lisse ; une derive lente est possible sur une longue
  session. A surveiller en phase 2 (chronometrage).

---

## Idees pour plus tard

### Reseau

- **WebRTC (`WebRTCMultiplayerPeer`)** : la vraie reponse « UDP dans le
  navigateur ». Supprime le blocage de tete de file du TCP. Cout : un serveur de
  signalisation separe et une extension native cote serveur dedie. A evaluer en
  phase 4 si la fluidite des autres voitures pose probleme.
- **Compression d'etat** : quantifier positions (int16, 1 cm) et angles (int16,
  ~0,005°) ferait passer un etat de ~48 a ~16 octets. Inutile a 12 joueurs,
  interessant au-dela ou sur connexion faible.
- **Delta-compression** : n'envoyer que les vehicules ayant change depuis le
  dernier accuse. Gain reel surtout sur une grille a l'arret.
- **Zone d'interet** : ne pas envoyer les voitures situees a plus de N metres.
  Sans objet a 12 joueurs sur un circuit court.
- **Rollback des collisions entre joueurs** : en phase 5, la collision devient
  une dependance entre vehicules et casse le determinisme du replay isole.
  Piste : ne predire que le vehicule local et laisser le serveur arbitrer les
  contacts, avec une correction plus permissive pendant le contact.

### Vehicule et ressenti

- Assistance au contrebraquage pendant le derapage (aide invisible, tres utilisee
  en arcade) : ramene doucement le nez dans l'axe du vecteur vitesse.
- Bonus de vitesse en sortie de derapage (type « mini-turbo »), a relier au
  systeme de bonus de la phase 5+.
- Effet de charge aerodynamique : augmenter l'adherence avec la vitesse pour
  stabiliser les longues courbes rapides.
- Suspension visuelle : deja prevue cote rendu, a enrichir avec le roulis et le
  tangage en phase 4.

### Circuit

- Format de circuit en ressource (`.tres`) decrivant le trace, les points de
  passage et les positions de depart, pour que la phase 1 ajoute des circuits
  sans toucher au code.
- Generation des reperes au sol a partir du trace plutot qu'a la main.

### Outillage

- Rejeu enregistre : sauvegarder les entrees d'une session permet de rejouer une
  course a l'identique (utile au debogage du determinisme, et base du fantome de
  contre-la-montre prevu plus tard).
- Panneau de reglage en direct : editer `tuning.cfg` en jeu avec rechargement a
  chaud, pour regler le ressenti sans relancer.

---

## Mesures de performance web vs bureau

Relevees a la fin de la phase 0, avec `--benchmark`. La mesure qui compte est le
**cout d'un pas de simulation**, isole du rendu : les compteurs de Godot donnent
un temps par IMAGE, ce qui ne se compare pas entre deux plateformes qui n'ont pas
le meme nombre d'images par seconde.

| | Bureau (Linux, natif) | Navigateur (WebAssembly) | Ecart |
|---|---|---|---|
| Un pas de simulation, par vehicule | **40,0 us** | **124,2 us** | **3,1x** |
| Budget a 60 Hz, 1 vehicule | 0,2 % | 0,7 % | |
| Budget a 60 Hz, 12 vehicules | 2,9 % | 8,9 % | |

**Lecture.** Le facteur 3 correspond a ce qu'on attend de WebAssembly compare au
natif. L'important est ailleurs : meme trois fois plus lente, la physique ne
consomme que **9 % du budget d'un navigateur pour douze voitures**. La marge est
large, et elle serait encore plus confortable en pratique — un client ne simule
que SA voiture, les onze autres sont interpolees, ce qui coute bien moins cher.

Le choix d'une physique personnalisee plutot que `VehicleBody3D` y est pour
beaucoup : quatre rayons et de l'algebre vectorielle, la ou un vehicule a
suspension aurait demande un solveur complet par voiture.

### Ce que ces mesures ne disent pas

Le banc a tourne dans un conteneur **sans carte graphique**, ou Chromium rend en
logiciel (SwiftShader). Le temps de rendu releve — plus de 600 ms par image —
ne veut donc rien dire, et le nombre d'images par seconde non plus. Seul le cout
de la physique est exploitable, parce qu'il ne depend pas du rendu.

**A verifier sur une vraie machine**, avant de considerer la phase 0 close :
- le nombre d'images par seconde reel dans le navigateur, avec les ombres ;
- le comportement en plein ecran a 1920x1080 ;
- le cout des ombres directionnelles en `gl_compatibility` (leur portee a deja
  ete ramenee a 95 m, ce qui les rend plus nettes et moins couteuses) ;
- la difference entre Chrome et Firefox, dont les moteurs WebAssembly different.

### Poids de l'export web

| Fichier | Taille |
|---|---|
| `index.wasm` | 38 Mo |
| `index.js` | 276 ko |
| `index.pck` (le jeu lui-meme) | 132 ko |
| **Total** | **39 Mo** |

Le moteur represente la quasi-totalite du poids ; le jeu pese 132 ko. Ce total
descendrait nettement avec un export optimise (`--disable-3d` est exclu ici, mais
retirer les modules inutilises est possible en recompilant les modeles d'export).
A regarder seulement si le temps de chargement devient genant : le fichier est
compresse a la volee par la plupart des hebergeurs.
