import { Camera, ChevronLeft, ChevronRight, FileText, Image as ImageIcon, Maximize2, Minimize2, MoreVertical, MoveHorizontal, Music2, Plus, RotateCw, Trash2, Upload, X, ZoomIn, ZoomOut } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import pdfWorkerUrl from 'pdfjs-dist/build/pdf.worker.mjs?url';
import { PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { SCORE_DOCUMENTS_DB_NAME, SCORE_DOCUMENTS_STORE_NAME } from '../domain/scoreDocuments';
import { MAX_SCORE_FILE_BYTES, MAX_SCORE_PAGES, MAX_SCORE_PIXELS, pdfPageLimitMessage, scoreAcceptAttribute, verifiedScoreSourceKind, verifyScoreFile, type ScoreImportSummary } from '../domain/scorePractice';
import { useI18n } from '../i18n/LocaleContext';
import './ScorePracticePage.css';

function bidiIsolate(value: string | number) {
  return `\u2068${value}\u2069`;
}

interface ImportedScorePage {
  id: string;
  name: string;
  source: 'camera' | 'photos' | 'files' | 'clipboard' | 'drop';
  kind: 'pdf' | 'image';
  url: string;
  file: File;
  dimensions?: { width: number; height: number };
  summary: ScoreImportSummary;
  persisted: boolean;
}

type PreparedScorePage = Omit<ImportedScorePage, 'url' | 'persisted'>;

interface StoredScoreDocument {
  id?: unknown;
  name?: unknown;
  source?: unknown;
  type?: unknown;
  blob?: unknown;
}

interface StoredScoreLoadResult {
  pages: ImportedScorePage[];
  removedInvalidCount: number;
  cleanupFailures: string[];
}

const SCORE_IMPORT_SOURCES = new Set<ImportedScorePage['source']>(['camera', 'photos', 'files', 'clipboard', 'drop']);

function openScoreDb() {
  return new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(SCORE_DOCUMENTS_DB_NAME, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore(SCORE_DOCUMENTS_STORE_NAME, { keyPath: 'id' });
    };
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
  });
}

async function saveScoreDocument(page: ImportedScorePage) {
  const db = await openScoreDb();
  try {
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction(SCORE_DOCUMENTS_STORE_NAME, 'readwrite');
      transaction.objectStore(SCORE_DOCUMENTS_STORE_NAME).put({
        id: page.id,
        name: page.name,
        source: page.source,
        kind: page.kind,
        type: page.file.type,
        size: page.file.size,
        dimensions: page.dimensions,
        confirmedAt: new Date().toISOString(),
        quality: page.summary.quality,
        blob: page.file,
      });
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error ?? new Error('Could not save score document.'));
      transaction.onabort = () => reject(transaction.error ?? new Error('Score document save was cancelled.'));
    });
  } finally {
    db.close();
  }
}

async function deleteScoreDocument(id: string | number) {
  const db = await openScoreDb();
  try {
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction(SCORE_DOCUMENTS_STORE_NAME, 'readwrite');
      transaction.objectStore(SCORE_DOCUMENTS_STORE_NAME).delete(id);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error ?? new Error('Could not delete score document.'));
      transaction.onabort = () => reject(transaction.error ?? new Error('Score document deletion was cancelled.'));
    });
  } finally {
    db.close();
  }
}

async function readStoredScoreDocuments(): Promise<StoredScoreDocument[]> {
  const db = await openScoreDb();
  try {
    return await new Promise<StoredScoreDocument[]>((resolve, reject) => {
      const transaction = db.transaction(SCORE_DOCUMENTS_STORE_NAME, 'readonly');
      const request = transaction.objectStore(SCORE_DOCUMENTS_STORE_NAME).getAll();
      request.onsuccess = () => resolve(request.result as StoredScoreDocument[]);
      request.onerror = () => reject(request.error ?? new Error('Could not read saved score documents.'));
    });
  } finally {
    db.close();
  }
}

