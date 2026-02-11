# RUNBOOK — ZEN’KO Mozaic Engine

Règle : ce fichier est un journal de preuves (append-only).
Chaque entrée = date + objectif + commande + résultat + décision + commit.

---

## 2026-02-11 — Checkpoint A3/B1 + Debug Renderer
**Objectif**
- Valider l’anti-répétition centre (CAP=3) + A3 metrics
- Générer une image mosaïque debug (sans target)

**Commande**
- python main.py | rg "\[V0\]|\[A3CFG\]|\[B1DBG\]|\[A3\]|\[V1\]"

**Résultat (preuve)**
- max_center_repeat = 3 (target <= 3)
- Center total tiles = 216
- Center unique tiles = 110
- Center dup rate ≈ 0.4907
- Debug image: output/mosaic_debug.png

**Décision**
- NEXT: A4 (option 1) = intégrer target + matching couleur simple, en conservant A3/B1 au centre.
