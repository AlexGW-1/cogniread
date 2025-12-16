# ADR 0001: Monorepo structure

## Status
Accepted

## Context
MVP requires rapid iteration across client + API + AI pipeline.

## Decision
Use a single repository with `app/`, `backend/api/`, `backend/ai/`, `infra/`, `docs/`.

## Consequences
- Easier cross-cutting changes and CI
- Clear ownership via CODEOWNERS (add later if needed)