async function readPdfPageCount(file: File) {
  const pdfjs = await import('pdfjs-dist');
  pdfjs.GlobalWorkerOptions.workerSrc = pdfWorkerUrl;
  const loadingTask = pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()) });
  try {
    const pdf = await loadingTask.promise;
    return pdf.numPages;
  } finally {
    await loadingTask.destroy().catch(() => undefined);
  }
}

async function decodeImageDimensions(file: File) {
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error('Image decode failed.'));
      image.src = url;
    });
    if (image.naturalWidth <= 0 || image.naturalHeight <= 0) {
      throw new Error('Image decode returned empty dimensions.');
    }
    return { width: image.naturalWidth, height: image.naturalHeight };
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function loadScoreDocuments(): Promise<StoredScoreLoadResult> {
  const rows = await readStoredScoreDocuments();
  const pages: ImportedScorePage[] = [];
  const cleanupFailures: string[] = [];
  let removedInvalidCount = 0;

  for (const row of rows) {
    const cleanupKey = typeof row.id === 'string' || typeof row.id === 'number' ? row.id : null;
    const cleanupLabel = typeof row.name === 'string' ? row.name : 'A saved file';
    if (typeof row.id !== 'string' || typeof row.name !== 'string' || !(row.blob instanceof Blob)) {
      if (cleanupKey == null) {
        cleanupFailures.push(cleanupLabel);
      } else {
        try {
          await deleteScoreDocument(cleanupKey);
          removedInvalidCount += 1;
        } catch {
          cleanupFailures.push(cleanupLabel);
        }
      }
      continue;
    }
    const file = new File([row.blob], row.name, { type: typeof row.type === 'string' ? row.type : row.blob.type });
    let kind: ImportedScorePage['kind'] | null = null;
    let dimensions: ImportedScorePage['dimensions'];
    let summary: ScoreImportSummary | null = null;
    let shouldRemove = file.size <= 0 || file.size > MAX_SCORE_FILE_BYTES;

    if (!shouldRemove) {
      try {
        const verifiedKind = await verifiedScoreSourceKind(file);
        if (verifiedKind === 'unsupported') {
          shouldRemove = true;
        } else {
          kind = verifiedKind;
          if (kind === 'pdf') {
            shouldRemove = pdfPageLimitMessage(await readPdfPageCount(file)) != null;
          } else {
            dimensions = await decodeImageDimensions(file);
          }
          summary = verifyScoreFile(file, dimensions, kind);
          shouldRemove ||= !summary.supported;
        }
      } catch {
        shouldRemove = true;
      }
    }

    if (shouldRemove || kind == null || summary == null) {
      try {
        await deleteScoreDocument(row.id);
        removedInvalidCount += 1;
      } catch {
        // Never resurrect a known-invalid row. If IndexedDB refuses cleanup,
        // keep it hidden and report that it remains saved instead of claiming
        // deletion succeeded.
        cleanupFailures.push(row.name);
      }
      continue;
    }

    const source = typeof row.source === 'string' && SCORE_IMPORT_SOURCES.has(row.source as ImportedScorePage['source'])
      ? row.source as ImportedScorePage['source']
      : 'files';
    pages.push({
      id: row.id,
      name: row.name,
      source,
      kind,
      url: URL.createObjectURL(file),
      file,
      dimensions,
      summary: { ...summary, label: 'Saved' },
      persisted: true,
    });
  }

  return { pages, removedInvalidCount, cleanupFailures };
}

