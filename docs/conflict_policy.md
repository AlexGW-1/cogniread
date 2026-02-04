# Conflict Policy (LWW) — Draft

## Purpose
Define a simple, predictable conflict resolution strategy for sync-ready entities.

## Strategy
Use **Last-Write-Wins (LWW)** based on `updatedAt` for all entities listed below.

### General Rules
- If `updatedAt` differs, keep the record with the newer timestamp.
- If `updatedAt` is equal, prefer the record with the higher `id` (stable tie-break).
- If `updatedAt` is missing on either side, treat that record as **older**.
- All timestamps are expected in ISO-8601 and UTC.

## Entities & Fields

### Note
- Conflict key: `id`
- LWW fields: `noteText`, `color`, `excerpt`, `anchor`, `endOffset`, `updatedAt`
- Rationale: edits are linear and last edit should win.

### Highlight
- Conflict key: `id`
- LWW fields: `color`, `excerpt`, `anchor`, `endOffset`, `updatedAt`
- Rationale: highlight changes are typically simple updates.

### FreeNote
- Conflict key: `id`
- LWW fields: `text`, `color`, `updatedAt`
- Rationale: free notes are edited linearly; last edit wins.

### Bookmark
- Conflict key: `id` (book has max 1 bookmark in current model)
- LWW fields: `anchor`, `label`, `updatedAt`
- Rationale: a single bookmark per book; last change wins.

### ReadingPosition
- Conflict key: `bookId`
- LWW fields: `chapterHref`, `offset`, `anchor`, `updatedAt`
- Rationale: user reading location should follow the latest activity.

### EventLog
- Conflict key: `id`
- Resolution: **append-only**; no conflicts resolved by LWW.
- Rationale: events are immutable and replayed in order.

## Known Limitations / Future Work
- **Notes merge:** two devices editing the same note could overwrite each other.
- **Highlights merge:** overlapping highlights or simultaneous color changes.
- **ReadingPosition drift:** LWW may jump backwards if a device is offline.
- **EventLog conflicts:** if multiple devices generate events with same `id`, need UUIDs.

## Next Steps
- Enforce `updatedAt` on all syncable entities.
- Consider per-field merge (e.g., note text) or CRDTs if collaborative editing is needed.
