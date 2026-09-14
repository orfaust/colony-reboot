import { useState } from 'react';
import { ColorInput, CommitInput, Field, NumberInput, RefSelect, TextInput, TextKeyInput } from './fields.jsx';
import ExtraFields from './ExtraFields.jsx';
import { buildingTypeSchema } from '../lib/schema.js';
import { WORLD_SCALE } from '../lib/game.js';
import { clone, contrastText, isPlainObject, moveItem, objectItems, rgbToHex, uniqueName } from '../lib/object.js';

function uniqueCode(base, taken) {
  const set = new Set(taken);
  if (!set.has(base)) return base;
  for (let i = 2; ; i++) if (!set.has(`${base}${i}`)) return `${base}${i}`;
}

function newBuilding(id, data) {
  const initials = id.split('_').map((p) => p.charAt(0).toUpperCase()).join('').slice(0, 3) || 'NB';
  return {
    id,
    name_key: `building_${id}_name`,
    description_key: `building_${id}_description`,
    code: uniqueCode(initials, data.map((b) => b?.code)),
    width: 1.5,
    height: 1.5,
    color: { r: 200, g: 200, b: 200 },
    power_need_kw: 0,
    power_output_kw: 0,
    needs: [],
    produces: [],
  };
}

function SizePreview({ building }) {
  const w = Math.max(0, Number(building.width) || 0) * WORLD_SCALE;
  const h = Math.max(0, Number(building.height) || 0) * WORLD_SCALE;
  const scale = Math.min(1, 220 / Math.max(w, h, 1));
  return (
    <div className="size-preview">
      <div
        className="size-box"
        style={{ width: w * scale, height: h * scale, background: rgbToHex(building.color), color: contrastText(building.color) }}
      >
        {building.code}
      </div>
      <small>
        {w}×{h} screen units in game{scale < 1 ? ` (preview at ${Math.round(scale * 100)}%)` : ''}
      </small>
    </div>
  );
}

function RecipeList({ title, addLabel, items, amountField, amountHint, resources, onChange }) {
  const list = Array.isArray(items) ? items : [];
  const options = resources.map((r) => ({ value: r.id, label: r.id }));
  const patch = (i, change) => onChange(list.map((it, j) => (j === i ? { ...it, ...change } : it)));
  return (
    <fieldset className="recipe">
      <legend>{title}</legend>
      {list.length === 0 && <p className="empty small">None</p>}
      {list.map((item, i) => (
        <div className="recipe-row" key={i}>
          <RefSelect value={item.resource_id} options={options} onChange={(v) => patch(i, { resource_id: v })} />
          <NumberInput value={item[amountField]} min={0} step={0.01} title={amountField} onChange={(v) => patch(i, { [amountField]: v })} />
          <span className="unit-label">{amountHint(item)}</span>
          <button type="button" className="btn tiny ghost danger" onClick={() => onChange(list.filter((_, j) => j !== i))}>
            ✕
          </button>
        </div>
      ))}
      <button
        type="button"
        className="btn tiny"
        disabled={resources.length === 0}
        title={resources.length === 0 ? 'Define resources in config/resources.json first' : undefined}
        onClick={() => onChange([...list, { resource_id: resources[0].id, [amountField]: 1 }])}
      >
        + {addLabel}
      </button>
    </fieldset>
  );
}

/** Instances in level files that reference a building type id. */
function levelReferences(docs, id) {
  return Object.entries(docs)
    .filter(([path, doc]) => path.startsWith('levels/') && Array.isArray(doc.data?.buildings))
    .map(([path, doc]) => [path, doc.data.buildings.filter((b) => b?.building_id === id).length])
    .filter(([, count]) => count > 0);
}