async function sanitizeImageFile(file: File) {
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error('Image decode failed.'));
      image.src = url;
    });
    const dimensions = { width: image.naturalWidth, height: image.naturalHeight };
    if (dimensions.width <= 0 || dimensions.height <= 0) throw new Error('Image decode returned empty dimensions.');
    if (dimensions.width * dimensions.height > MAX_SCORE_PIXELS) {
      return { dimensions, file };
    }
    const canvas = document.createElement('canvas');
    canvas.width = dimensions.width;
    canvas.height = dimensions.height;
    const context = canvas.getContext('2d');
    if (!context) return { dimensions, file };
    context.drawImage(image, 0, 0);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.92));
    if (!blob) return { dimensions, file };
    const name = file.name.replace(/\.[^.]+$/, '') || 'score-page';
    return {
      dimensions,
      file: new File([blob], `${name}.jpg`, { type: 'image/jpeg' }),
    };
  } finally {
    URL.revokeObjectURL(url);
  }
}

function PdfCanvasPreview({
  file,
  name,
  pageNumber,
  zoom,
  rotation,
  onPageCount,
}: {
  file: File;
  name: string;
  pageNumber: number;
  zoom: number;
  rotation: number;
  onPageCount: (count: number) => void;
}) {
  const { t } = useI18n();
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [renderStatus, setRenderStatus] = useState(() => t('score.openingPdf'));

  useEffect(() => {
    let cancelled = false;
    let cleanup: (() => void) | undefined;

    async function renderPdfPage() {
      setRenderStatus(t('score.openingPdf'));
      const pdfjs = await import('pdfjs-dist');
      pdfjs.GlobalWorkerOptions.workerSrc = pdfWorkerUrl;
      const loadingTask = pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()) });
      cleanup = () => {
        void loadingTask.destroy();
      };
      try {
        const pdf = await loadingTask.promise;
        if (cancelled) return;
        onPageCount(pdf.numPages);
        const safePageNumber = Math.min(Math.max(1, pageNumber), pdf.numPages);
        const page = await pdf.getPage(safePageNumber);
        if (cancelled) return;
        const viewport = page.getViewport({ scale: zoom, rotation });
        const canvas = canvasRef.current;
        const context = canvas?.getContext('2d');
        if (!canvas || !context) throw new Error('Canvas unavailable.');
        canvas.width = Math.ceil(viewport.width);
        canvas.height = Math.ceil(viewport.height);
        canvas.style.width = `${Math.ceil(viewport.width)}px`;
        canvas.style.height = `${Math.ceil(viewport.height)}px`;
        const renderTask = page.render({ canvas, canvasContext: context, viewport });
        cleanup = () => {
          renderTask.cancel();
          void loadingTask.destroy();
        };
        await renderTask.promise;
        if (!cancelled) setRenderStatus('');
      } catch (error) {
        if (!cancelled) setRenderStatus(error instanceof Error && error.message !== 'Rendering cancelled, page 0' ? t('score.pdfOpenFailed') : '');
      }
    }

    void renderPdfPage();
    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [file, name, onPageCount, pageNumber, rotation, t, zoom]);

  return (
    <>
      <canvas ref={canvasRef} aria-label={t('score.pageFor', { name: bidiIsolate(name) })} />
      {renderStatus && <span className="sm-render-status" role="status">{renderStatus}</span>}
    </>
  );
}

