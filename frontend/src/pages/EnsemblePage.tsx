import { FileText, Plus, Printer, Trash2, UserPlus, Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  addEnsembleMemberByUsername,
  createEnsembleGroup,
  friendlyUserFacingError,
  getEnsembleGroup,
  getEnsembleGroups,
  getEnsembleReport,
  getEnsembleRoster,
  getEnsembleSummary,
  removeEnsembleMember,
  type EnsembleRosterStudent,
} from '../api/client';
import { NoteStatsTable } from '../components/NoteStatsTable';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';

function relativeWhen(value: string | null): string {
  if (!value) return 'Never';
  const then = new Date(value).getTime();
  if (Number.isNaN(then)) return 'Never';
  const days = Math.floor((Date.now() - then) / 86_400_000);
  if (days <= 0) return 'Today';
  if (days === 1) return 'Yesterday';
  if (days < 7) return `${days}d ago`;
  if (days < 30) return `${Math.floor(days / 7)}w ago`;
  return `${Math.floor(days / 30)}mo ago`;
}

export function EnsemblePage() {
  const [summary, setSummary] = useState<any>(null);
  const [report, setReport] = useState<any>(null);
  const [roster, setRoster] = useState<EnsembleRosterStudent[] | null>(null);
  const [groups, setGroups] = useState<any[]>([]);
  const [selectedGroup, setSelectedGroup] = useState<any>(null);
  const [newGroupName, setNewGroupName] = useState('');
  const [memberUsername, setMemberUsername] = useState('');
  const [ensembleStatus, setEnsembleStatus] = useState('');
  const [loading, setLoading] = useState(true);
  const { instrumentId } = useAppSettings();
  const auth = useAuth();
  const myId = auth.profile?.id;

  const managesGroup = (group: any): boolean => {
    if (auth.profile?.role === 'director' || auth.profile?.role === 'admin') return true;
    return group?.director_user_id != null && group.director_user_id === myId;
  };
  const managesSelected = managesGroup(selectedGroup);
  const hasDirectorReport = Boolean(managesSelected && selectedGroup && report);

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
      if (managesGroup(group)) {
        const [summaryData, reportData, rosterData] = await Promise.all([
          getEnsembleSummary(groupId).catch(() => null),
          getEnsembleReport(groupId).catch(() => null),
          getEnsembleRoster(groupId).catch(() => null),
        ]);
        setSummary(summaryData);
        setReport(reportData);
        setRoster(rosterData?.students ?? null);
      } else {
        setSummary(null);
        setReport(null);
        setRoster(null);
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
      setRoster(null);
      setEnsembleStatus('');
      setLoading(false);
      return;
    }
    setLoading(true);
    getEnsembleGroups()
      .then((groupsData) => {
        setGroups(groupsData);
        if (groupsData[0]) {
          return selectGroup(groupsData[0].id);
        }
        setSelectedGroup(null);
        setSummary(null);
        setReport(null);
        setRoster(null);
        return undefined;
      })
      .catch((error) => setEnsembleStatus(friendlyUserFacingError(error, 'Could not load ensemble data.')))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [auth.isSignedIn]);

  const createGroup = async () => {
    if (!newGroupName.trim()) {
      setEnsembleStatus('Enter a name for your ensemble first.');
      return;
    }
    try {
      const group = await createEnsembleGroup(newGroupName);
      setNewGroupName('');
      setEnsembleStatus(`“${group.name}” created — you're the director. Add students by username below.`);
      await auth.refreshProfile().catch(() => undefined);
      const groupsData = await getEnsembleGroups();
      setGroups(groupsData);
      await selectGroup(group.id);
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not create the ensemble.'));
    }
  };

  const addMember = async () => {
    if (!selectedGroup?.id) {
      setEnsembleStatus('Select an ensemble before adding a student.');
      return;
    }
    if (!memberUsername.trim()) {
      setEnsembleStatus('Enter the student’s username first.');
      return;
    }
    try {
      await addEnsembleMemberByUsername(selectedGroup.id, { username: memberUsername, instrument_id: instrumentId, role_in_group: 'student' });
      setMemberUsername('');
      setEnsembleStatus('Student added.');
      await selectGroup(selectedGroup.id);
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not add the student. Check the username is exact.'));
    }
  };

  const removeMember = async (memberId: number, label: string) => {
    if (!selectedGroup?.id) return;
    if (!window.confirm(`Remove ${label} from this ensemble? Their own practice data is not deleted.`)) return;
    try {
      await removeEnsembleMember(selectedGroup.id, memberId);
      setEnsembleStatus(`${label} removed.`);
      await selectGroup(selectedGroup.id);
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not remove the student.'));
    }
  };

  if (!auth.isSignedIn) {
    return (
      <ScreenContainer>
        <PageHeader
          eyebrow="Ensemble"
          title="Ensembles"
          description="Create a class or section, add your students, and see how each one is practicing."
        />
        <SectionCard title="Sign in to use ensembles" eyebrow="Free to start">
          <div className="inline-panel">
            <h3>An account keeps rosters private and synced</h3>
            <p className="muted-copy">Guest practice stays on this device. Ensembles need a signed-in account so membership and student data stay private and follow you across devices.</p>
            {auth.configured ? (
              <Link to="/?next=/ensemble" className="primary-button">Sign in or create an account</Link>
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
        title="Ensembles"
        description="Create a class or section, add students by username, and track how each one is practicing."
        action={hasDirectorReport ? (
          <button className="primary-button" onClick={() => window.print()} type="button">
            <Printer size={18} />
            Print report
          </button>
        ) : undefined}
      />

      {/* Create / start an ensemble — available to everyone (self-serve). */}
      <SectionCard title="Start an ensemble" eyebrow="You become the director">
        <p className="muted-copy">Name a class, section, or studio. You’ll be able to add students by their BrassTune username and see each student’s practice minutes and intonation.</p>
        <div className="ensemble-create-row">
          <input
            className="ensemble-create-input"
            value={newGroupName}
            onChange={(event) => setNewGroupName(event.target.value)}
            placeholder="e.g. Period 3 Brass"
            onKeyDown={(event) => { if (event.key === 'Enter') createGroup(); }}
          />
          <button className="primary-button" type="button" onClick={createGroup} disabled={!newGroupName.trim()}>
            <Plus size={18} />
            Create ensemble
          </button>
        </div>
      </SectionCard>

      {groups.length === 0 ? (
        <SectionCard title="No ensembles yet" eyebrow="Get started">
          <div className="ensemble-empty">
            <span className="brand-mark"><Users size={20} /></span>
            <div>
              <h3>You’re not in any ensembles yet</h3>
              <p className="muted-copy">Create one above to start a roster, or ask your director to add your username so you show up on theirs.</p>
              {auth.profile?.username && <p className="muted-copy">Your username: <strong>@{auth.profile.username}</strong></p>}
            </div>
          </div>
        </SectionCard>
      ) : (
        <SectionCard title={selectedGroup?.name ?? 'Roster'} eyebrow={managesSelected ? 'Director view' : 'Your ensemble'}>
          {groups.length > 1 && (
            <div className="ensemble-group-tabs">
              {groups.map((group) => (
                <button
                  key={group.id}
                  type="button"
                  className={`chip-tab ${selectedGroup?.id === group.id ? 'active' : ''}`}
                  onClick={() => selectGroup(group.id)}
                  disabled={loading}
                >
                  {group.name}
                </button>
              ))}
            </div>
          )}

          {managesSelected ? (
            <>
              <div className="settings-actions ensemble-add-row">
                <label className="field compact-field">
                  <span>Add student by username</span>
                  <input value={memberUsername} onChange={(event) => setMemberUsername(event.target.value.toLowerCase())} placeholder="student-username" onKeyDown={(event) => { if (event.key === 'Enter') addMember(); }} />
                </label>
                <button className="ghost-button" type="button" onClick={addMember} disabled={!memberUsername.trim()}>
                  <UserPlus size={17} />
                  Add student
                </button>
              </div>
              {roster && roster.length > 0 ? (
                <div className="table-wrap">
                  <table className="roster-table">
                    <thead>
                      <tr>
                        <th>Student</th>
                        <th>Instrument</th>
                        <th>Minutes</th>
                        <th>Sessions</th>
                        <th>Avg error</th>
                        <th>In tune</th>
                        <th>Last practice</th>
                        <th aria-label="Actions" />
                      </tr>
                    </thead>
                    <tbody>
                      {roster.map((student) => (
                        <tr key={student.member_id}>
                          <td>{student.display_name ?? (student.username ? `@${student.username}` : 'Student')}</td>
                          <td>{student.instrument_id}</td>
                          <td>{student.practice_minutes}</td>
                          <td>{student.sessions_count}</td>
                          <td>{student.average_abs_cents != null ? `${student.average_abs_cents}c` : '—'}</td>
                          <td>{student.in_tune_percentage != null ? `${student.in_tune_percentage}%` : '—'}</td>
                          <td>{relativeWhen(student.last_practice_at)}</td>
                          <td>
                            <button
                              className="icon-button danger-action"
                              type="button"
                              aria-label={`Remove ${student.display_name ?? student.username ?? 'student'}`}
                              onClick={() => removeMember(student.member_id, student.display_name ?? (student.username ? `@${student.username}` : 'this student'))}
                            >
                              <Trash2 size={16} />
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <p className="muted-copy">No students yet. Add your first student by their username above. Practice stats appear here once they practice after joining.</p>
              )}
            </>
          ) : (
            <div className="roster-list">
              {(selectedGroup?.members ?? []).map((member: any) => (
                <div className="history-row" key={member.id}>
                  <span>{memberLabel(member)}</span>
                  <strong>{member.instrument_id}</strong>
                  <em>{member.status}</em>
                </div>
              ))}
              {(selectedGroup?.members ?? []).length === 0 && <p className="muted-copy">This ensemble has no visible members.</p>}
            </div>
          )}
          {ensembleStatus && <p className="settings-status" role="status" aria-live="polite">{ensembleStatus}</p>}
        </SectionCard>
      )}

      {hasDirectorReport && (
        <>
          <SectionCard title="Section trends" eyebrow="By instrument">
            <div className="section-trend-grid">
              {(summary?.sections ?? []).map((section: any) => (
                <article key={section.instrument_id}>
                  <span>{section.instrument_id}</span>
                  <strong>{section.average_abs_cents.toFixed(1)}c</strong>
                  <p>{section.session_count} sessions, {section.practice_minutes} minutes</p>
                </article>
              ))}
              {(summary?.sections ?? []).length === 0 && <p className="muted-copy">Section trends appear once your students log practice.</p>}
            </div>
          </SectionCard>
          {report?.recommended_rehearsal_focus && (
            <SectionCard title="Rehearsal focus" eyebrow="Suggested" >
              <p>{report.recommended_rehearsal_focus}</p>
              <div className="plan-steps">
                {(report.suggested_long_tone_sequence ?? []).map((item: string, index: number) => (
                  <article key={item}>
                    <span><FileText size={15} /> {index + 1}</span>
                    <p>{item}</p>
                  </article>
                ))}
              </div>
            </SectionCard>
          )}
          {(report?.top_problem_notes ?? []).length > 0 && (
            <SectionCard title="Top problem notes" eyebrow="Across the ensemble">
              <NoteStatsTable rows={report.top_problem_notes ?? []} />
            </SectionCard>
          )}
        </>
      )}
    </ScreenContainer>
  );
}
