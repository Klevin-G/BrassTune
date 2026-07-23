import { Clock3, Star } from 'lucide-react';
import { Link } from 'react-router-dom';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';
import { EXERCISES, type Exercise } from '../../domain/playAlong';
import type { PracticeTarget } from '../../domain/practiceLibrary';
import type { MessageId } from '../../i18n/messages.base';

type ShortcutTranslator = (id: MessageId, values?: Record<string, string | number>) => string;

function builtInPlayAlongLabel(exercise: Exercise, t: ShortcutTranslator) {
  const root = exercise.label.split(' ')[0];
  if (exercise.group === 'major') return t('playAlong.majorLabel', { note: root });
  if (exercise.group === 'minor') return t('playAlong.minorLabel', { note: root });
  if (exercise.id === 'arpeggio') return t('playAlong.arpeggioLabel');
  if (exercise.id === 'chromatic') return t('playAlong.chromaticLabel');
  return t('playAlong.longTonesLabel');
}

export function resolvePracticeShortcutLabel(target: PracticeTarget, t: ShortcutTranslator) {
  if (target.kind === 'warmup' && target.id === 'guided-5') return t('warmup.title');
  if (target.kind === 'play-along') {
    const builtIn = EXERCISES.find((exercise) => exercise.id === target.id);
    if (builtIn) return builtInPlayAlongLabel(builtIn, t);
  }
  return target.label;
}

export function PracticeShortcuts() {
  const { library } = usePracticeLibrary();
  const { t } = useI18n();
  if (library.favorites.length === 0 && library.recents.length === 0) return null;
  return (
    <SectionCard title={t('shortcuts.title')} eyebrow={t('shortcuts.eyebrow')}>
      <div className="practice-shortcut-columns">
        <div>
          <h3><Star size={16} /> {t('shortcuts.favorites')}</h3>
          {library.favorites.length === 0 ? <p className="muted-copy">{t('shortcuts.emptyFavorites')}</p> : library.favorites.map((item) => <Link className="practice-shortcut" to={item.href} key={`${item.kind}:${item.id}`}>{resolvePracticeShortcutLabel(item, t)}</Link>)}
        </div>
        <div>
          <h3><Clock3 size={16} /> {t('shortcuts.recents')}</h3>
          {library.recents.length === 0 ? <p className="muted-copy">{t('shortcuts.emptyRecents')}</p> : library.recents.map((item) => <Link className="practice-shortcut" to={item.href} key={`${item.kind}:${item.id}`}>{resolvePracticeShortcutLabel(item, t)}</Link>)}
        </div>
      </div>
    </SectionCard>
  );
}
