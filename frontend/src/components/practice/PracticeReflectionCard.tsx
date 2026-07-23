import { useState } from 'react';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';

export function PracticeReflectionCard({ sessionId }: { sessionId?: string }) {
  const { saveReflection } = usePracticeLibrary();
  const [text, setText] = useState('');
  const [saved, setSaved] = useState(false);
  return (
    <SectionCard title="Quick reflection" eyebrow="A note for your future self">
      <form className="practice-feature-stack" onSubmit={(event) => {
        event.preventDefault();
        if (saveReflection(text, sessionId)) {
          setText('');
          setSaved(true);
        }
      }}>
        <label className="field"><span>What felt better, and what will you try next?</span><textarea maxLength={280} rows={3} value={text} onChange={(event) => { setText(event.target.value); setSaved(false); }} /></label>
        <div className="practice-actions"><button className="ghost-button" type="submit" disabled={!text.trim()}>Save reflection</button><span className="muted-copy">{text.length}/280</span></div>
        {saved && <p role="status" className="practice-success">Reflection saved on this practice profile.</p>}
      </form>
    </SectionCard>
  );
}
