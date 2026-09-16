import PathInput from './PathInput.jsx';
import { useCatalogSelection } from './useCatalogSelection.js';
import { ColorInput, Field, RefSelect, TextInput, TextKeyInput } from './fields.jsx';
import ExtraFields from './ExtraFields.jsx';
import { isPlainObject, moveItem, rgbToHex } from '../lib/object.js';
import { SUBJECT_ROLES, roleSchema, validateRoles } from '../lib/schema.js';
import { newRole } from '../lib/roles.js';

export default function SubjectRolesEditor({ data, onChange, ctx }) {
  const [selected, setSelected] = useCatalogSelection(ctx.gridSelection);
  if (!Array.isArray(data)) return <p className="callout error">Expected a role array. Repair it in the JSON tab.</p>;
  const issues = validateRoles(data, ctx.texts);
  const missing = SUBJECT_ROLES.filter((id) => !data.some((r) => r?.id === id));
  const current = selected !== null && selected < data.length ? selected : null;
  const role = current === null ? null : data[current];
  // Read this row's key, not a lookup by ID: duplicate IDs must remain repairable.
  const label = (entry, index) => typeof ctx.texts?.[entry?.name_key] === 'string' ? ctx.texts[entry.name_key]
    : typeof entry?.id === 'string' ? entry.id : `Invalid role #${index}`;
  const add = () => {
    if (!missing.length) return;
    onChange([...data, newRole(missing[0])]);
    setSelected(data.length);
  };
  const move = (from, to) => {
    onChange(moveItem(data, from, to));
    if (current === from) setSelected(to);
    else if (current === to) setSelected(from);
  };
  const remove = () => {
    if (!confirm('Remove this required role? Validation will fail until it is restored.')) return;
    onChange(data.filter((_, i) => i !== current));
    setSelected(null);
  };
  const set = (key, value) => onChange(data.map((r, i) => i === current ? { ...r, [key]: value } : r), `$[${current}].${key}`);
  const error = (key) => issues.filter((e) => e.path === `$[${current}].${key}`).map((e) => e.message).join('; ');
  return <div className="master-detail">
    <aside className="panel list-panel" aria-label="Subject roles">
      <div className="list-header"><h3><button type="button" className="catalog-grid-title" onClick={ctx.onOpenGrid} title="Open editable grid">Subject roles ({data.length})</button></h3>
        <button type="button" className="btn tiny" disabled={!missing.length} onClick={add}>Add missing role</button>
      </div>
      {data.length === 0 && <p className="empty small">No roles. Add the required roles to begin.</p>}
      <ul className="item-list">{data.map((entry, i) => <li key={i}>
        <button type="button" className={current === i ? 'active' : ''} aria-pressed={current === i} onClick={() => setSelected(i)}>
          <span className="swatch" style={{ background: rgbToHex(entry?.color) }} />
          <span className="item-title">{label(entry, i)}</span>
          <span className="item-meta">{typeof entry?.id === 'string' ? entry.id : `#${i}`}</span>
        </button>
        <span className="reorder">
          <button type="button" className="btn tiny ghost" aria-label={`Move role ${i} up`} disabled={i === 0} onClick={() => move(i, i - 1)}>↑</button>
          <button type="button" className="btn tiny ghost" aria-label={`Move role ${i} down`} disabled={i === data.length - 1} onClick={() => move(i, i + 1)}>↓</button>
        </span>
      </li>)}</ul>
    </aside>
    <section className="panel detail-panel">
      {current === null ? <p className="empty">Select a role on the left.</p> : <>
        <div className="detail-header"><div><span className="eyebrow">Subject role #{current}</span><h2>{label(role, current)}</h2></div>
          <button type="button" className="btn danger" onClick={remove}>Remove</button>
        </div>
        <p className="hint">Metadata for worker, supervisor and repairer. Optional PNG paths are validated by python tools/build.py; empty paths use color.</p>
        {!isPlainObject(role) ? <p className="callout error">Invalid role at index {current}. Repair it in the JSON tab.</p> : <div key={current}>
          <ExtraFields value={role} schema={roleSchema} onChange={(next) => onChange(data.map((r, i) => i === current ? next : r))} />
          <div className="form-grid">
            <Field label="ID" error={error('id')}><RefSelect value={role.id} options={SUBJECT_ROLES.map((id) => ({ value: id }))} onChange={(id) => set('id', id)} /></Field>
            <Field label="Name key" error={error('name_key')}><TextKeyInput value={role.name_key} texts={ctx.texts} onCreateKey={ctx.onCreateTextKey} onEditKey={ctx.onEditTextKey} onRenameKey={ctx.onRenameTextKey} onChange={(v) => set('name_key', v)} /></Field>
            <Field label="Color" error={error('color')}><ColorInput value={role.color} onChange={(v) => set('color', v)} /></Field>
            <Field label="Sprite path" hint="Optional PNG path. Empty uses color; python tools/build.py checks files." error={error('sprite')}><PathInput value={role.sprite} onChange={(v) => set('sprite', v)} /></Field>
          </div>
        </div>}
      </>}
    </section>
  </div>;
}
