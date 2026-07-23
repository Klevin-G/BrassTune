import { Focus, Play } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { BUILT_IN_PRACTICE_PACKS } from '../../domain/practiceLibrary';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';

export function PracticePackPanel() {
  const navigate = useNavigate();
  const { t } = useI18n();
  const { startWorkspace } = usePracticeLibrary();
  return (
    <SectionCard title={t('packs.title')} eyebrow={t('packs.eyebrow')}>
      <p className="muted-copy">{t('packs.body')}</p>
      <div className="practice-pack-grid">
        {BUILT_IN_PRACTICE_PACKS.map((pack) => (
          <article className="practice-pack" key={pack.id}>
            <span><Focus size={17} /></span>
            <div><h3>{pack.id === 'daily-foundations' ? t('packs.daily.name') : t('packs.time.name')}</h3><p>{pack.id === 'daily-foundations' ? t('packs.daily.description') : t('packs.time.description')}</p><small>{t('packs.steps', { count: pack.steps.length })}</small></div>
            <button className="ghost-button" type="button" onClick={() => { startWorkspace(pack); navigate(pack.steps[0].href); }}><Play size={16} />{t('packs.start')}</button>
          </article>
        ))}
      </div>
    </SectionCard>
  );
}
