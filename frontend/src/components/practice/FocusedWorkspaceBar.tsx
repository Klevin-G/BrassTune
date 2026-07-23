import { ArrowLeft, ArrowRight, X } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';

export function FocusedWorkspaceBar() {
  const navigate = useNavigate();
  const { workspace, moveWorkspace, exitWorkspace } = usePracticeLibrary();
  if (!workspace) return null;
  const step = workspace.pack.steps[workspace.stepIndex];
  const go = (index: number) => {
    moveWorkspace(index);
    navigate(workspace.pack.steps[index].href);
  };
  return (
    <aside className="focus-workspace" aria-label="Focused practice workspace">
      <div><small>{workspace.pack.name} · Step {workspace.stepIndex + 1} of {workspace.pack.steps.length}</small><strong>{step.label}</strong><span>{step.instruction}</span></div>
      <div className="focus-workspace-actions">
        <button className="ghost-button" type="button" disabled={workspace.stepIndex === 0} onClick={() => go(workspace.stepIndex - 1)} aria-label="Previous practice step"><ArrowLeft size={17} /></button>
        <button className="primary-button" type="button" disabled={workspace.stepIndex === workspace.pack.steps.length - 1} onClick={() => go(workspace.stepIndex + 1)}>Next <ArrowRight size={17} /></button>
        <button className="ghost-button" type="button" onClick={exitWorkspace}><X size={17} /> Exit focus</button>
      </div>
    </aside>
  );
}