function BuildingForm({ index, building, data, onChange, ctx }) {
  const resources = objectItems(ctx.resources);
  const set = (field, value) => onChange({ ...building, [field]: value }, `${index}.${field}`);
  const unitOf = (id) => ctx.texts?.[resources.find((r) => r.id === id)?.unit_type_key] ?? 'unit';
  const codeTaken = data.some((b, i) => i !== index && b?.code === building.code);

  const renameId = (next) => {
    next = next.trim();
    if (!next || data.some((b, i) => i !== index && b?.id === next)) return false;
    const refs = levelReferences(ctx.docs, building.id);
    onChange({ ...building, id: next });
    const total = refs.reduce((sum, [, n]) => sum + n, 0);
    if (total && confirm(`${total} level instance(s) reference "${building.id}" (${refs.map(([p]) => p).join(', ')}).\nUpdate them to "${next}"?`))
      for (const [path] of refs)
        ctx.updateDoc(path, (level) => ({
          ...level,
          buildings: level.buildings.map((b) => (b?.building_id === building.id ? { ...b, building_id: next } : b)),
        }));
    return true;
  };

  return (
    <div className="form">
      <ExtraFields value={building} schema={buildingTypeSchema} onChange={(v) => onChange(v)} />
      <div className="form-grid">
        <Field label="ID" hint="Unique; referenced by level instances as building_id (applied on Enter/blur)">
          <CommitInput value={building.id ?? ''} onCommit={renameId} spellCheck={false} />
        </Field>
        <Field label="Code" hint="Unique short code shown in the scene" error={codeTaken ? 'Code already used' : null}>
          <TextInput value={building.code} onChange={(v) => set('code', v)} spellCheck={false} />
        </Field>
        <Field label="Name key" wide>
          <TextKeyInput value={building.name_key} onChange={(v) => set('name_key', v)} texts={ctx.texts} onCreateKey={ctx.onCreateTextKey} />
        </Field>
        <Field label="Description key" wide>
          <TextKeyInput
            value={building.description_key}
            onChange={(v) => set('description_key', v)}
            texts={ctx.texts}
            onCreateKey={ctx.onCreateTextKey}
          />
        </Field>
      </div>

      <div className="form-split">
        <div className="form-grid">
          <Field label="Width" hint="World units (> 0)" error={!(building.width > 0) ? 'Must be positive' : null}>
            <NumberInput value={building.width} min={0} step={0.1} onChange={(v) => set('width', v)} />
          </Field>
          <Field label="Height" hint="World units (> 0)" error={!(building.height > 0) ? 'Must be positive' : null}>
            <NumberInput value={building.height} min={0} step={0.1} onChange={(v) => set('height', v)} />
          </Field>
          <Field label="Color" wide>
            <ColorInput value={building.color} onChange={(v) => set('color', v)} />
          </Field>
          <Field label="Power need" hint="kW (≥ 0)">
            <NumberInput value={building.power_need_kw} min={0} onChange={(v) => set('power_need_kw', v)} />
          </Field>
          <Field label="Power output" hint="kW (≥ 0)">
            <NumberInput value={building.power_output_kw} min={0} onChange={(v) => set('power_output_kw', v)} />
          </Field>
        </div>
        <SizePreview building={building} />
      </div>

      <div className="form-split">
        <RecipeList
          title="Needs"
          addLabel="Add need"
          items={building.needs}
          amountField="amount_per_unit"
          amountHint={(it) => `${unitOf(it.resource_id)} per produced unit`}
          resources={resources}
          onChange={(v) => set('needs', v)}
        />
        <RecipeList
          title="Produces"
          addLabel="Add product"
          items={building.produces}
          amountField="time_per_unit"
          amountHint={(it) => `hours per ${unitOf(it.resource_id)}` + (it.time_per_unit > 0 ? ` (${+(1 / it.time_per_unit).toFixed(3)}/h)` : '')}
          resources={resources}
          onChange={(v) => set('produces', v)}
        />
      </div>
    </div>
  );
}

export default function BuildingsEditor({ data, onChange, ctx }) {
  const [selected, setSelected] = useState(0);
  if (!Array.isArray(data)) return <p className="empty">Expected an array of building types. Fix the file in the JSON tab.</p>;
  const current = selected !== null && selected < data.length ? selected : null;
  const building = current !== null ? data[current] : null;

  const add = () => {
    const id = uniqueName('new_building', data.map((b) => b?.id));
    onChange([...data, newBuilding(id, data)]);
    setSelected(data.length);
  };
  const duplicate = (index) => {
    const copy = clone(data[index]);
    if (isPlainObject(copy)) {
      copy.id = uniqueName(`${copy.id}_copy`, data.map((b) => b?.id));
      copy.code = uniqueCode(copy.code, data.map((b) => b?.code));
    }
    onChange([...data.slice(0, index + 1), copy, ...data.slice(index + 1)]);
    setSelected(index + 1);
  };
  const remove = (index) => {
    const id = data[index]?.id;
    const refs = levelReferences(ctx.docs, id);
    const warning = refs.length ? `\nIt is still used by ${refs.map(([p, n]) => `${n} instance(s) in ${p}`).join(', ')}.` : '';
    if (!confirm(`Delete building type "${id}"?${warning}`)) return;
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
          <h3>Building types ({data.length})</h3>
          <button type="button" className="btn tiny" onClick={add}>
            + New
          </button>
        </div>
        <ul className="item-list">
          {data.map((b, index) => (
            <li key={index}>
              <button type="button" className={current === index ? 'active' : ''} onClick={() => setSelected(index)}>
                <span className="swatch" style={{ background: rgbToHex(b?.color) }} />
                <span className="item-title">{ctx.texts?.[b?.name_key] ?? b?.id}</span>
                <span className="item-meta">{b?.code}</span>
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
        {current === null && <p className="empty">Select a building type on the left.</p>}
        {current !== null && (
          <>
            <div className="detail-header">
              <div>
                <span className="eyebrow">Building type #{current}</span>
                <h2>{ctx.texts?.[building?.name_key] ?? building?.id}</h2>
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
            {isPlainObject(building) ? (
              <BuildingForm
                key={current}
                index={current}
                building={building}
                data={data}
                ctx={ctx}
                onChange={(next, historyKey) => onChange(data.map((b, i) => (i === current ? next : b)), historyKey)}
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
