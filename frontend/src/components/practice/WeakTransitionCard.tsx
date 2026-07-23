import { Target } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { generateWeakTransitionDrill, type TransitionEvent } from '../../domain/transitionDrills';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';

export function WeakTransitionCard({ events }: { events: TransitionEvent[] }) {
  const { t, formatNumber } = useI18n();
  const navigate = useNavigate();
  const { saveExercise } = usePracticeLibrary();
  const drill = generateWeakTransitionDrill(events);
  return (
    <SectionCard title={t('transition.title')} eyebrow={t('transition.eyebrow')}>
      {!drill.ready ? <p className="muted-copy">{t('transition.noEvidence')}</p> : (
        <div className="practice-feature-stack">
          <p>{t('transition.body', { from: drill.from, to: drill.to, cents: formatNumber(drill.averageError), count: formatNumber(drill.evidenceCount) })}</p>
          <p className="muted-copy">{t('transition.pattern', { notes: drill.notes.join(' · ') })}</p>
          <button className="ghost-button" type="button" onClick={() => {
            const exercise = saveExercise({ name: t('transition.name', { from: drill.from, to: drill.to }), notes: drill.notes, source: 'generated' });
            navigate(`/practice/play-along?exercise=${encodeURIComponent(exercise.id)}`);
          }}><Target size={17} />{t('transition.save')}</button>
        </div>
      )}
    </SectionCard>
  );
}
