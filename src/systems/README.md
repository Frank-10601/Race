# Systemes des phases suivantes

Dossier volontairement vide en phase 0. Il accueillera, sans toucher au reste :

- `laps/`       phase 1 : points de passage, compteur de tours, chronometre
- `race/`       phase 2 : depart compte, classement en direct, ecran de resultats
- `effects/`    phase 4 : poussiere, traces de pneus, effets de vitesse
- `collision/`  phase 5 : collisions entre joueurs, remise en piste

Regle : ces systemes **observent** l'etat du vehicule et du reseau, ils ne le
modifient pas. Le vehicule ne doit jamais dependre d'un systeme de ce dossier.
