# Score Capture Validation

Updated: 2026-06-20 UTC.

## Current Validation

| Gate | Status | Evidence |
|---|---|---|
| Supported format classification | Implemented | `scoreSourceKind()` and Vitest coverage. |
| Unsupported active format rejection | Implemented for raw SVG | Vitest rejects `image/svg+xml`. |
| Minimum resolution warning | Implemented | Low-resolution image test returns review status. |
| Likely sheet-music heuristic | Basic filename/geometry heuristic | Low-confidence/non-music copy is shown as review, not failure. |
| Preview before practice | Implemented | UI requires preview and confirmation before local save. |
| Camera permission denial | Implemented | User-facing fallback message. |
| Local storage failure | Implemented | Confirmation failure shows recovery copy. |

## Gaps To Close

- Validate magic bytes rather than trusting only MIME/extension.
- Apply EXIF orientation and strip private/location metadata before export/upload.
- Cap decoded pixel count before image decode to resist decompression bombs.
- Add blur, glare, skew, crop-completeness, contrast, and staff-line quality checks.
- Add retake/crop/reorder workflows.
- Add native VisionKit scanner and PhotosPicker/fileImporter flow.
- Add generated noncopyrighted fixture score images for repeatable visual tests.
- Add keyboard and touch score-reader E2E coverage.

## Printed-Note Flag Rule

Until OMR and alignment are implemented and validated, score practice may only show audio-based pitch flags tied to page/time. Do not phrase those flags as confirmed printed-score-note errors.
