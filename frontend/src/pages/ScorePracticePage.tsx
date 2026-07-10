import { Camera, ChevronLeft, ChevronRight, FileText, Image as ImageIcon, Maximize2, Minimize2, MoreVertical, MoveHorizontal, Music2, Plus, RotateCw, Trash2, Upload, X, ZoomIn, ZoomOut } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import pdfWorkerUrl from 'pdfjs-dist/build/pdf.worker.mjs?url';
import { PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import './ScorePracticePage.css';
import { SCORE_DOCUMENTS_DB_NAME, SCORE_DOCUMENTS_STORE_NAME } from '../domain/scoreDocuments';
import { MAX_SCORE_FILE_BYTES, MAX_SCORE_PIXELS, pdfPageLimitMessage, scoreAcceptAttribute, verifiedScoreSourceKind, verifyScoreFile, type ScoreImportSummary } from '../domain/scorePractice';

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
    transaction.onerror = () => reject(transaction.error);
  });
  db.close();
}

async function deleteScoreDocument(id: string) {
  const db = await openScoreDb();
  await new Promise<void>((resolve, reject) => {
    const transaction = db.transaction(SCORE_DOCUMENTS_STORE_NAME, 'readwrite');
    transaction.objectStore(SCORE_DOCUMENTS_STORE_NAME).delete(id);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
  });
  db.close();
}

async function loadScoreDocuments(): Promise<ImportedScorePage[]> {
  const db = await openScoreDb();
  const rows = await new Promise<any[]>((resolve, reject) => {
    const transaction = db.transaction(SCORE_DOCUMENTS_STORE_NAME, 'readonly');
    const request = transaction.objectStore(SCORE_DOCUMENTS_STORE_NAME).getAll();
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  db.close();
  return rows
    .filter((row) => row.blob instanceof Blob)
    .map((row) => {
      const file = new File([row.blob], row.name, { type: row.type || row.blob.type });
      return {
        id: row.id,
        name: row.name,
        source: row.source,
        kind: row.kind,
        url: URL.createObjectURL(file),
        file,
        dimensions: row.dimensions,
        summary: {
          kind: row.kind,
          supported: true,
          label: 'Saved',
          quality: row.quality,
        },
        persisted: true,
      };
    });
}

async function sanitizeImageFile(file: File) {
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error('Image preview failed.'));
      image.src = url;
    });
    const dimensions = { width: image.naturalWidth, height: image.naturalHeight };
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
  } catch {
    return { dimensions: undefined, file };
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
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [renderStatus, setRenderStatus] = useState('Opening PDF…');

  useEffect(() => {
    let cancelled = false;
    let cleanup: (() => void) | undefined;

    async function renderPdfPage() {
      setRenderStatus('Opening PDF…');
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
        if (!cancelled) setRenderStatus(error instanceof Error && error.message !== 'Rendering cancelled, page 0' ? 'This PDF page could not open in this browser.' : '');
      }
    }

    void renderPdfPage();
    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [file, name, onPageCount, pageNumber, rotation, zoom]);

  return (
    <>
      <canvas ref={canvasRef} aria-label={`Sheet music page for ${name}`} />
      {renderStatus && <span className="sm-render-status" role="status">{renderStatus}</span>}
    </>
  );
}

