import { useState } from 'react';
import { ColorInput, CommitInput, Field, TextKeyInput } from './fields.jsx';
import ExtraFields from './ExtraFields.jsx';
import { BUILDINGS_PATH, resourceSchema } from '../lib/schema.js';
import { clone, isPlainObject, moveItem, objectItems, rgbToHex, uniqueName } from '../lib/object.js';

function newResource(id) {
  return {
    id,
    name_key: `resource_${id}_name`,
    description_key: `resource_${id}_description`,
    unit_type_key: 'unit_kg',
    color: { r: 200, g: 200, b: 200 },
  };
}

/** Building types whose needs or produces reference a resource id. */
const usersOf = (buildings, id) =>
  objectItems(buildings).filter((b) => [...(b.needs ?? []), ...(b.produces ?? [])].some((r) => r?.resource_id === id));

function ResourceForm({ index, resource, data, onChange, ctx }) {
  const set = (field, value) => onChange({ ...resource, [field]: value }, `${index}.${field}`);
  const users = usersOf(ctx.buildings, resource.id);

  const renameId = (next) => {
    next = next.trim();
    if (!next || data.some((r, i) => i !== index && r?.id === next)) return false;
    onChange({ ...resource, id: next });
    if (users.length && confirm(`${users.length} building type(s) reference "${resource.id}" (${users.map((b) => b.id).join(', ')}).\nUpdate them to "${next}"?`)) {
      const swap = (list) => (Array.isArray(list) ? list.map((r) => (r?.resource_id === resource.id ? { ...r, resource_id: next } : r)) : list);
      ctx.updateDoc(BUILDINGS_PATH, (buildings) => buildings.map((b) => (isPlainObject(b) ? { ...b, needs: swap(b.needs), produces: swap(b.produces) } : b)));
    }
    return true;
  };

  return (
    <div className="form">
      <ExtraFields value={resource} schema={resourceSchema} onChange={(v) => onChange(v)} />
      <div className="form-grid">
        <Field label="ID" hint={users.length ? `Used by: ${users.map((b) => b.id).join(', ')}` : 'Not used by any building type'}>
          <CommitInput value={resource.id ?? ''} onCommit={renameId} spellCheck={false} />
        </Field>
        <Field label="Color">
          <ColorInput value={resource.color} onChange={(v) => set('color', v)} />
        </Field>
        <Field label="Name key" wide>
          <TextKeyInput value={resource.name_key} onChange={(v) => set('name_key', v)} texts={ctx.texts} onCreateKey={ctx.onCreateTextKey} />
        </Field>
        <Field label="Description key" wide>
          <TextKeyInput
            value={resource.description_key}
            onChange={(v) => set('description_key', v)}
            texts={ctx.texts}
            onCreateKey={ctx.onCreateTextKey}
          />
        </Field>
        <Field label="Unit key" wide>
          <TextKeyInput value={resource.unit_type_key} onChange={(v) => set('unit_type_key', v)} texts={ctx.texts} onCreateKey={ctx.onCreateTextKey} />
        </Field>
      </div>
    </div>
  );
}

export default function ResourcesEditor({ data, onChange, ctx }) {
  const [selected, setSelected] = useState(0);
  if (!Array.isArray(data)) return <p className="empty">Expected an array of resources. Fix the file in the JSON tab.</p>;
  const current = selected !== null && selected < data.length ? selected : null;
  const resource = current !== null ? data[current] : null;

  const add = () => {
    onChange([...data, newResource(uniqueName('new_resource', data.map((r) => r?.id)))]);
    setSelected(data.length);
  };
  const duplicate = (index) => {
    const copy = clone(data[index]);
    if (isPlainObject(copy)) copy.id = uniqueName(`${copy.id}_copy`, data.map((r) => r?.id));
    onChange([...data.slice(0, index + 1), copy, ...data.slice(index + 1)]);
    setSelected(index + 1);
  };
  const remove = (index) => {
    const id = data[index]?.id;
    const users = usersOf(ctx.buildings, id);
    const warning = users.length ? `\nIt is still used by: ${users.map((b) => b.id).join(', ')}.` : '';
    if (!confirm(`Delete resource "${id}"?${warning}`)) return;
    onChange(data.filter((_, i) => i !== index));
    setSelected(null);
  };
  const move = (index, to) => {
    onChange(moveItem(data, index, to));
    if (current === index) setSelected(to);
  };

  return (
    <div className="master-detail">
      <aside className="panel list-panel">
        <div className="list-header">
          <h3>Resources ({data.length})</h3>
          <button type="button" className="btn tiny" onClick={add}>
            + New
          </button>
        </div>
        <ul className="item-list">
          {data.map((r, index) => (
            <li key={index}>
              <button type="button" className={current === index ? 'active' : ''} onClick={() => setSelected(index)}>
                <span className="swatch" style={{ background: rgbToHex(r?.color) }} />
                <span className="item-title">{ctx.texts?.[r?.name_key] ?? r?.id}</span>
                <span className="item-meta">{ctx.texts?.[r?.unit_type_key]}</span>
              </button>
              <span className="reorder">
                <button type="button" className="btn tiny ghost" disabled={index === 0} onClick={() => move(index, index - 1)}>
                  ↑
                </button>
                <button type="button" className="btn tiny ghost" disabled={index === data.length - 1} onClick={() => move(index, index + 1)}>
                  ↓
                </button>
              </span>
            </li>
          ))}
        </ul>
      </aside>

      <section className="panel detail-panel">
        {current === null && <p className="empty">Select a resource on the left.</p>}
        {current !== null && (
          <>
            <div className="detail-header">
              <div>
                <span className="eyebrow">Resource #{current}</span>
                <h2>{ctx.texts?.[resource?.name_key] ?? resource?.id}</h2>
              </div>
              <div className="btn-row">
                <button type="button" className="btn" onClick={() => duplicate(current)}>
                  Duplicate
                </button>
                <button type="button" className="btn danger" onClick={() => remove(current)}>
                  Delete
                </button>
              </div>
            </div>
            {isPlainObject(resource) ? (
              <ResourceForm
                key={current}
                index={current}
                resource={resource}
                data={data}
                ctx={ctx}
                onChange={(next, historyKey) => onChange(data.map((r, i) => (i === current ? next : r)), historyKey)}
              />
            ) : (
              <p className="empty">This entry is not an object. Fix it in the JSON tab.</p>
            )}
          </>
        )}
      </section>
    </div>
  );
}
