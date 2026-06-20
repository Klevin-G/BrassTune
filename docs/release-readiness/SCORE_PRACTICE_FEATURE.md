# Score Practice Feature

Updated: 2026-06-20 UTC.

## Implemented Web Surface

- Route: `/practice/score`
- Navigation: app side nav, mobile More menu, and practice-page tool links.
- Three explicit import actions:
  - Scan with Camera
  - Choose from Photos
  - Choose Files
- Drag/drop and clipboard paste where the browser provides files.
- Supported source types by MIME/extension: PDF, JPEG/JPG, PNG, HEIC/HEIF, WebP, TIFF, BMP, AVIF, and GIF first-frame browser decode.
- Raw SVG is rejected rather than rendered.
- Camera capture uses `getUserMedia` with rear-camera preference where available.
- Imported pages show preview, quality messages, page list, zoom, rotation, focus preview, remove, and confirm controls.
- Confirmed pages are saved locally in IndexedDB with source metadata and blob.
- Source pages stay local by default.

## Automated Evidence

- `frontend/src/domain/scorePractice.test.ts` covers accepted PDF/image formats, SVG rejection, and low-resolution/non-music review status.
- `cd frontend && npm test` passed: `34` tests.
- `cd frontend && npm run build` passed.
- Full local E2E and device simulation passed.
- Rendered browser spot check verified Scan with Camera, Choose from Photos, Choose Files, local-default copy, and raw-SVG rejection copy with no console errors.

## Deliberately Not Claimed

- Full PDF.js rendering.
- Native VisionKit document scan.
- EXIF stripping and magic-byte validation.
- Perspective correction, crop, retake, page reorder, thumbnails, and browser Fullscreen API integration.
- OCR metadata extraction.
- Optical music recognition.
- Automatic score following.
- Printed-note mismatch certainty.

## Privacy Rules

- Do not upload source PDFs/images by default.
- Do not log source page contents.
- Do not include source pages in exported reports unless the user explicitly chooses that.
- Warn beta testers that copyrighted scores and student markings may be sensitive.
