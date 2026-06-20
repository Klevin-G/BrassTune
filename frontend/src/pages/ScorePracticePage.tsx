import { Camera, CheckCircle2, FileText, Image as ImageIcon, Maximize2, Music2, RotateCw, Trash2, Upload, ZoomIn, ZoomOut } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { InsightCard, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { MAX_SCORE_FILE_BYTES, MAX_SCORE_PIXELS, scoreAcceptAttribute, verifiedScoreSourceKind, verifyScoreFile, type ScoreImportSummary } from '../domain/scorePractice';

interface ImportedScorePage {
  id: string;
  name: string;
  source: 'camera' | 'photos' | 'files' | 'clipboard' | 'drop';
  kind: 'pdf' | 'image';
  url: string;
  file: File;
  dimensions?: { width: number; height: number };
  summary: ScoreImportSummary;
  confirmed: boolean;
  persisted: boolean;
}

const DB_NAME = 'brasstune-score-practice';
const STORE_NAME = 'scoreDocuments';

function openScoreDb() {
  return new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore(STORE_NAME, { keyPath: 'id' });
    };
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
  });
}

async function saveScoreDocument(page: ImportedScorePage) {
  const db = await openScoreDb();
  await new Promise<void>((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    transaction.objectStore(STORE_NAME).put({
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
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    transaction.objectStore(STORE_NAME).delete(id);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
  });
  db.close();
}

async function loadScoreDocuments(): Promise<ImportedScorePage[]> {
  const db = await openScoreDb();
  const rows = await new Promise<any[]>((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const request = transaction.objectStore(STORE_NAME).getAll();
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
          label: 'Saved locally',
          quality: row.quality,
        },
        confirmed: true,
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

function formatSize(size: number) {
  if (size < 1024 * 1024) return `${Math.round(size / 1024)} KB`;
  return `${(size / 1024 / 1024).toFixed(1)} MB`;
}

export function ScorePracticePage() {
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const photosInputRef = useRef<HTMLInputElement | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const cameraStreamRef = useRef<MediaStream | null>(null);
  const pagesRef = useRef<ImportedScorePage[]>([]);
  const [pages, setPages] = useState<ImportedScorePage[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [status, setStatus] = useState('Choose a PDF, image, or camera scan. Source pages stay on this device unless you export them.');
  const [cameraActive, setCameraActive] = useState(false);
  const [zoom, setZoom] = useState(1);
  const [rotation, setRotation] = useState(0);
  const [focusMode, setFocusMode] = useState(false);
  const canUseCamera = typeof navigator !== 'undefined' && Boolean(navigator.mediaDevices?.getUserMedia);
  const selected = pages.find((page) => page.id === selectedId) ?? pages[0];

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
        setStatus(`${stored.length} saved score page${stored.length === 1 ? '' : 's'} restored from this browser.`);
      })
      .catch(() => {
        if (!cancelled) setStatus('Saved score pages could not be loaded in this browser.');
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const importFiles = async (files: File[], source: ImportedScorePage['source']) => {
    const imported: ImportedScorePage[] = [];
    for (const file of files) {
      if (file.size > MAX_SCORE_FILE_BYTES) {
        setStatus(`${file.name} is too large for local score practice.`);
        continue;
      }
      const kind = await verifiedScoreSourceKind(file);
      if (kind === 'unsupported') {
        setStatus(`${file.name} is not supported or its file contents do not match a safe PDF/image format.`);
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
        confirmed: false,
        persisted: false,
      });
    }
    if (imported.length) {
      setPages((current) => [...current, ...imported]);
      setSelectedId(imported[0].id);
      setStatus(`${imported.length} page${imported.length === 1 ? '' : 's'} ready for review.`);
    }
  };

  const startCamera = async () => {
    if (!canUseCamera) {
      setStatus('Camera scanning is unavailable in this browser. Choose Photos or Files instead.');
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false });
      cameraStreamRef.current = stream;
      if (videoRef.current) videoRef.current.srcObject = stream;
      setCameraActive(true);
      setStatus('Camera preview is active. Capture a page, then review it before practice.');
    } catch {
      setStatus('Camera permission was denied or no camera was available. Choose Photos or Files instead.');
    }
  };

  const captureCameraPage = async () => {
    const video = videoRef.current;
    if (!video || video.videoWidth === 0 || video.videoHeight === 0) {
      setStatus('Camera preview is not ready yet.');
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
      setStatus('Camera capture failed. Try again.');
      return;
    }
    await importFiles([new File([blob], `camera-score-${new Date().toISOString().slice(0, 19)}.jpg`, { type: 'image/jpeg' })], 'camera');
  };

  const confirmSelected = async () => {
    if (!selected) return;
    try {
      await saveScoreDocument(selected);
      setPages((current) => current.map((page) => (page.id === selected.id ? { ...page, confirmed: true, persisted: true } : page)));
      setStatus(`${selected.name} saved locally for score practice.`);
    } catch {
      setStatus('This browser could not save the score locally. Keep the page open or export it before closing.');
    }
  };

  const removeSelected = async () => {
    if (!selected) return;
    URL.revokeObjectURL(selected.url);
    if (selected.persisted) {
      await deleteScoreDocument(selected.id).catch(() => undefined);
    }
    setPages((current) => current.filter((page) => page.id !== selected.id));
    setSelectedId(null);
    setStatus(selected.persisted ? 'Page removed from this practice set and local storage.' : 'Page removed from this practice set.');
  };

  return (
    <ScreenContainer className="score-practice-screen">
      <PageHeader
        eyebrow="Practice with score"
        title="Score practice"
        description="Import a PDF, image, or camera capture, confirm the page quality, then practice with tuner and metronome overlays."
        meta={<StatusBadge tone="gold">Local by default</StatusBadge>}
      />
      <SectionCard title="Import score" eyebrow="Three actions">
        <div
          className="score-drop-zone"
          onDragOver={(event) => event.preventDefault()}
          onDrop={(event) => {
            event.preventDefault();
            void importFiles(Array.from(event.dataTransfer.files), 'drop');
          }}
        >
          <div className="settings-actions">
            {canUseCamera && (
              <button className="primary-button" type="button" onClick={cameraActive ? captureCameraPage : startCamera}>
                <Camera size={18} />
                {cameraActive ? 'Capture page' : 'Scan with Camera'}
              </button>
            )}
            <button className="ghost-button" type="button" onClick={() => photosInputRef.current?.click()}>
              <ImageIcon size={18} />
              Choose from Photos
            </button>
            <button className="ghost-button" type="button" onClick={() => fileInputRef.current?.click()}>
              <Upload size={18} />
              Choose Files
            </button>
          </div>
          <input ref={photosInputRef} className="visually-hidden" type="file" accept={scoreAcceptAttribute()} multiple onChange={(event) => void importFiles(Array.from(event.target.files ?? []), 'photos')} aria-label="Choose score images from Photos" />
          <input ref={fileInputRef} className="visually-hidden" type="file" accept={scoreAcceptAttribute()} multiple onChange={(event) => void importFiles(Array.from(event.target.files ?? []), 'files')} aria-label="Choose score files" />
          <p>Drag and drop or paste images here. Raw SVG is rejected instead of rendered.</p>
          {cameraActive && (
            <div className="camera-preview">
              <video ref={videoRef} autoPlay playsInline muted aria-label="Camera preview for score scanning" />
              <button className="ghost-button" type="button" onClick={stopCamera}>Stop camera</button>
            </div>
          )}
        </div>
        <p className="settings-status" aria-live="polite">{status}</p>
      </SectionCard>
      <div className="score-reader-grid">
        <SectionCard title="Pages" eyebrow={`${pages.length} imported`}>
          {pages.length === 0 ? (
            <InsightCard title="No score yet" body="Choose a file, photo, or camera capture to begin. Imported source pages are not uploaded." icon={Music2} tone="gold" />
          ) : (
            <div className="score-page-list">
              {pages.map((page, index) => (
                <button className={`score-page-row ${page.id === selected?.id ? 'active' : ''}`} key={page.id} type="button" onClick={() => setSelectedId(page.id)}>
                  <span className="insight-icon">{page.kind === 'pdf' ? <FileText size={17} /> : <ImageIcon size={17} />}</span>
                  <span>
                    <strong>Page {index + 1}</strong>
                    <em>{page.name}</em>
                  </span>
                  <StatusBadge tone={page.confirmed ? 'green' : page.summary.quality.status === 'good' ? 'gold' : 'amber'}>{page.confirmed ? 'Confirmed' : page.summary.label}</StatusBadge>
                </button>
              ))}
            </div>
          )}
        </SectionCard>
        <SectionCard title="Preview and confirm" eyebrow={selected?.source ?? 'Waiting'}>
          {selected ? (
            <div className={`score-preview-stack ${focusMode ? 'score-preview-stack-focused' : ''}`}>
              <div className="score-toolbar">
                <button className="icon-button" type="button" onClick={() => setZoom((value) => Math.min(2, value + 0.1))} aria-label="Zoom in score preview" title="Zoom in"><ZoomIn size={18} /></button>
                <button className="icon-button" type="button" onClick={() => setZoom((value) => Math.max(0.6, value - 0.1))} aria-label="Zoom out score preview" title="Zoom out"><ZoomOut size={18} /></button>
                <button className="icon-button" type="button" onClick={() => setRotation((value) => (value + 90) % 360)} aria-label="Rotate score preview" title="Rotate"><RotateCw size={18} /></button>
                <button className="icon-button" type="button" onClick={() => setFocusMode((value) => !value)} aria-label={focusMode ? 'Exit focused score preview' : 'Focus score preview'} aria-pressed={focusMode} title={focusMode ? 'Exit focus mode' : 'Focus mode'}><Maximize2 size={18} /></button>
                <button className="icon-button danger-action" type="button" onClick={() => void removeSelected()} aria-label="Remove selected score page" title="Remove"><Trash2 size={18} /></button>
              </div>
              <div className="score-preview-frame">
                {selected.kind === 'pdf' ? (
                  <iframe title={`Preview ${selected.name}`} src={selected.url} />
                ) : (
                  <img alt={`Preview ${selected.name}`} src={selected.url} style={{ transform: `scale(${zoom}) rotate(${rotation}deg)` }} />
                )}
              </div>
              <div className="insight-grid">
                <InsightCard title={selected.summary.label} detail={`${Math.round(selected.summary.quality.likelySheetMusicScore * 100)}% likely sheet music`} body={selected.summary.quality.messages.join(' ')} icon={CheckCircle2} tone={selected.summary.quality.status === 'good' ? 'green' : 'amber'} />
                <InsightCard title="Privacy" detail={`${formatSize(selected.file.size)} ${selected.file.type || selected.kind}`} body="The source page is stored locally after confirmation. Export reports should omit source pages unless you choose otherwise." icon={FileText} />
              </div>
              <div className="settings-actions">
                <button className="primary-button" type="button" onClick={confirmSelected} disabled={!selected.summary.supported || selected.confirmed}>
                  <CheckCircle2 size={18} />
                  {selected.confirmed ? 'Confirmed' : 'Confirm for practice'}
                </button>
              </div>
            </div>
          ) : (
            <InsightCard title="Preview required" body="Every imported page must be reviewed before practice. BrassTune does not silently discard images." icon={FileText} tone="gold" />
          )}
        </SectionCard>
      </div>
      <SectionCard title="Practice overlays" eyebrow="Manual alignment">
        <div className="insight-grid">
          <InsightCard title="Manual markers" detail="Rehearsal, measure, phrase" body="Use page and timestamp markers during review. Automatic score following is not claimed in this build." icon={Music2} tone="gold" />
          <InsightCard title="Metronome overlay" detail="Count-in ready" body="Open the metronome for tempo and count-in. Printed-note mismatch flags require confirmed OMR and alignment, which remain experimental." icon={CheckCircle2} />
        </div>
      </SectionCard>
    </ScreenContainer>
  );
}
