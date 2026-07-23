import { ArrowLeft, ArrowRight, X } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { useI18n } from '../../i18n/LocaleContext';

export function FocusedWorkspaceBar() {
  const navigate = useNavigate();
  const { workspace, moveWorkspace, exitWorkspace } = usePracticeLibrary();
  const { t } = useI18n();
  if (!workspace) return null;
  const step = workspace.pack.steps[workspace.stepIndex];
  const go = (index: number) => {
    moveWorkspace(index);
    navigate(workspace.pack.steps[index].href);
  };
  return (
    <aside className="focus-workspace" aria-label={t('workspace.label')}>
      <div><small>{t('workspace.step', { name: workspace.pack.name, current: workspace.stepIndex + 1, total: workspace.pack.steps.length })}</small><strong>{step.label}</strong><span>{step.instruction}</span></div>
      <div className="focus-workspace-actions">
        <button className="ghost-button" type="button" disabled={workspace.stepIndex === 0} onClick={() => go(workspace.stepIndex - 1)} aria-label={t('workspace.previous')}><ArrowLeft size={17} /></button>
        <button className="primary-button" type="button" disabled={workspace.stepIndex === workspace.pack.steps.length - 1} onClick={() => go(workspace.stepIndex + 1)}>{t('workspace.next')} <ArrowRight size={17} /></button>
        <button className="ghost-button" type="button" onClick={exitWorkspace}><X size={17} /> {t('workspace.exit')}</button>
      </div>
    </aside>
  );
}
