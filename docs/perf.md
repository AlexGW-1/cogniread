# Performance Baseline (M1)

## Reader open (time to content)
- TBD: capture `Reader perf: time to content` for 2–3 large EPUBs.

## Parse pipeline timings
- TBD: `read bytes`, `extract chapters`, `build chapters`.

## Baseline results
- Strugackiy_Mir-Poludnya: 3.27 MB, 254 chapters
  - read bytes: 7ms
  - extract chapters: 1415ms
  - build chapters: 1867ms
  - time to content: 3427ms
- Sapkovskiy_Vedmak: 2.97 MB, 70 chapters
  - read bytes: 33ms
  - extract chapters: 655ms
  - build chapters: 729ms
  - time to content: 1481ms
- Simmons_Giperion: 3.12 MB, 165 chapters
  - read bytes: 28ms
  - extract chapters: 914ms
  - build chapters: 1360ms
  - time to content: 2354ms

## Decision
- Based on baseline, proceed with **render-by-chapters** to reduce widget tree size.
- Revisit after baseline logs; if still sluggish, evaluate chunked virtualization.

## Test corpus (local only)
- List local EPUBs used; do not commit to repo.