export function ScorePracticePage() {
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const photosInputRef = useRef<HTMLInputElement | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const viewerRef = useRef<HTMLDivElement | null>(null);
  const cameraStreamRef = useRef<MediaStream | null>(null);
  const pagesRef = useRef<ImportedScorePage[]>([]);
  const [pages, setPages] = useState<ImportedScorePage[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [status, setStatus] = useState('');
  const [importOpen, setImportOpen] = useState(false);
  const [cameraActive, setCameraActive] = useState(false);
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
      setPages((current) => current.map((page) => (
        page.id === selectedId
          ? {
            ...page,
            persisted: false,
            summary: {
              ...page.summary,
              supported: false,
              label: 'Too many pages',
              quality: {
                status: 'unsupported',
                messages: [limitMessage],
                likelySheetMusicScore: page.summary.quality.likelySheetMusicScore,
              },
            },
          }
          : page
      )));
      setStatus(limitMessage);
    }
    setPdfPageCount(count);
    setPdfPageNumber((value) => Math.min(Math.max(1, value), count));
  }, [selectedId]);

  useEffect(() => {
    pagesRef.current = pages;
  }, [pages]);

  const stopCamera = () => {
    cameraStreamRef.current?.getTracks().forEach((track) => track.stop());
    cameraStreamRef.current = null;
    setCameraActive(false);
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
    const onPaste = (event: ClipboardEvent) => {
      const files = Array.from(event.clipboardData?.files ?? []);
      if (files.length) void importFiles(files, 'clipboard');
    };
    window.addEventListener('paste', onPaste);
    return () => {
      window.removeEventListener('paste', onPaste);
      stopCamera();
      pagesRef.current.forEach((page) => URL.revokeObjectURL(page.url));
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    loadScoreDocuments()
      .then((stored) => {
        if (cancelled || stored.length === 0) return;
        setPages(stored);
        setSelectedId(stored[0].id);
        setStatus('Your music is here.');
      })
      .catch(() => {
        if (!cancelled) setStatus('Saved music could not be opened in this browser.');
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const importFiles = async (files: File[], source: ImportedScorePage['source']) => {
    const imported: ImportedScorePage[] = [];
    for (const file of files) {
      if (file.size > MAX_SCORE_FILE_BYTES) {
        setStatus(`${file.name} is too large to add.`);
        continue;
      }
      const kind = await verifiedScoreSourceKind(file);
      if (kind === 'unsupported') {
        setStatus(`${file.name} isn't a photo or PDF we can open.`);
        continue;
      }
      const prepared = kind === 'image' ? await sanitizeImageFile(file) : { dimensions: undefined, file };
      const summary = verifyScoreFile(prepared.file, prepared.dimensions, kind);
      if (!summary.supported) {
        setStatus(`${file.name}: ${summary.quality.messages.join(' ')}`);
        continue;
      }
      imported.push({
        id: `${Date.now()}-${crypto.randomUUID?.() ?? Math.random().toString(16).slice(2)}`,
        name: prepared.file.name,
        source,
        kind,
        url: URL.createObjectURL(prepared.file),
        file: prepared.file,
        dimensions: prepared.dimensions,
        summary,
        persisted: false,
      });
    }
    if (!imported.length) return;
    setPages((current) => [...current, ...imported]);
    setSelectedId(imported[0].id);
    setImportOpen(false);
    setStatus(imported.length === 1 ? 'Added your page.' : `Added ${imported.length} pages.`);
    for (const page of imported) {
      try {
        await saveScoreDocument(page);
        setPages((current) => current.map((entry) => (entry.id === page.id ? { ...entry, persisted: true } : entry)));
      } catch {
        setStatus('Added — but this browser may not keep it after you close the tab.');
      }
    }
  };

  const startCamera = async () => {
    if (!canUseCamera) {
      setStatus('This browser can’t use the camera. Choose Photos or Files instead.');
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false });
      cameraStreamRef.current = stream;
      if (videoRef.current) videoRef.current.srcObject = stream;
      setCameraActive(true);
      setStatus('Point at your music, then Capture page.');
    } catch {
      setStatus('Camera permission was blocked. Choose Photos or Files instead.');
    }
  };

  const captureCameraPage = async () => {
    const video = videoRef.current;
    if (!video || video.videoWidth === 0 || video.videoHeight === 0) {
      setStatus('Camera isn’t ready yet.');
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
      setStatus('Capture failed. Try again.');
      return;
    }
    stopCamera();
    await importFiles([new File([blob], `camera-score-${new Date().toISOString().slice(0, 19)}.jpg`, { type: 'image/jpeg' })], 'camera');
  };

  const performDelete = async () => {
    setPendingDelete(false);
    if (!selected) return;
    URL.revokeObjectURL(selected.url);
    if (selected.persisted) {
      await deleteScoreDocument(selected.id).catch(() => undefined);
    }
    setPages((current) => current.filter((page) => page.id !== selected.id));
    setSelectedId(null);
    setStatus('Page removed.');
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
        <p className="sm-import-lead"><Music2 size={20} />Add your sheet music to read while you play.</p>
      )}
      <div className="sm-import-actions">
        {canUseCamera && (
          <button className="primary-button" type="button" onClick={cameraActive ? captureCameraPage : startCamera}>
            <Camera size={18} />
            {cameraActive ? 'Capture page' : 'Scan with camera'}
          </button>
        )}
        <button className={canUseCamera ? 'ghost-button' : 'primary-button'} type="button" onClick={() => photosInputRef.current?.click()}>
          <ImageIcon size={18} />
          Choose from Photos
        </button>
        <button className="ghost-button" type="button" onClick={() => fileInputRef.current?.click()}>
          <Upload size={18} />
          Choose Files
        </button>
      </div>
      <p className="sm-import-hint">Or drag and drop a file here.</p>
      {cameraActive && (
        <div className="camera-preview">
          <video ref={videoRef} autoPlay playsInline muted aria-label="Camera preview" />
          <button className="ghost-button" type="button" onClick={stopCamera}>Stop camera</button>
        </div>
      )}
      <p className="sm-import-note">Your music stays on this device.</p>
    </div>
  );

  return (
    <ScreenContainer className="score-practice-screen sm-screen">
      <PageHeader
        title="Sheet Music"
        description="Add a photo, PDF, or scan of your sheet music to read while you play."
        action={hasPages ? (
          <button className="ghost-button" type="button" onClick={() => setImportOpen((value) => !value)}>
            <Plus size={18} />
            Add music
          </button>
        ) : undefined}
      />

      {selected && (
        <SectionCard className="sm-viewer-card">
          <div className={`sm-viewer ${focusMode ? 'is-focus' : ''}`} ref={viewerRef}>
            <div className="sm-toolbar">
              <button className="icon-button labeled" type="button" onClick={() => { setFitWidth(true); setZoom(1); }} aria-pressed={fitWidth} title="Fit to width">
                <MoveHorizontal size={17} />Fit width
              </button>
              <button className="icon-button labeled" type="button" onClick={zoomOut} title="Zoom out">
                <ZoomOut size={17} />Zoom out
              </button>
              <button className="icon-button labeled" type="button" onClick={zoomIn} title="Zoom in">
                <ZoomIn size={17} />Zoom in
              </button>
              <button className="icon-button labeled" type="button" onClick={() => setRotation((value) => (value + 90) % 360)} title="Rotate">
                <RotateCw size={17} />Rotate
              </button>
              {selected.kind === 'pdf' && pdfPageCount > 1 && (
                <div className="sm-pager">
                  <button className="icon-button" type="button" onClick={() => setPdfPageNumber((value) => Math.max(1, value - 1))} disabled={pdfPageNumber <= 1} aria-label="Previous page"><ChevronLeft size={18} /></button>
                  <span className="sm-pager-label">Page {pdfPageNumber} / {pdfPageCount}</span>
                  <button className="icon-button" type="button" onClick={() => setPdfPageNumber((value) => Math.min(pdfPageCount, value + 1))} disabled={pdfPageNumber >= pdfPageCount} aria-label="Next page"><ChevronRight size={18} /></button>
                </div>
              )}
              <button className="icon-button labeled" type="button" onClick={toggleFullscreen} aria-pressed={focusMode} title={focusMode ? 'Exit full screen' : 'Full screen'}>
                {focusMode ? <Minimize2 size={17} /> : <Maximize2 size={17} />}
                {focusMode ? 'Exit full screen' : 'Full screen'}
              </button>
              <div className="sm-menu-wrap">
                <button className="icon-button" type="button" onClick={() => setMenuOpen((value) => !value)} aria-label="More options" aria-haspopup="menu" aria-expanded={menuOpen}><MoreVertical size={18} /></button>
                {menuOpen && (
                  <>
                    <button className="sm-menu-scrim" type="button" aria-label="Close menu" onClick={() => setMenuOpen(false)} />
                    <div className="sm-menu" role="menu">
                      <button className="sm-menu-item sm-menu-danger" type="button" role="menuitem" onClick={() => { setMenuOpen(false); setPendingDelete(true); }}>
                        <Trash2 size={17} />Delete this page
                      </button>
                    </div>
                  </>
                )}
              </div>
            </div>

            <div className={`sm-viewer-body ${showFilmstrip ? 'has-strip' : ''}`}>
              {showFilmstrip && (
                <aside className="sm-filmstrip" aria-label="Pages">
                  {pages.map((page, index) => (
                    <button className={`sm-thumb ${page.id === selected.id ? 'is-active' : ''}`} key={page.id} type="button" onClick={() => setSelectedId(page.id)}>
                      <span className="sm-thumb-img">
                        {page.kind === 'image' ? <img src={page.url} alt="" /> : <FileText size={22} />}
                      </span>
                      <span className="sm-thumb-meta">
                        <strong>Page {index + 1}</strong>
                        {!page.summary.supported && <StatusBadge tone="amber">Can’t open</StatusBadge>}
                        <em className="sm-thumb-name">{page.name}</em>
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
                      alt={`Sheet music ${selected.name}`}
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
          title={hasPages ? 'Add music' : undefined}
          action={hasPages ? (
            <button className="icon-button" type="button" onClick={() => setImportOpen(false)} aria-label="Close"><X size={18} /></button>
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
          void importFiles(Array.from(event.target.files ?? []), 'photos').finally(() => {
            event.currentTarget.value = '';
          });
        }}
        aria-label="Choose sheet music from Photos"
      />
      <input
        ref={fileInputRef}
        className="visually-hidden"
        type="file"
        accept={acceptAttribute}
        multiple
        onChange={(event) => {
          void importFiles(Array.from(event.target.files ?? []), 'files').finally(() => {
            event.currentTarget.value = '';
          });
        }}
        aria-label="Choose sheet music files"
      />

      {pendingDelete && (
        <div className="sm-confirm-backdrop" role="dialog" aria-modal="true" aria-label="Remove page">
          <div className="sm-confirm">
            <h3>Remove this page?</h3>
            <p>You can add it again anytime.</p>
            <div className="sm-confirm-actions">
              <button className="ghost-button" type="button" onClick={() => setPendingDelete(false)}>Cancel</button>
              <button className="sm-danger-button" type="button" onClick={() => void performDelete()}>
                <Trash2 size={17} />Remove
              </button>
            </div>
          </div>
        </div>
      )}
    </ScreenContainer>
  );
}
