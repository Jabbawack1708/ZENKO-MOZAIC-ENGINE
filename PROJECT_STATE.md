# PROJECT_STATE — ZEN’KO Mozaic Engine

## Current
- Date: 2026-02-01
- Version: v1.0.0-alpha
- Commit: not yet committed
- Goal (V1, 1 sentence):
  Generate a premium subject-focused mosaic where the center remains highly readable and tiles blend softly.

## RUNBOOK (proof)
Not available yet.

## Invariants (do not change in V1)
- Config-driven execution
- Single style: PREMIUM_SUBJECT_FOCUS
- GitHub is source of truth
- main.py contains exactly one: parse_args(), run(cfg), if __name__ == '__main__'

## Backlog
### NOW
1) Repo scaffolding + proof of Git push
2) Lock workflow discipline (no web UI edits, local->git only)

### NEXT
- Engine baseline (V1)

### LATER
- face-aware
- anti-duplication
- multi profiles
- tile inspector

### DONE
- 2026-02-01: GitHub repo created (empty)
