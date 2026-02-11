# PROJECT_STATE — ZEN’KO Mozaic Engine

## 1) Identité du projet
- Nom : ZEN’KO Mozaic Engine
- Version : v1.0.0-alpha
- Repo : `~/workspace/zenko-mozaic-engine`
- Entrée unique : `main.py`
- Exécution : `python main.py`

---

## 2) Intention produit (NON NÉGOCIABLE)
### Décision structurante (verrouillée)
Rendu par défaut = **Effet Galerie / portrait-first**
- Le sujet/portrait doit rester **hautement lisible**
- La mosaïque doit rester **discrète**
- La répétition de tuiles au centre doit être **fortement contrôlée**

### Décision stratégique différée (à rappeler plus tard)
Effet **“Mosaïque assumée”** = **ÉDITION PAYANTE**
- Mise de côté volontaire
- À rappeler lors offre / pricing / positionnement

---

## 3) Architecture (FIGÉE)


zenko-mozaic-engine/
├── main.py # Entrée unique (ne rien mettre d’autre)
├── configs/
│ └── default.py # Config source de vérité
├── engine/
│ ├── bootstrap.py # Orchestrateur (pas de logique métier finale)
│ ├── profiles/
│ │ ├── registry.py # load_profile()
│ │ └── premium_subject_focus.py# Profil unique V1
│ └── core/
│ ├── a3_probe.py # Metrics anti-répétition (centre ellipse)
│ ├── a3_viz.py # Preuve ASCII
│ ├── b0_probe.py # Legacy
│ ├── blend_mask.py # Masque / blend
│ └── debug_renderer.py # Rendu debug mosaïque (image)
├── data/
└── output/


### Règles non négociables

- `main.py` = **point d’entrée unique**
- Aucune logique métier dans `main.py`
- `bootstrap.py` orchestre, **ne décide pas**
- Toute stratégie visuelle = **profil**
- Une seule stratégie active en V1

---


---

## 4) Profil actif (V1)
- Profil : `PREMIUM_SUBJECT_FOCUS`
- Fichier : `engine/profiles/premium_subject_focus.py`

Paramètres (actuels) :
- Output : 3840 x 2160
- Tile size : 48
- Blend : alpha_center=0.04, alpha_edge=0.18, feather=0.22
- Ellipse : center_x=0.50, center_y=0.45, ellipse_rx≈0.252, ellipse_ry≈0.306
- A3 diversity :
  - enable=True
  - k_center=1.30
  - k_edge=0.05
  - cap=3 (centre)

---

## 5) Règles de travail (discipline)
- 1 étape = 1 objectif + 1 preuve console + 1 commit
- Toujours des preuves imprimées (sortie console filtrée)
- Pas de dépendances lourdes / fragiles (matplotlib évité)
- Pas de refactor architecture sans raison
- Si changement > 5 lignes : fournir le fichier complet (éviter erreurs humaines)

---

## 6) STATUS — 2026-02-11

### ✅ DONE
- V0 grid simulation stable
- Chargement tuiles réelles (fallback fake)
- A3 diversity active (pénalité répétitions)
- B1 hard cap centre : **cap=3** appliqué
- Preuve console : `max_center_repeat <= 3`
- Preuve ASCII A3 OK
- Debug renderer : image mosaïque générée
  - output : `output/mosaic_debug.png`

### ⚠ LIMITES ACTUELLES
- Aucune photo cible / target intégrée
- Pas de matching couleur
- Placement encore “structurel” (pas “visuel”)

### 🎯 NOW
- Stabiliser l’état + commit checkpoint
- Préparer A4 (matching couleur simple)

### 🔜 NEXT (A4 — option 1)
- Ajouter une image cible `data/target/target.jpg`
- Calcul moyenne RGB par tuile (cache)
- Calcul moyenne RGB par cellule target
- Choisir tuile la plus proche (distance euclidienne)
- Conserver A3 (anti-répétition centre) pendant la sélection