export function ScorePracticePage() {
  const { t, formatNumber } = useI18n();
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const photosInputRef = useRef<HTMLInputElement | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const viewerRef = useRef<HTMLDivElement | null>(null);
  const cameraStreamRef = useRef<MediaStream | null>(null);
  const cameraRequestGenerationRef = useRef(0);
  const cameraStartingRef = useRef(false);
  const pagesRef = useRef<ImportedScorePage[]>([]);
  const mountedRef = useRef(true);
  const deleteDialogRef = useRef<HTMLDivElement | null>(null);
  const deleteCancelRef = useRef<HTMLButtonElement | null>(null);
  const deleteReturnFocusRef = useRef<HTMLElement | null>(null);
  const moreOptionsRef = useRef<HTMLButtonElement | null>(null);
  const [pages, setPages] = useState<ImportedScorePage[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [status, setStatus] = useState('');
  const [importOpen, setImportOpen] = useState(false);
  const [cameraActive, setCameraActive] = useState(false);
  const [cameraStarting, setCameraStarting] = useState(false);
  const [zoom, setZoom] = useState(1);
  const [fitWidth, setFitWidth] = useState(true);
  const [rotation, setRotation] = useState(0);
  const [focusMode, setFocusMode] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [pendingDelete, setPendingDelete] = useState(false);
  const [pdfPageNumber, setPdfPageNumber] = useState(1);
  const [pdfPageCount, setPdfPageCount] = useState(1);
  const canUseCamera = typeof navigator !== 'undefined' && Boolean(navigator.mediaDevices?.getUserMedia);
  const selected = pages.find((page) => page.id === selectedId) ?? pages[0];
  const hasPages = pages.length > 0;
  const showImport = !hasPages || importOpen;
  const showFilmstrip = pages.length > 1 && !focusMode;

  useEffect(() => {
    setPdfPageNumber(1);
    setPdfPageCount(1);
    setZoom(1);
    setFitWidth(true);
    setRotation(0);
    setMenuOpen(false);
  }, [selected?.id]);

  const updatePdfPageCount = useCallback((count: number) => {
    const limitMessage = pdfPageLimitMessage(count);
    if (limitMessage) {
      const oversizedPage = pagesRef.current.find((page) => page.id === selectedId);
      if (oversizedPage) {
        // Imports are page-counted before persistence and restored rows are
        // validated before display. This is a final fail-closed guard for a
        // document that changes or races those checks.
        void (async () => {
          let cleanupFailed = false;
          if (oversizedPage.persisted) {
            try {
              await deleteScoreDocument(oversizedPage.id);
            } catch {
              cleanupFailed = true;
            }
          }
          URL.revokeObjectURL(oversizedPage.url);
          setPages((current) => current.filter((page) => page.id !== oversizedPage.id));
          setSelectedId((current) => current === oversizedPage.id ? null : current);
          setStatus(cleanupFailed
            ? t('score.pageLimitCleanup', { count: formatNumber(count), limit: formatNumber(MAX_SCORE_PAGES) })
            : t('score.pageLimit', { count: formatNumber(count), limit: formatNumber(MAX_SCORE_PAGES) }));
        })();
      }
    }
    setPdfPageCount(count);
    setPdfPageNumber((value) => Math.min(Math.max(1, value), count));
  }, [formatNumber, selectedId, t]);

  useEffect(() => {
    pagesRef.current = pages;
  }, [pages]);

  const stopCamera = () => {
    cameraRequestGenerationRef.current += 1;
    cameraStartingRef.current = false;
    cameraStreamRef.current?.getTracks().forEach((track) => track.stop());
    cameraStreamRef.current = null;
    if (mountedRef.current) {
      setCameraActive(false);
      setCameraStarting(false);
    }
  };

  useEffect(() => {
    if (cameraActive && videoRef.current && cameraStreamRef.current) {
      videoRef.current.srcObject = cameraStreamRef.current;
    }
  }, [cameraActive]);

  useEffect(() => {
    const onFullscreenChange = () => setFocusMode(Boolean(document.fullscreenElement));
    document.addEventListener('fullscreenchange', onFullscreenChange);
    return () => document.removeEventListener('fullscreenchange', onFullscreenChange);
  }, []);

  useEffect(() => {
    if (!pendingDelete) return;
    deleteCancelRef.current?.focus();
    const onKeyDown = (event: globalThis.KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        setPendingDelete(false);
        return;
      }
      if (event.key !== 'Tab') return;
      const focusable = Array.from(deleteDialogRef.current?.querySelectorAll<HTMLElement>('button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])') ?? []);
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      deleteReturnFocusRef.current?.focus();
      deleteReturnFocusRef.current = null;
    };
  }, [pendingDelete]);

  useEffect(() => {
    mountedRef.current = true;
    const onPaste = (event: ClipboardEvent) => {
      const files = Array.from(event.clipboardData?.files ?? []);
      if (files.length) void importFiles(files, 'clipboard');
    };
    window.addEventListener('paste', onPaste);
    return () => {
      mountedRef.current = false;
      window.removeEventListener('paste', onPaste);
      stopCamera();
      pagesRef.current.forEach((page) => URL.revokeObjectURL(page.url));
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    loadScoreDocuments()
      .then(({ pages: stored, removedInvalidCount, cleanupFailures }) => {
        if (cancelled) {
          stored.forEach((page) => URL.revokeObjectURL(page.url));
          return;
        }
        if (stored.length > 0) {
          setPages((current) => {
            const currentIds = new Set(current.map((page) => page.id));
            const restored = stored.filter((page) => {
              if (!currentIds.has(page.id)) return true;
              URL.revokeObjectURL(page.url);
              return false;
            });
            return [...current, ...restored];
          });
          setSelectedId((current) => current ?? stored[0].id);
        }
        if (cleanupFailures.length > 0) {
          setStatus(t('score.savedCleanupFailed', { count: cleanupFailures.length }));
        } else if (removedInvalidCount > 0) {
          setStatus(t('score.removedInvalid', { count: removedInvalidCount }));
        } else if (stored.length > 0) {
          setStatus(t('score.musicReady'));
        }
      })
      .catch(() => {
        if (!cancelled) setStatus(t('score.savedOpenFailed'));
      });
    return () => {
      cancelled = true;
    };
  }, [t]);

  const importFiles = async (files: File[], source: ImportedScorePage['source']) => {
    const imported: PreparedScorePage[] = [];
    for (const file of files) {
      try {
        if (file.size > MAX_SCORE_FILE_BYTES) {
          setStatus(t('score.tooLarge', { filename: bidiIsolate(file.name) }));
          continue;
        }
        const kind = await verifiedScoreSourceKind(file);
        if (kind === 'unsupported') {
          setStatus(t('score.unsupportedFile', { filename: bidiIsolate(file.name) }));
          continue;
        }
        if (kind === 'pdf') {
          const pageCount = await readPdfPageCount(file);
          const limitMessage = pdfPageLimitMessage(pageCount);
          if (limitMessage) {
            setStatus(t('score.pageLimit', { count: formatNumber(pageCount), limit: formatNumber(MAX_SCORE_PAGES) }));
            continue;
          }
        }
        const prepared = kind === 'image' ? await sanitizeImageFile(file) : { dimensions: undefined, file };
        const summary = verifyScoreFile(prepared.file, prepared.dimensions, kind);
        if (!summary.supported) {
          setStatus(t('score.unsupportedFile', { filename: bidiIsolate(file.name) }));
          continue;
        }
        imported.push({
          id: `${Date.now()}-${crypto.randomUUID?.() ?? Math.random().toString(16).slice(2)}`,
          name: prepared.file.name,
          source,
          kind,
          file: prepared.file,
          dimensions: prepared.dimensions,
          summary,
        });
      } catch {
        setStatus(t(/\.pdf$/i.test(file.name) || file.type === 'application/pdf' ? 'score.invalidPdf' : 'score.invalidImage', { filename: bidiIsolate(file.name) }));
      }
    }
    if (!imported.length) return;
    setStatus(t('score.savingPages', { count: imported.length }));
    const saved = await Promise.all(imported.map(async (page) => {
      try {
        await saveScoreDocument({ ...page, url: '', persisted: false });
        return { page, persisted: true };
      } catch {
        return { page, persisted: false };
      }
    }));
    if (!mountedRef.current) return;
    const ready = saved.map(({ page, persisted }) => ({
      ...page,
      url: URL.createObjectURL(page.file),
      persisted,
    }));
    setPages((current) => [...current, ...ready]);
    setSelectedId(ready[0].id);
    setImportOpen(false);
    setStatus(saved.some(({ persisted }) => !persisted)
      ? t('score.addedNotPersisted')
      : t('score.addedPages', { count: ready.length }));
  };

  const startCamera = async () => {
    if (!canUseCamera) {
      setStatus(t('score.cameraUnavailable'));
      return;
    }
    if (cameraStartingRef.current) return;
    const generation = ++cameraRequestGenerationRef.current;
    cameraStartingRef.current = true;
    setCameraStarting(true);
    setStatus(t('score.openingCamera'));
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false });
      if (!mountedRef.current || generation !== cameraRequestGenerationRef.current) {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }
      cameraStreamRef.current = stream;
      if (videoRef.current) videoRef.current.srcObject = stream;
      setCameraActive(true);
      setStatus(t('score.cameraReady'));
    } catch {
      if (mountedRef.current && generation === cameraRequestGenerationRef.current) {
        setStatus(t('score.cameraBlocked'));
      }
    } finally {
      if (generation === cameraRequestGenerationRef.current) {
        cameraStartingRef.current = false;
        if (mountedRef.current) setCameraStarting(false);
      }
    }
  };

  const openDeleteDialog = () => {
    deleteReturnFocusRef.current = moreOptionsRef.current;
    setMenuOpen(false);
    setPendingDelete(true);
  };

  const captureCameraPage = async () => {
    const video = videoRef.current;
    if (!video || video.videoWidth === 0 || video.videoHeight === 0) {
      setStatus(t('score.cameraNotReady'));
      return;
    }
    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext('2d');
    if (!context) return;
    context.drawImage(video, 0, 0);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.9));
    if (!blob) {
      setStatus(t('score.captureFailed'));
      return;
    }
    stopCamera();
    await importFiles([new File([blob], `camera-score-${new Date().toISOString().slice(0, 19)}.jpg`, { type: 'image/jpeg' })], 'camera');
  };

  const performDelete = async () => {
    setPendingDelete(false);
    if (!selected) return;
    if (selected.persisted) {
      try {
        await deleteScoreDocument(selected.id);
      } catch {
        setStatus(t('score.removeFailed', { filename: bidiIsolate(selected.name) }));
        return;
      }
    }
    URL.revokeObjectURL(selected.url);
    setPages((current) => current.filter((page) => page.id !== selected.id));
    setSelectedId(null);
    setStatus(t('score.removed'));
  };

  const toggleFullscreen = () => {
    if (document.fullscreenElement) {
      void document.exitFullscreen();
      return;
    }
    const el = viewerRef.current;
    if (el?.requestFullscreen) {
      el.requestFullscreen().catch(() => setFocusMode((value) => !value));
    } else {
      setFocusMode((value) => !value);
    }
  };

  const zoomIn = () => {
    setFitWidth(false);
    setZoom((value) => Math.min(3, Number((value + 0.15).toFixed(2))));
  };
  const zoomOut = () => {
    setFitWidth(false);
    setZoom((value) => Math.max(0.4, Number((value - 0.15).toFixed(2))));
  };
  const pdfZoom = fitWidth ? 1 : zoom;

  const acceptAttribute = scoreAcceptAttribute();

  const importPanel = (
    <div
      className="sm-import-dropzone"
      onDragOver={(event) => event.preventDefault()}
      onDrop={(event) => {
        event.preventDefault();
        void importFiles(Array.from(event.dataTransfer.files), 'drop');
      }}
    >
      {!hasPages && (
        <p className="sm-import-lead"><Music2 size={20} />{t('score.importLead')}</p>
      )}
      <div className="sm-import-actions">
        {canUseCamera && (
          <button className="primary-button" type="button" disabled={cameraStarting} onClick={cameraActive ? captureCameraPage : startCamera}>
            <Camera size={18} />
            {t(cameraStarting ? 'score.openingCamera' : cameraActive ? 'score.capturePage' : 'score.scanCamera')}
          </button>
        )}
        <button className={canUseCamera ? 'ghost-button' : 'primary-button'} type="button" onClick={() => photosInputRef.current?.click()}>
          <ImageIcon size={18} />
          {t('score.choosePhotos')}
        </button>
        <button className="ghost-button" type="button" onClick={() => fileInputRef.current?.click()}>
          <Upload size={18} />
          {t('score.chooseFiles')}
        </button>
      </div>
      <p className="sm-import-hint">{t('score.dragDrop')}</p>
      {cameraActive && (
        <div className="camera-preview">
          <video ref={videoRef} autoPlay playsInline muted aria-label={t('score.cameraPreview')} />
          <button className="ghost-button" type="button" onClick={stopCamera}>{t('score.stopCamera')}</button>
        </div>
      )}
      <p className="sm-import-note">{t('score.localOnly')}</p>
    </div>
  );

  return (
    <ScreenContainer className="score-practice-screen sm-screen">
      <PageHeader
        title={t('score.title')}
        description={t('score.description')}
        action={hasPages ? (
          <button className="ghost-button" type="button" onClick={() => setImportOpen((value) => !value)}>
            <Plus size={18} />
            {t('score.addMusic')}
          </button>
        ) : undefined}
      />

      {selected && (
        <SectionCard className="sm-viewer-card">
          <div className={`sm-viewer ${focusMode ? 'is-focus' : ''}`} ref={viewerRef}>
            <div className="sm-toolbar">
              <button className="icon-button labeled" type="button" onClick={() => { setFitWidth(true); setZoom(1); }} aria-pressed={fitWidth} title={t('score.fitWidth')}>
                <MoveHorizontal size={17} />{t('score.fitWidth')}
              </button>
              <button className="icon-button labeled" type="button" onClick={zoomOut} title={t('score.zoomOut')}>
                <ZoomOut size={17} />{t('score.zoomOut')}
              </button>
              <button className="icon-button labeled" type="button" onClick={zoomIn} title={t('score.zoomIn')}>
                <ZoomIn size={17} />{t('score.zoomIn')}
              </button>
              <button className="icon-button labeled" type="button" onClick={() => setRotation((value) => (value + 90) % 360)} title={t('score.rotate')}>
                <RotateCw size={17} />{t('score.rotate')}
              </button>
              {selected.kind === 'pdf' && pdfPageCount > 1 && (
                <div className="sm-pager">
                  <button className="icon-button" type="button" onClick={() => setPdfPageNumber((value) => Math.max(1, value - 1))} disabled={pdfPageNumber <= 1} aria-label={t('common.previous')}><ChevronLeft size={18} /></button>
                  <span className="sm-pager-label"><bdi dir="ltr">{t('score.pageCount', { current: formatNumber(pdfPageNumber), total: formatNumber(pdfPageCount) })}</bdi></span>
                  <button className="icon-button" type="button" onClick={() => setPdfPageNumber((value) => Math.min(pdfPageCount, value + 1))} disabled={pdfPageNumber >= pdfPageCount} aria-label={t('common.next')}><ChevronRight size={18} /></button>
                </div>
              )}
              <button className="icon-button labeled" type="button" onClick={toggleFullscreen} aria-pressed={focusMode} title={t(focusMode ? 'score.exitFullscreen' : 'score.fullscreen')}>
                {focusMode ? <Minimize2 size={17} /> : <Maximize2 size={17} />}
                {t(focusMode ? 'score.exitFullscreen' : 'score.fullscreen')}
              </button>
              <div className="sm-menu-wrap">
                <button className="icon-button" ref={moreOptionsRef} type="button" onClick={() => setMenuOpen((value) => !value)} aria-label={t('sessions.moreOptions')} aria-haspopup="menu" aria-expanded={menuOpen}><MoreVertical size={18} /></button>
                {menuOpen && (
                  <>
                    <button className="sm-menu-scrim" type="button" aria-label={t('score.closeMenu')} onClick={() => setMenuOpen(false)} />
                    <div className="sm-menu" role="menu">
                      <button className="sm-menu-item sm-menu-danger" type="button" role="menuitem" onClick={openDeleteDialog}>
                        <Trash2 size={17} />{t('score.deletePage')}
                      </button>
                    </div>
                  </>
                )}
              </div>
            </div>

            <div className={`sm-viewer-body ${showFilmstrip ? 'has-strip' : ''}`}>
              {showFilmstrip && (
                <aside className="sm-filmstrip" aria-label={t('score.pages')}>
                  {pages.map((page, index) => (
                    <button className={`sm-thumb ${page.id === selected.id ? 'is-active' : ''}`} key={page.id} type="button" onClick={() => setSelectedId(page.id)}>
                      <span className="sm-thumb-img">
                        {page.kind === 'image' ? <img src={page.url} alt="" /> : <FileText size={22} />}
                      </span>
                      <span className="sm-thumb-meta">
                        <strong><bdi dir="ltr">{t('score.pageNumber', { count: formatNumber(index + 1) })}</bdi></strong>
                        {!page.summary.supported && <StatusBadge tone="amber">{t('score.cantOpen')}</StatusBadge>}
                        <em className="sm-thumb-name"><bdi dir="auto">{page.name}</bdi></em>
                      </span>
                    </button>
                  ))}
                </aside>
              )}
              <div className="sm-stage">
                <div className={`sm-frame ${fitWidth ? 'is-fit' : ''}`}>
                  {selected.kind === 'pdf' ? (
                    <PdfCanvasPreview
                      file={selected.file}
                      name={selected.name}
                      pageNumber={pdfPageNumber}
                      zoom={pdfZoom}
                      rotation={rotation}
                      onPageCount={updatePdfPageCount}
                    />
                  ) : (
                    <img
                      className={`sm-page ${fitWidth ? 'sm-page-fit' : ''}`}
                      alt={t('score.musicAlt', { name: bidiIsolate(selected.name) })}
                      src={selected.url}
                      style={fitWidth ? { transform: rotation ? `rotate(${rotation}deg)` : undefined } : { transform: `scale(${zoom}) rotate(${rotation}deg)` }}
                    />
                  )}
                </div>
              </div>
            </div>
          </div>
        </SectionCard>
      )}

      {showImport && (
        <SectionCard
          title={hasPages ? t('score.addMusic') : undefined}
          action={hasPages ? (
            <button className="icon-button" type="button" onClick={() => setImportOpen(false)} aria-label={t('common.close')}><X size={18} /></button>
          ) : undefined}
        >
          {importPanel}
        </SectionCard>
      )}

      {status && <p className="sm-status" aria-live="polite">{status}</p>}

      <input
        ref={photosInputRef}
        className="visually-hidden"
        type="file"
        accept={acceptAttribute}
        multiple
        onChange={(event) => {
          const input = event.currentTarget;
          void importFiles(Array.from(input.files ?? []), 'photos').finally(() => {
            input.value = '';
          });
        }}
        aria-label={t('score.choosePhotos')}
      />
      <input
        ref={fileInputRef}
        className="visually-hidden"
        type="file"
        accept={acceptAttribute}
        multiple
        onChange={(event) => {
          const input = event.currentTarget;
          void importFiles(Array.from(input.files ?? []), 'files').finally(() => {
            input.value = '';
          });
        }}
        aria-label={t('score.chooseFiles')}
      />

      {pendingDelete && (
        <div className="sm-confirm-backdrop" role="dialog" aria-modal="true" aria-labelledby="sm-delete-title" aria-describedby="sm-delete-description">
          <div className="sm-confirm" ref={deleteDialogRef}>
            <h3 id="sm-delete-title">{t('score.removeTitle')}</h3>
            <p id="sm-delete-description">{t('score.removeBody')}</p>
            <div className="sm-confirm-actions">
              <button className="ghost-button" ref={deleteCancelRef} type="button" onClick={() => setPendingDelete(false)}>{t('common.cancel')}</button>
              <button className="sm-danger-button" type="button" onClick={() => void performDelete()}>
                <Trash2 size={17} />{t('score.remove')}
              </button>
            </div>
          </div>
        </div>
      )}
    </ScreenContainer>
  );
}
