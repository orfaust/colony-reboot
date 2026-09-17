import PathInput from './PathInput.jsx';
import { useCatalogSelection } from './useCatalogSelection.js';
import { ColorInput, Field, NumberInput, RefSelect, TextInput, TextKeyInput } from './fields.jsx';
import ExtraFields from './ExtraFields.jsx';
import { isPlainObject, uniqueName, moveItem, clone, rgbToHex } from '../lib/object.js';
import { shipSchema, stationSchema, validateShips, validateStations } from '../lib/schema.js';
import { newShip, newStation, newStock } from '../lib/station.js';

// Only explicit user actions create defaults. Malformed loaded values stay visible
// to validation and can always be repaired in the JSON tab.
function FixedForm({ value, schema, onChange, ctx, issues, path = '$' }) {
  if (!isPlainObject(value)) return <p className="callout error">Expected an object. Repair it in the JSON tab.</p>;
  return <div className="form">
    <ExtraFields value={value} schema={schema} onChange={onChange} />
    <div className="form-grid">
      {Object.entries(schema.fields).map(([field, child]) => {
        const p = `${path}.${field}`;
        const set = (next) => onChange({ ...value, [field]: next }, p);
        const error = issues.filter((i) => i.level === 'error' && i.path === p).map((i) => i.message).join('; ');
        if (child.type === 'array') {
          const rows = value[field];
          const catalog = Array.isArray(ctx[field]) ? ctx[field].filter(isPlainObject) : [];
          const idField = { resources: 'resource_id', subjects: 'subject_id', ships: 'ship_id' }[field];
          const available = catalog.filter((item) => !Array.isArray(rows) || !rows.some((r) => r?.[idField] === item.id));
          const add = () => set([...rows, newStock(field, available[0]?.id ?? '')]);
          return <section className="panel wide" key={field}>
            <div className="list-header"><h3>{field}</h3><button type="button" className="btn tiny" disabled={!Array.isArray(rows) || (idField && !available.length)} onClick={add}>+ Add</button></div>
            {error && <p className="field-error">{error}</p>}
            {!Array.isArray(rows) ? <p className="callout error">Expected an array. Repair it in the JSON tab.</p> : rows.map((row, i) => {
              const rowPath = `${p}[${i}]`;
              const update = (next, historyKey) => onChange({ ...value, [field]: rows.map((r, j) => j === i ? next : r) }, historyKey);
              return <div className="panel" key={i}>
                <div className="btn-row">
                  <button type="button" className="btn tiny" disabled={i === 0} onClick={() => set(moveItem(rows, i, i - 1))}>↑</button>
                  <button type="button" className="btn tiny" disabled={i === rows.length - 1} onClick={() => set(moveItem(rows, i, i + 1))}>↓</button>
                  <button type="button" className="btn tiny danger" onClick={() => set(rows.filter((_, j) => j !== i))}>Remove</button>
                </div>
                <FixedForm value={row} schema={child.item} onChange={update} ctx={ctx} issues={issues} path={rowPath} />
              </div>;
            })}
          </section>;
        }
        const ref = { resource_id: 'resources', subject_id: 'subjects', ship_id: 'ships' }[field];
        return <Field key={field} label={field === 'distance' ? 'distance (km)' : field === 'max_speed' ? 'max_speed (km/h)' : field === 'max_speed_hours' ? 'max_speed_hours (acceleration / braking hours)' : field === 'units_per_hour' ? 'units_per_hour (cargo units loaded / unloaded per hour)' : (field === 'width' || field === 'height') ? `${field} (pixels)` : field} hint={field === 'sprite' ? 'Optional assets/.../*.png path; empty means unset. Catalog metadata only.' : undefined} error={error}>
          {field === 'color' ? <ColorInput value={isPlainObject(value.color) ? value.color : undefined} onChange={set} /> : field.endsWith('_key') ? <TextKeyInput value={value[field]} onChange={set} texts={ctx.texts} onCreateKey={ctx.onCreateTextKey} onEditKey={ctx.onEditTextKey} onRenameKey={ctx.onRenameTextKey} />
            : ref ? <RefSelect value={value[field]} options={(Array.isArray(ctx[ref]) ? ctx[ref] : []).filter(isPlainObject).map((r) => ({ value: r.id, label: ctx.texts?.[r.name_key] ?? r.id }))} onChange={set} />
              : field === 'sprite' ? <PathInput value={value[field]} onChange={set} />
              : child.type === 'string' ? <TextInput value={value[field]} onChange={set} />
                : <NumberInput value={value[field]} integer={child.type === 'int'} onChange={set} />}
        </Field>;
      })}
    </div>
  </div>;
}

