import { FileText, Music2, Plus, Printer, Target, UserPlus, Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { addEnsembleMemberByUsername, createEnsembleGroup, friendlyUserFacingError, getEnsembleGroup, getEnsembleGroups, getEnsembleReport, getEnsembleSummary } from '../api/client';
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
  const [loading, setLoading] = useState(true);
  const { instrumentId } = useAppSettings();
  const auth = useAuth();
  const canManage = auth.profile?.role === 'director' || auth.profile?.role === 'admin';
  const hasDirectorReport = Boolean(canManage && selectedGroup && report);

  const memberLabel = (member: any) => {
    if (member.is_current_user) return 'You';
    if (member.username) return `@${member.username}`;
    return member.display_name ?? 'Member';
  };

  const selectGroup = async (groupId: number) => {
    setLoading(true);
    try {
      const group = await getEnsembleGroup(groupId);
      setSelectedGroup(group);
      if (canManage) {
        const [summaryData, reportData] = await Promise.all([getEnsembleSummary(groupId), getEnsembleReport(groupId)]);
        setSummary(summaryData);
        setReport(reportData);
      } else {
        setSummary(null);
        setReport(null);
      }
      setEnsembleStatus('');
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not load ensemble data.'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!auth.isSignedIn) {
      setGroups([]);
      setSelectedGroup(null);
      setSummary(null);
      setReport(null);
      setEnsembleStatus('Sign in with an ensemble account to view roster and director reports.');
      setLoading(false);
      return;
    }
    getEnsembleGroups()
      .then((groupsData) => {
        setGroups(groupsData);
        if (groupsData[0]) {
          return selectGroup(groupsData[0].id);
        }
        setSummary(null);
        setReport(null);
        return undefined;
      })
      .catch((error) => setEnsembleStatus(friendlyUserFacingError(error, 'Could not load ensemble data.')))
      .finally(() => setLoading(false));
  }, [auth.isSignedIn, canManage]);

  const createGroup = async () => {
    if (!newGroupName.trim()) {
      setEnsembleStatus('Enter a group name before creating an ensemble.');
      return;
    }
    try {
      const group = await createEnsembleGroup(newGroupName);
      setGroups((old) => [group, ...old]);
      await selectGroup(group.id);
      setNewGroupName('');
      setEnsembleStatus('Group created.');
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not create group.'));
    }
  };

  const addMember = async () => {
    if (!selectedGroup?.id) {
      setEnsembleStatus('Choose a group before adding a member.');
      return;
    }
    if (!memberUsername.trim()) {
      setEnsembleStatus('Enter a username before adding a member.');
      return;
    }
    try {
      await addEnsembleMemberByUsername(selectedGroup.id, { username: memberUsername, instrument_id: instrumentId, role_in_group: 'student' });
      await selectGroup(selectedGroup.id);
      setMemberUsername('');
      setEnsembleStatus('Member added.');
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not add member.'));
    }
  };

  if (!auth.isSignedIn) {
    return (
      <ScreenContainer>
        <PageHeader
          eyebrow="Ensemble"
          title="Ensemble access"
          description="Sign in with an ensemble account to view roster membership and director reports."
        />
        <SectionCard title="Membership required" eyebrow="Cloud ensemble">
          <div className="inline-panel">
            <h3>Use a signed-in ensemble account</h3>
            <p className="muted-copy">Guest practice stays available, but ensemble rosters and reports require a cloud account so membership and privacy rules can be enforced.</p>
            {auth.configured ? (
              <Link to="/?next=/ensemble" className="primary-button">Sign in</Link>
            ) : (
              <p className="settings-status" role="status">Cloud sign-in is not configured in this local environment.</p>
            )}
          </div>
        </SectionCard>
      </ScreenContainer>
    );
  }

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Ensemble"
        title={canManage ? 'Director briefing' : 'Ensemble membership'}
        description={canManage ? 'See section-level intonation tendencies and turn them into a rehearsal focus.' : 'Review your visible ensemble roster membership.'}
        action={hasDirectorReport ? (
          <button className="primary-button" onClick={() => window.print()} type="button">
            <Printer size={18} />
            Print report
          </button>
        ) : undefined}
      />
      <SectionCard title={canManage ? 'Roster admin' : 'Roster'} eyebrow={canManage ? 'Director tools' : 'Student view'}>
        <div className="ensemble-admin-grid">
          <div className="mini-stat-list">
            {groups.map((group) => (
              <button className="mini-stat-row button-row" type="button" key={group.id} onClick={() => selectGroup(group.id)} disabled={loading}>
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
                  <span>{memberLabel(member)}</span>
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
                <button className="ghost-button" type="button" onClick={createGroup} disabled={!newGroupName.trim()}>
                  <Plus size={17} />
                  Create
                </button>
                <label className="field compact-field">
                  <span>Add by username</span>
                  <input value={memberUsername} onChange={(event) => setMemberUsername(event.target.value.toLowerCase())} placeholder="avery" />
                </label>
                <button className="ghost-button" type="button" onClick={addMember} disabled={!selectedGroup?.id || !memberUsername.trim()}>
                  <UserPlus size={17} />
                  Add
                </button>
              </div>
            )}
            {ensembleStatus && <p className="settings-status" role="status" aria-live="polite">{ensembleStatus}</p>}
          </div>
        </div>
      </SectionCard>
      {hasDirectorReport && (
        <>
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
              body={report.recommended_rehearsal_focus}
              icon={FileText}
              tone="gold"
            />
            <InsightCard
              title="Long-tone sequence"
              detail={`${report.suggested_long_tone_sequence?.length ?? 0} steps`}
              body="Use the sequence as a section warmup before repertoire excerpts."
              icon={Music2}
              tone="green"
            />
            <InsightCard
              title="Priority lens"
              detail="Top problem notes"
              body="The table below ranks note issues by severity across active ensemble sessions."
              icon={Target}
              tone="amber"
            />
          </div>
          <SectionCard title="Rehearsal focus" eyebrow="Suggested sequence">
            <div className="plan-steps">
              {report.suggested_long_tone_sequence?.map((item: string, index: number) => (
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
            <NoteStatsTable rows={report.top_problem_notes ?? []} />
          </SectionCard>
        </>
      )}
    </ScreenContainer>
  );
}
