import { Clock3, Star } from 'lucide-react';
import { Link } from 'react-router-dom';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';

export function PracticeShortcuts() {
  const { library } = usePracticeLibrary();
  if (library.favorites.length === 0 && library.recents.length === 0) return null;
  return (
    <SectionCard title="Your shortcuts" eyebrow="Saved for this practice profile">
      <div className="practice-shortcut-columns">
        <div>
          <h3><Star size={16} /> Favorites</h3>
          {library.favorites.length === 0 ? <p className="muted-copy">Use the star on an exercise or preset.</p> : library.favorites.map((item) => <Link className="practice-shortcut" to={item.href} key={`${item.kind}:${item.id}`}>{item.label}</Link>)}
        </div>
        <div>
          <h3><Clock3 size={16} /> Recently started</h3>
          {library.recents.length === 0 ? <p className="muted-copy">Tools appear here only after you start them.</p> : library.recents.map((item) => <Link className="practice-shortcut" to={item.href} key={`${item.kind}:${item.id}`}>{item.label}</Link>)}
        </div>
      </div>
    </SectionCard>
  );
}
