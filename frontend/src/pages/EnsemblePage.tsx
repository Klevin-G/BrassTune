import { FileText, Music2, Plus, Printer, Target, UserPlus, Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { addEnsembleMemberByUsername, createEnsembleGroup, getEnsembleGroup, getEnsembleGroups, getEnsembleReport, getEnsembleSummary } from '../api/client';
import { NoteStatsTable } from '../components/NoteStatsTable';
import { InsightCard, PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';

export function EnsemblePage() {
  const [summary, setSummary] = useState<any>(null);
  const [report, setReport] = useState<any>(null);
  const [groups, setGroups] = useState<any[]>([]);
  const [selectedGroup, setSelectedGroup] = useState<any>(null);
  const [newGroupName, setNewGroupName] = useState('');
  const [memberUsername, setMemberUsername] = useState('');
  const [ensembleStatus, setEnsembleStatus] = useState('');
  const { instrumentId } = useAppSettings();
  const auth = useAuth();
  const canManage = auth.profile?.role === 'director' || auth.profile?.role === 'admin';

  useEffect(() => {
    Promise.all([getEnsembleSummary(), getEnsembleReport(), getEnsembleGroups()]).then(([summaryData, reportData, groupsData]) => {
      setSummary(summaryData);
      setReport(reportData);
      setGroups(groupsData);
      if (groupsData[0]) {
        getEnsembleGroup(groupsData[0].id).then(setSelectedGroup).catch(() => undefined);
      }
    });
  }, []);

  const createGroup = async () => {
    if (!newGroupName.trim()) return;
    try {
      const group = await createEnsembleGroup(newGroupName);
      setGroups((old) => [group, ...old]);
      setSelectedGroup(group);
      setNewGroupName('');
      setEnsembleStatus('Group created.');
    } catch (error) {
      setEnsembleStatus(error instanceof Error ? error.message : 'Could not create group.');
    }
  };

  const addMember = async () => {
    if (!selectedGroup?.id || !memberUsername.trim()) return;
    try {
      await addEnsembleMemberByUsername(selectedGroup.id, { username: memberUsername, instrument_id: instrumentId, role_in_group: 'student' });
      const group = await getEnsembleGroup(selectedGroup.id);
      setSelectedGroup(group);
      setMemberUsername('');
      setEnsembleStatus('Member added.');
    } catch (error) {
      setEnsembleStatus(error instanceof Error ? error.message : 'Could not add member.');
    }
  };

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Ensemble"
        title="Director briefing"
        description="A local report view for seeing section-level intonation tendencies and turning them into a rehearsal focus."
        action={
          <button className="primary-button" onClick={() => window.print()} type="button">
            <Printer size={18} />
            Export report
          </button>
        }
      />
      <SectionCard title="Roster admin" eyebrow={canManage ? 'Director tools' : 'Student view'}>
        <div className="ensemble-admin-grid">
          <div className="mini-stat-list">
            {groups.map((group) => (
              <button className="mini-stat-row button-row" type="button" key={group.id} onClick={() => getEnsembleGroup(group.id).then(setSelectedGroup)}>
                <span>{group.name}</span>
                <strong>{selectedGroup?.id === group.id ? 'Open' : 'View'}</strong>
              </button>
            ))}
            {groups.length === 0 && <p className="muted-copy">No ensembles are visible for this account yet.</p>}
          </div>
          <div className="inline-panel">
            <h3>{selectedGroup?.name ?? 'No group selected'}</h3>
            <div className="roster-list">
              {selectedGroup?.members?.map((member: any) => (
                <div className="history-row" key={member.id}>
                  <span>@{member.username ?? member.user_id}</span>
                  <strong>{member.instrument_id}</strong>
                  <em>{member.status}</em>
                </div>
              ))}
            </div>
            {canManage && (
              <div className="settings-actions">
                <label className="field compact-field">
                  <span>New group</span>
                  <input value={newGroupName} onChange={(event) => setNewGroupName(event.target.value)} placeholder="Concert Brass" />
                </label>
                <button className="ghost-button" type="button" onClick={createGroup}>
                  <Plus size={17} />
                  Create
                </button>
                <label className="field compact-field">
                  <span>Add by username</span>
                  <input value={memberUsername} onChange={(event) => setMemberUsername(event.target.value.toLowerCase())} placeholder="avery" />
                </label>
                <button className="ghost-button" type="button" onClick={addMember}>
                  <UserPlus size={17} />
                  Add
                </button>
              </div>
            )}
            {ensembleStatus && <p className="settings-status">{ensembleStatus}</p>}
          </div>
        </div>
      </SectionCard>
      <SectionCard title="Section trends" eyebrow="Brass sections">
        <div className="section-trend-grid">
          {summary?.sections?.map((section: any) => (
            <article key={section.instrument_id}>
              <span>{section.instrument_id}</span>
              <strong>{section.average_abs_cents.toFixed(1)}c</strong>
              <p>{section.session_count} sessions, {section.practice_minutes} minutes</p>
            </article>
          ))}
        </div>
      </SectionCard>
      <div className="insight-grid">
        <InsightCard
          title="Briefing summary"
          detail="Director handoff"
          body={report?.recommended_rehearsal_focus ?? 'Seed data will populate the rehearsal focus when the backend is running.'}
          icon={FileText}
          tone="gold"
        />
        <InsightCard
          title="Long-tone sequence"
          detail={`${report?.suggested_long_tone_sequence?.length ?? 0} steps`}
          body="Use the sequence as a section warmup before repertoire excerpts."
          icon={Music2}
          tone="green"
        />
        <InsightCard
          title="Priority lens"
          detail="Top problem notes"
          body="The table below ranks note issues by severity across the seeded ensemble sessions."
          icon={Target}
          tone="amber"
        />
      </div>
      <SectionCard title="Rehearsal focus" eyebrow="Suggested sequence">
        <div className="plan-steps">
          {report?.suggested_long_tone_sequence?.map((item: string, index: number) => (
            <article key={item}>
              <span>
                <Users size={15} /> {index + 1}
              </span>
              <p>{item}</p>
            </article>
          ))}
        </div>
      </SectionCard>
      <SectionCard title="Top problem notes" eyebrow="Ensemble data">
        <NoteStatsTable rows={report?.top_problem_notes ?? []} />
      </SectionCard>
    </ScreenContainer>
  );
}
