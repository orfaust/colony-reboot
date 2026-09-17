import { useState } from 'react';
import { Field, RefSelect } from './fields.jsx';
import PathInput from './PathInput.jsx';
import ExtraFields from './ExtraFields.jsx';
import { SUBJECT_ROLES, subjectRoleSchema, validSpritePath, SPRITE_PATH_ERROR } from '../lib/schema.js';
import { roleLabel } from '../lib/roles.js';
import { isPlainObject, moveItem } from '../lib/object.js';

export default function SubjectRoleAssignments({ value, onChange, ctx, subjectSprite = '' }) {
  const [selected, select] = useState(0);
  const [adding, setAdding] = useState('');
  const malformed = value !== null && !Array.isArray(value);
  const rows = Array.isArray(value) ? value : [];
  const index = selected !== null && selected < rows.length ? selected : null;
  const item = index === null ? null : rows[index];
  const available = SUBJECT_ROLES.filter((id) => !rows.some((r) => r?.role_id === id));
  const addId = available.includes(adding) ? adding : available[0] ?? '';
  const update = (next, field) => onChange(rows.map((r, i) => i === index ? next : r), `${index}.${field}`);
  const reorder = (from, to) => {
    onChange(moveItem(rows, from, to));
    if (index === from) select(to);
    else if (index === to) select(from);
  };
  const label = (row, i) => typeof row?.role_id === 'string' ? roleLabel(row.role_id, ctx) : `Invalid role ${i + 1}`;
  const duplicate = rows.some((r, i) => i !== index && r?.role_id === item?.role_id);
  const repairId = SUBJECT_ROLES.includes(item) && available.includes(item) ? item : addId;
  return <section className="panel subject-role-assignments">
    <div className="detail-header"><h3>Roles</h3><span className="muted">{rows.length} assigned</span></div>
    <p className="hint">Assign each role at most once. An empty sprite override falls back to the subject sprite, then to the subject color.</p>
    {malformed && <div className="callout error">Expected an array or null. Loaded data has not been converted.
      <button type="button" className="btn danger" onClick={() => {
        if (confirm('Replace malformed roles with null (no roles)? This can be undone.')) { onChange(null); select(null); }
      }}>Reset to no roles</button>
    </div>}
    <div className="master-detail">
      <aside className="panel list-panel" aria-label="Assigned subject roles">
        <div className="list-header"><h3>Assigned roles</h3></div>
        {!rows.length && <p className="empty small">No roles.</p>}
        <ul className="item-list">{rows.map((r, i) => <li key={i}>
          <button type="button" className={i === index ? 'active' : ''} aria-pressed={i === index} onClick={() => select(i)}>
            <span className="item-title">{label(r, i)}</span>
            <span className="item-meta">{typeof r?.sprite === 'string' && r.sprite ? 'Override' : 'Inherited'}</span>
          </button>
          <span className="reorder">
            <button type="button" className="btn tiny ghost" aria-label={`Move role ${i} up`} disabled={i === 0} onClick={() => reorder(i, i - 1)}>↑</button>
            <button type="button" className="btn tiny ghost" aria-label={`Move role ${i} down`} disabled={i === rows.length - 1} onClick={() => reorder(i, i + 1)}>↓</button>
          </span>
        </li>)}</ul>
        <div className="subject-role-add">
          <label className="field"><span>Add role</span><select className="input" value={addId} disabled={malformed || !available.length} onChange={(e) => setAdding(e.target.value)}>
            {!available.length && <option value="">All roles assigned</option>}
            {available.map((id) => <option key={id} value={id}>{roleLabel(id, ctx)}</option>)}
          </select></label>
          <button type="button" className="btn" disabled={malformed || !addId} onClick={() => { if (malformed || !addId) return; onChange([...rows, { role_id: addId, sprite: '' }]); select(rows.length); }}>+ Add role</button>
        </div>
      </aside>
      <div className="panel detail-panel">
        {index === null ? <p className="empty">Select a role on the left, or add one.</p> : <>
          <div className="detail-header"><h3>{label(item, index)}</h3>
            <button type="button" className="btn danger" onClick={() => {
              if (!confirm(`Remove ${label(item, index)}? Level subjects using this role may need updating.`)) return;
              const next = rows.filter((_, i) => i !== index); onChange(next.length ? next : null); select(null);
            }}>Remove role</button>
          </div>
          {isPlainObject(item) ? <div key={index} className="form">
            <ExtraFields value={item} schema={subjectRoleSchema} onChange={(next) => update(next, 'extra')} />
            <Field label="Role" error={!SUBJECT_ROLES.includes(item.role_id) ? 'Choose a supported role.' : duplicate ? 'Duplicate role: each role may appear only once.' : null}>
              <RefSelect value={typeof item.role_id === 'string' ? item.role_id : ''}
                options={SUBJECT_ROLES.filter((id) => id === item.role_id || available.includes(id)).map((id) => ({ value: id, label: roleLabel(id, ctx) }))}
                onChange={(role_id) => update({ ...item, role_id }, 'role_id')} />
            </Field>
            <Field label="Sprite path" hint="Optional assets/.../*.png override; empty uses the subject sprite." error={validSpritePath(item.sprite) ? null : SPRITE_PATH_ERROR}>
              <PathInput value={item.sprite} onChange={(sprite) => update({ ...item, sprite }, 'sprite')} />
            </Field>
            <p className="hint">Subject sprite: <code>{subjectSprite || '(none — color fallback)'}</code></p>
          </div> : <div className="callout error">Invalid role entry. Repair it in JSON or replace it explicitly.
            <button type="button" className="btn" disabled={!repairId} onClick={() => update({ role_id: repairId, sprite: '' }, 'repair')}>Repair as object</button>
          </div>}
        </>}
      </div>
    </div>
  </section>;
}
