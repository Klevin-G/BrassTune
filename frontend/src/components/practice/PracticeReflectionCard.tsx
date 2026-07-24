import { Check, Pencil, Trash2, X } from 'lucide-react';
import { useState } from 'react';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';

export function PracticeReflectionCard({ sessionId }: { sessionId?: string }) {
  const { library, saveReflection, updateReflection, deleteReflection } = usePracticeLibrary();
  const { t, formatDate } = useI18n();
  const [text, setText] = useState('');
  const [saved, setSaved] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editText, setEditText] = useState('');
  const reflections = sessionId == null
    ? library.reflections
    : library.reflections.filter((reflection) => reflection.sessionId === sessionId);
  return (
    <SectionCard title={t('reflection.title')} eyebrow={t('reflection.eyebrow')}>
      <form className="practice-feature-stack" onSubmit={(event) => {
        event.preventDefault();
        if (saveReflection(text, sessionId)) {
          setText('');
          setSaved(true);
        }
      }}>
        <label className="field"><span>{t('reflection.prompt')}</span><textarea maxLength={280} rows={3} value={text} onChange={(event) => { setText(event.target.value); setSaved(false); }} /></label>
        <div className="practice-actions"><button className="ghost-button" type="submit" disabled={!text.trim()}>{t('reflection.save')}</button><span className="muted-copy">{text.length}/280</span></div>
        {saved && <p role="status" className="practice-success">{t('reflection.saved')}</p>}
      </form>
      {reflections.length > 0 && (
        <div className="practice-reflection-list" aria-label={t('reflection.list')}>
          <h3>{t('reflection.list')}</h3>
          {reflections.map((reflection) => {
            const editing = editingId === reflection.id;
            return (
              <article className="practice-reflection" key={reflection.id}>
                {editing ? (
                  <label className="field">
                    <span>{t('reflection.edit')}</span>
                    <textarea maxLength={280} rows={3} value={editText} onChange={(event) => setEditText(event.target.value)} />
                  </label>
                ) : <p>{reflection.text}</p>}
                <div className="practice-reflection-meta">
                  <time dateTime={reflection.createdAt}>{formatDate(new Date(reflection.createdAt), { dateStyle: 'medium', timeStyle: 'short' })}</time>
                  <div className="practice-reflection-actions">
                    {editing ? (
                      <>
                        <button className="icon-button" type="button" aria-label={t('reflection.saveChanges')} disabled={!editText.trim()} onClick={() => {
                          if (updateReflection(reflection.id, editText)) {
                            setEditingId(null);
                            setEditText('');
                          }
                        }}><Check size={16} /></button>
                        <button className="icon-button" type="button" aria-label={t('reflection.cancel')} onClick={() => { setEditingId(null); setEditText(''); }}><X size={16} /></button>
                      </>
                    ) : (
                      <button className="icon-button" type="button" aria-label={t('reflection.edit')} onClick={() => { setEditingId(reflection.id); setEditText(reflection.text); }}><Pencil size={16} /></button>
                    )}
                    <button className="icon-button" type="button" aria-label={t('reflection.delete')} onClick={() => { deleteReflection(reflection.id); if (editing) setEditingId(null); }}><Trash2 size={16} /></button>
                  </div>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </SectionCard>
  );
}
