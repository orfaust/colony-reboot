import { useMemo, useState } from 'react';
import { CommitInput } from './fields.jsx';
import { collectTextReferences, REQUIRED_TEXT_KEYS } from '../lib/schema.js';
import { renameKey } from '../lib/object.js';

export default function LocalizationEditor({ data, onChange, ctx }) {
  const [filter, setFilter] = useState('');
  const [newKey, setNewKey] = useState('');
  const [onlyUnused, setOnlyUnused] = useState(false);
  const refs = useMemo(() => collectTextReferences(ctx.docs), [ctx.docs]);

  const missing = [...refs.keys()].filter((k) => !(k in data));
  const needle = filter.trim().toLowerCase();
  const rows = Object.entries(data).filter(
    ([k, v]) =>
      (!needle || k.toLowerCase().includes(needle) || String(v).toLowerCase().includes(needle)) && (!onlyUnused || !refs.has(k)),
  );

  const addKey = (key, value = '') => {
    key = key.trim();
    if (!key || key in data) return;
    onChange({ ...data, [key]: value });
  };

  return (
    <div className="panel localization-editor">
      <div className="toolbar">
        <input className="input search" placeholder="Search keys or text…" value={filter} onChange={(e) => setFilter(e.target.value)} />
        <label className="checkbox">
          <input type="checkbox" checked={onlyUnused} onChange={(e) => setOnlyUnused(e.target.checked)} />
          <span>Only unreferenced</span>
        </label>
        <div className="toolbar-spacer" />
        <form
          className="inline"
          onSubmit={(e) => {
            e.preventDefault();
            addKey(newKey);
            setNewKey('');
          }}
        >
          <input className="input" placeholder="new_key_name" value={newKey} onChange={(e) => setNewKey(e.target.value)} spellCheck={false} />
          <button type="submit" className="btn primary" disabled={!newKey.trim() || newKey.trim() in data}>
            + Add key
          </button>
        </form>
      </div>

      {missing.length > 0 && (
        <div className="callout error">
          <strong>Referenced but not defined:</strong>
          {missing.map((k) => (
            <span key={k} className="chip">
              {k}
              <button type="button" className="btn tiny" onClick={() => addKey(k)}>
                + Add
              </button>
            </span>
          ))}
        </div>
      )}

      <div className="table-wrap">
        <table className="loc-table">
          <thead>
            <tr>
              <th>Key</th>
              <th>English text</th>
              <th>Used by</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map(([key, value]) => {
              const uses = refs.get(key) ?? [];
              const invalid = typeof value !== 'string' || value.trim() === '';
              return (
                <tr key={key} className={invalid ? 'invalid-row' : ''}>
                  <td>
                    <CommitInput
                      className="mono"
                      value={key}
                      spellCheck={false}
                      onCommit={(next) => {
                        next = next.trim();
                        if (!next || next in data) return false;
                        if (uses.length && !confirm(`"${key}" is referenced ${uses.length} time(s). References are not renamed automatically. Continue?`))
                          return false;
                        onChange(renameKey(data, key, next));
                        return true;
                      }}
                    />
                  </td>
                  <td>
                    <textarea
                      className={`input autosize${invalid ? ' invalid' : ''}`}
                      rows={1}
                      value={typeof value === 'string' ? value : JSON.stringify(value)}
                      placeholder="Text must not be empty"
                      onChange={(e) => onChange({ ...data, [key]: e.target.value }, `text:${key}`)}
                    />
                  </td>
                  <td className="uses" title={uses.map((u) => `${u.file} ${u.path}`).join('\n')}>
                    {REQUIRED_TEXT_KEYS.includes(key) ? <span className="badge">required</span> : null}
                    {uses.filter((u) => u.file !== 'game code').length > 0 ? (
                      <span className="badge subtle">{uses.filter((u) => u.file !== 'game code').length} ref</span>
                    ) : !REQUIRED_TEXT_KEYS.includes(key) ? (
                      <span className="badge warn">unused?</span>
                    ) : null}
                  </td>
                  <td>
                    <button
                      type="button"
                      className="btn tiny ghost danger"
                      title="Delete key"
                      onClick={() => {
                        if (uses.length && !confirm(`"${key}" is still referenced. Delete anyway?`)) return;
                        const { [key]: _removed, ...rest } = data;
                        onChange(rest);
                      }}
                    >
                      ✕
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {rows.length === 0 && <p className="empty">No keys match.</p>}
      </div>
      <p className="hint">“unused?” only reflects references found in the JSON assets; UI code may also use keys directly.</p>
    </div>
  );
}
