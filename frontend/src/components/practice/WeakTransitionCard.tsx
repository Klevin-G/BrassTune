import { Target } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { generateWeakTransitionDrill, type TransitionEvent } from '../../domain/transitionDrills';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';

export function WeakTransitionCard({ events }: { events: TransitionEvent[] }) {
  const navigate = useNavigate();
  const { saveExercise } = usePracticeLibrary();
  const drill = generateWeakTransitionDrill(events);
  return (
    <SectionCard title="Transition drill" eyebrow="Built only when there is enough evidence">
      {!drill.ready ? <p className="muted-copy">{drill.reason}</p> : (
        <div className="practice-feature-stack">
          <p><strong>{drill.from} → {drill.to}</strong> averaged {drill.averageError}¢ off across {drill.evidenceCount} examples.</p>
          <p className="muted-copy">Suggested pattern: {drill.notes.join(' · ')}</p>
          <button className="ghost-button" type="button" onClick={() => {
            const exercise = saveExercise({ name: `${drill.from} to ${drill.to} transition`, notes: drill.notes, source: 'generated' });
            navigate(`/practice/play-along?exercise=${encodeURIComponent(exercise.id)}`);
          }}><Target size={17} />Save and practice this drill</button>
        </div>
      )}
    </SectionCard>
  );
}
