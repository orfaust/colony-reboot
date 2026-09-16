import { useState } from 'react';
import { TextInput } from './fields.jsx';
import ExtraFields from './ExtraFields.jsx';
import { isPlainObject, moveItem } from '../lib/object.js';
import { keyBindingsSchema, validateKeyBindings } from '../lib/schema.js';
import { KEY_DEFAULTS, normalizeInput } from '../lib/station.js';
import { DEVICE_LABELS, availableBindings, filterBindingGroups, inputLabel, nextBinding } from '../lib/bindings.js';

function BindingInput({ action, rows, index, issues, onChange }) {
  const value = normalizeInput(rows[index]);
  const device = value.split(':')[0];
  const options = availableBindings(action.id, rows, index, device);
  const known = options.includes(value);
  const errors = issues.filter((i) => i.path === `$.${action.id}[${index}]`);
  return <div className={`binding-input${errors.length ? ' has-error' : ''}`}>
    <div className="binding-input-controls">
      <select className="input binding-device" value={device} aria-label={`${action.label}: input ${index + 1} device`}
        onChange={(event) => onChange(availableBindings(action.id, rows, index, event.target.value)[0])}>
        {!Object.hasOwn(DEVICE_LABELS, device) && <option value={device}>Unknown device</option>}
        {Object.entries(DEVICE_LABELS).map(([id, label]) => <option key={id} value={id} disabled={!availableBindings(action.id, rows, index, id).length}>{label}</option>)}
      </select>
      <select className={`input binding-value${!known ? ' invalid' : ''}`} value={value} aria-invalid={errors.length > 0 || !known}
        aria-label={`${action.label}: input ${index + 1}`} onChange={(event) => onChange(event.target.value)}>
        {!known && <option value={value}>{typeof rows[index] === 'string' ? rows[index] : JSON.stringify(rows[index])} (invalid)</option>}
        {options.map((input) => <option key={input} value={input}>{inputLabel(input)}</option>)}
      </select>
    </div>
    {errors.map((issue, i) => <small className="field-error" key={i}>{issue.message}</small>)}
  </div>;
}

export default function KeyBindingsEditor({ data, onChange }) {
  const [query, setQuery] = useState('');
  const issues = validateKeyBindings(data);
  const groups = filterBindingGroups(query);
  const restoreAll = () => {
    if (confirm('Restore all default key bindings?')) onChange(structuredClone(KEY_DEFAULTS));
  };
  if (!isPlainObject(data)) return <section className="panel"><p className="callout error">Expected an object. Repair it in the JSON tab or restore defaults.</p><button className="btn" onClick={restoreAll}>Restore defaults</button></section>;
  return <section className="panel bindings-editor">
    <div className="detail-header"><div><h2>Key bindings</h2><p className="field-hint">Choose one or more inputs for each action. Changes apply after restarting the game.</p></div>
      <button type="button" className="btn" onClick={restoreAll}>Restore all defaults</button>
    </div>
    <ExtraFields value={data} schema={keyBindingsSchema} onChange={onChange} />
    <div className="bindings-toolbar">
      <TextInput value={query} onChange={setQuery} placeholder="Search actions…" aria-label="Search key binding actions" />
      <span className={`badge ${issues.length ? 'error' : ''}`}>{issues.length ? `${issues.length} errors` : 'All bindings valid'}</span>
      <span className="field-hint">Version {String(data.version ?? 'missing')}</span>
      {data.version !== 1 && <button type="button" className="btn tiny" onClick={() => onChange({ ...data, version: 1 })}>Set version to 1</button>}
    </div>
    {groups.length === 0 && <p className="empty">No matching actions. <button type="button" className="btn tiny" onClick={() => setQuery('')}>Clear search</button></p>}
    {groups.map((group) => <section className="bindings-group" key={group.title}>
      <h3>{group.title}</h3>
      {group.actions.map((action) => {
        const rows = data[action.id];
        const validArray = Array.isArray(rows);
        const actionIssues = issues.filter((i) => i.path === `$.${action.id}`);
        const changed = JSON.stringify(rows) !== JSON.stringify(KEY_DEFAULTS[action.id]);
        const set = (next) => onChange({ ...data, [action.id]: next });
        const next = validArray ? nextBinding(action.id, rows) : undefined;
        return <div className="binding-action" key={action.id}>
          <div className="binding-description"><strong>{action.label}</strong><code>{action.id}</code><small>{action.hint}</small>{changed && <span className="binding-custom">Customized</span>}</div>
          <div className="binding-assignments">
            {!validArray && <p className="field-error">Invalid binding list. Restore this action or repair it in the JSON tab.</p>}
            {validArray && rows.map((_, index) => <div className="binding-row" key={index}>
              <BindingInput action={action} rows={rows} index={index} issues={issues} onChange={(input) => set(rows.map((r, i) => index === i ? input : r))} />
              <div className="btn-row">
                <button type="button" className="btn tiny ghost" disabled={index === 0} aria-label={`Move ${action.label} input ${index + 1} up`} onClick={() => set(moveItem(rows, index, index - 1))}>↑</button>
                <button type="button" className="btn tiny ghost" disabled={index === rows.length - 1} aria-label={`Move ${action.label} input ${index + 1} down`} onClick={() => set(moveItem(rows, index, index + 1))}>↓</button>
                <button type="button" className="btn tiny danger" disabled={rows.length === 1} title="Each action requires at least one input" aria-label={`Remove ${action.label} input ${index + 1}`} onClick={() => set(rows.filter((_, i) => index !== i))}>×</button>
              </div>
            </div>)}
            {actionIssues.map((issue, i) => <small className="field-error" key={i}>{issue.message}</small>)}
            <div className="btn-row binding-actions">
              <button type="button" className="btn tiny" disabled={!next} onClick={() => set([...rows, next])}>+ Add input</button>
              <button type="button" className="btn tiny ghost" disabled={!changed} onClick={() => { if (confirm(`Restore default inputs for ${action.label}?`)) set([...KEY_DEFAULTS[action.id]]); }}>Reset action</button>
            </div>
          </div>
        </div>;
      })}
    </section>)}
  </section>;
}
