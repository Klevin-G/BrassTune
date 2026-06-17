import { Download } from 'lucide-react';
import { exportUrl } from '../api/client';

export function ExportButtons({ sessionId }: { sessionId: number }) {
  return (
    <div className="export-buttons">
      <a className="ghost-button" href={exportUrl(`/api/export/session/${sessionId}.csv`)}>
        <Download size={17} />
        Samples CSV
      </a>
      <a className="ghost-button" href={exportUrl(`/api/export/note-events/${sessionId}.csv`)}>
        <Download size={17} />
        Events CSV
      </a>
      <a className="ghost-button" href={exportUrl(`/api/export/session/${sessionId}.json`)}>
        <Download size={17} />
        JSON
      </a>
    </div>
  );
}

