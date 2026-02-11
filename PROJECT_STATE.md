# PROJECT_STATE — ZEN’KO Mosaic Engine

## 1. IDENTITÉ DU PROJET

**Nom** : ZEN’KO Mosaic Engine  
**Version** : v1.0.0-alpha  
**Date** : 2026-02-10  
**Dépôt** : zenko-mozaic-engine  
**Entrée unique** : `main.py`  
**Mode d’exécution** : CLI (python main.py)

---

## 2. INTENTION PRODUIT (NON NÉGOCIABLE)

### Décision structurante (VERROUILLÉE)

**Rendu par défaut = EFFET GALERIE (portrait-first)**

- Le visage / sujet central doit rester **hautement lisible**
- La mosaïque est **secondaire**, douce, non agressive
- La répétition de tuiles dans la zone centrale doit être **fortement pénalisée**

### Décision stratégique différée (À RAPPELER PLUS TARD)

- **Effet “Mosaïque assumée” = ÉDITION PAYANTE**
- Mise de côté volontaire
- Devra être rappelée explicitement lors du travail **offre / pricing / positionnement**

---

## 3. ARCHITECTURE (FIGÉE)

zenko-mozaic-engine/
├── main.py # Entrée unique (NE RIEN METTRE D’AUTRE)
├── configs/
│ └── default.py # Configuration globale (source de vérité)
├── engine/
│ ├── bootstrap.py # Orchestrateur (pas de logique métier)
│ ├── core/
│ │ ├── a3_probe.py # Mesures anti-répétition (A3)
│ │ ├── a3_viz.py # Visualisation ASCII (debug)
│ │ ├── b0_probe.py # Probes historiques
│ │ └── blend_mask.py # Masques de blend
│ ├── profiles/
│ │ ├── registry.py # Registry des profils
│ │ └── premium_subject_focus.py # PROFIL UNIQUE V1
├── data/ # Inputs
├── output/ # Outputs
├── PROJECT_STATE.md # CE FICHIER (source de reprise)
└── requirements.txt


### Règles non négociables

- `main.py` = **point d’entrée unique**
- Aucune logique métier dans `main.py`
- `bootstrap.py` orchestre, **ne décide pas**
- Toute stratégie visuelle = **profil**
- Une seule stratégie active en V1

---

## 4. PROFIL ACTIF (V1)

### Profil unique

`PREMIUM_SUBJECT_FOCUS`

Fichier :
engine/profiles/premium_subject_focus.py

Contenu **validé** :

- Tile size : **48**
- Grid observée : **80 x 45**
- Blend elliptique centré visage
- A3 activé (anti-répétition centre)

```python
"a3_diversity": {
    "enable": True,
    "k_center": 1.30,
    "k_edge": 0.05,
    "cap": 3
}
