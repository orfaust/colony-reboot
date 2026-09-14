import { useEffect, useRef, useState } from 'react';

export default function RawEditor({ data, onChange }) {
  const serialized = JSON.stringify(data, null, 2);
  const [text, setText] = useState(serialized);
  const [error, setError] = useState(null);
  const focused = useRef(false);

  // Resync from the document unless the user is typing (e.g. after undo or a visual edit).
  useEffect(() => {
    if (!focused.current) {
      setText(serialized);
      setError(null);
    }
  }, [serialized]);

  const update = (next) => {
    setText(next);
    try {
      const parsed = JSON.parse(next);
      setError(null);
      if (JSON.stringify(parsed, null, 2) !== serialized) onChange(parsed, 'raw');
    } catch (e) {
      setError(e.message);
    }
  };

  return (
    <div className="raw-editor">
      <textarea
        spellCheck={false}
        value={text}
        onFocus={() => (focused.current = true)}
        onBlur={() => {
          focused.current = false;
          if (!error) setText(serialized);
        }}
        onChange={(e) => update(e.target.value)}
        onKeyDown={(e) => {
          if (e.key !== 'Tab') return;
          e.preventDefault();
          const el = e.currentTarget;
          const { selectionStart: s, selectionEnd: end } = el;
          update(text.slice(0, s) + '  ' + text.slice(end));
          requestAnimationFrame(() => el.setSelectionRange(s + 2, s + 2));
        }}
      />
      <div className={`raw-status${error ? ' error' : ''}`}>
        {error ? `Invalid JSON — changes are not applied: ${error}` : 'Valid JSON · edits apply immediately'}
      </div>
    </div>
  );
}