function CatalogEditor({ data, onChange, ctx, title, singular, schema, create, issues }) {
  const [selected, setSelected] = useCatalogSelection(ctx.gridSelection);
  if (!Array.isArray(data)) return <p className="callout error">Expected an array. Repair it in the JSON tab.</p>;
  const current = selected !== null && selected < data.length ? selected : null;
  const item = current === null ? null : data[current];
  const label = (entry, index) => ctx.texts?.[entry?.name_key] ?? entry?.id ?? `${singular} #${index}`;
  const add = () => {
    onChange([...data, create(uniqueName(`new_${singular.toLowerCase().replaceAll(' ', '_')}`, data.map((r) => r?.id)))]);
    setSelected(data.length);
  };
  const duplicate = () => {
    const copy = clone(item);
    if (isPlainObject(copy)) copy.id = uniqueName(`${copy.id}_copy`, data.map((r) => r?.id));
    onChange([...data.slice(0, current + 1), copy, ...data.slice(current + 1)]);
    setSelected(current + 1);
  };
  const remove = () => {
    if (!confirm(`Delete ${singular.toLowerCase()} "${item?.id}"? References may need updating.`)) return;
    onChange(data.filter((_, i) => i !== current));
    setSelected(null);
  };
  const move = (from, to) => {
    onChange(moveItem(data, from, to));
    if (current === from) setSelected(to);
    else if (current === to) setSelected(from);
  };
  return <div className="master-detail">
    <aside className="panel list-panel">
      <div className="list-header"><h3><button type="button" className="catalog-grid-title" onClick={ctx.onOpenGrid} title="Open editable grid">{title} ({data.length})</button></h3><button type="button" className="btn tiny" onClick={add}>+ New</button></div>
      <ul className="item-list">{data.map((entry, i) => <li key={i}>
        <button type="button" className={current === i ? 'active' : ''} onClick={() => setSelected(i)}>
          {schema === shipSchema && <span className="swatch" style={{ background: rgbToHex(entry?.color) }} />}
          <span className="item-title">{label(entry, i)}</span><span className="item-meta">{entry?.code}</span>
        </button>
        <span className="reorder">
          <button type="button" className="btn tiny ghost" disabled={i === 0} onClick={() => move(i, i - 1)}>↑</button>
          <button type="button" className="btn tiny ghost" disabled={i === data.length - 1} onClick={() => move(i, i + 1)}>↓</button>
        </span>
      </li>)}</ul>
    </aside>
    <section className="panel detail-panel">
      {current === null ? <p className="empty">Select a {singular.toLowerCase()} on the left.</p> : <>
        <div className="detail-header"><div><span className="eyebrow">{singular} #{current}</span><h2>{label(item, current)}</h2></div>
          <div className="btn-row"><button type="button" className="btn" onClick={duplicate}>Duplicate</button><button type="button" className="btn danger" onClick={remove}>Delete</button></div>
        </div>
        <FixedForm key={current} value={item} schema={schema} ctx={ctx} issues={issues} path={`$[${current}]`}
          onChange={(next, key) => onChange(data.map((r, i) => i === current ? next : r), key)} />
      </>}
    </section>
  </div>;
}

export function SpaceStationsEditor(props) {
  return <CatalogEditor {...props} title="Space stations" singular="Space station" schema={stationSchema} create={newStation}
    issues={validateStations(props.data, props.ctx.texts, props.ctx)} />;
}

export function ShipsEditor(props) {
  return <CatalogEditor {...props} title="Ships" singular="Ship" schema={shipSchema} create={newShip}
    issues={validateShips(props.data, props.ctx.texts, props.ctx.subjects)} />;
}
