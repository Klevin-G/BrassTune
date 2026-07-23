import { Focus, Play } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { BUILT_IN_PRACTICE_PACKS } from '../../domain/practiceLibrary';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';

export function PracticePackPanel() {
  const navigate = useNavigate();
  const { startWorkspace } = usePracticeLibrary();
  return (
    <SectionCard title="Offline practice packs" eyebrow="Focused, step-by-step practice">
      <p className="muted-copy">Pack instructions and the app shell work offline after your first visit. Microphone, account sync, and audio files still need their normal browser or network access.</p>
      <div className="practice-pack-grid">
        {BUILT_IN_PRACTICE_PACKS.map((pack) => (
          <article className="practice-pack" key={pack.id}>
            <span><Focus size={17} /></span>
            <div><h3>{pack.name}</h3><p>{pack.description}</p><small>{pack.steps.length} focused steps</small></div>
            <button className="ghost-button" type="button" onClick={() => { startWorkspace(pack); navigate(pack.steps[0].href); }}><Play size={16} />Start pack</button>
          </article>
        ))}
      </div>
    </SectionCard>
  );
}
