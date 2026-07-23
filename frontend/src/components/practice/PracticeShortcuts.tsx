import { Clock3, Star } from 'lucide-react';
import { Link } from 'react-router-dom';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';

export function PracticeShortcuts() {
  const { library } = usePracticeLibrary();
  const { t } = useI18n();
  if (library.favorites.length === 0 && library.recents.length === 0) return null;
  return (
    <SectionCard title={t('shortcuts.title')} eyebrow={t('shortcuts.eyebrow')}>
      <div className="practice-shortcut-columns">
        <div>
          <h3><Star size={16} /> {t('shortcuts.favorites')}</h3>
          {library.favorites.length === 0 ? <p className="muted-copy">{t('shortcuts.emptyFavorites')}</p> : library.favorites.map((item) => <Link className="practice-shortcut" to={item.href} key={`${item.kind}:${item.id}`}>{item.label}</Link>)}
        </div>
        <div>
          <h3><Clock3 size={16} /> {t('shortcuts.recents')}</h3>
          {library.recents.length === 0 ? <p className="muted-copy">{t('shortcuts.emptyRecents')}</p> : library.recents.map((item) => <Link className="practice-shortcut" to={item.href} key={`${item.kind}:${item.id}`}>{item.label}</Link>)}
        </div>
      </div>
    </SectionCard>
  );
}
