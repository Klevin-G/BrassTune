import { Download } from 'lucide-react';
import { downloadExport } from '../api/client';

export function ExportButtons({ sessionId }: { sessionId: number }) {
  const download = (path: string, filename: string) => {
    downloadExport(path, filename).catch(() => undefined);
  };
  return (
    <div className="export-buttons">
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/session/${sessionId}.csv`, `session-${sessionId}-samples.csv`)}>
        <Download size={17} />
        Samples CSV
      </button>
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/note-events/${sessionId}.csv`, `session-${sessionId}-note-events.csv`)}>
        <Download size={17} />
        Events CSV
      </button>
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/session/${sessionId}.json`, `session-${sessionId}.json`)}>
        <Download size={17} />
        JSON
      </button>
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/session/${sessionId}.zip`, `session-${sessionId}-export.zip`)}>
        <Download size={17} />
        ZIP
      </button>
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/session/${sessionId}/audio`, `session-${sessionId}-audio`)}>
        <Download size={17} />
        Audio
      </button>
    </div>
  );
}
