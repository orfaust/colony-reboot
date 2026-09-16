import { Field, NumberInput, UnitsPerHourInput, RefSelect } from './fields.jsx';
import ExtraFields from './ExtraFields.jsx';
import { isPlainObject, objectItems } from '../lib/object.js';
import { stationInstanceSchema, validateStationInstance } from '../lib/schema.js';
import { syncStationInstance } from '../lib/station.js';

export default function LevelStationEditor({ value, onChange, ctx }) {
  const stations = objectItems(ctx.space_stations);
  const station = stations.find((s) => s.id === value?.station_id);
  const issues = validateStationInstance(value, ctx.space_stations);
  const errors = (path) => issues.filter((i) => i.path === path).map((i) => i.message).join('; ');
  return <section className="panel">
    <div className="detail-header"><h3>Space station</h3>
      <button type="button" className="btn" disabled={!station} onClick={() => onChange(syncStationInstance(value, station))}>Sync stock with template</button>
    </div>
    <Field label="Station template" error={errors('$.space_station.station_id')} hint="One station per level. Capacities and ships come from the template.">
      <RefSelect value={value?.station_id} options={stations.map((s) => ({ value: s.id, label: ctx.texts?.[s.name_key] ?? s.id }))}
        onChange={(id) => {
          if (isPlainObject(value) && !confirm('Change station template? Matching stock values will be kept; other entries will be replaced.')) return;
          onChange(syncStationInstance(value, stations.find((s) => s.id === id)));
        }} />
    </Field>
    {!isPlainObject(value) ? <p className="callout error">Select a station template to configure this level.</p> : <>
      <ExtraFields value={value} schema={stationInstanceSchema} onChange={onChange} />
      <Field label="Distance (km)" error={errors('$.space_station.distance')} hint="Distance from this level's colony.">
        <NumberInput value={value.distance} min={0} onChange={(distance) => onChange({ ...value, distance }, '$.space_station.distance')} />
      </Field>
      {['resources', 'subjects'].map((field) => {
        const idField = field === 'resources' ? 'resource_id' : 'subject_id';
        const rows = Array.isArray(value[field]) ? value[field] : [];
        return <fieldset key={field} className="recipe"><legend>{field}</legend>
          {rows.map((row, i) => {
            const path = `$.space_station.${field}[${i}]`;
            if (!isPlainObject(row)) return <p key={i} className="callout error">Invalid row. Sync stock or repair it in the JSON tab.</p>;
            const definition = objectItems(station?.[field]).find((d) => d[idField] === row[idField]);
            const catalogItem = objectItems(ctx[field]).find((d) => d.id === row[idField]);
            const set = (key, next) => onChange({ ...value, [field]: rows.map((r, j) => i === j ? { ...r, [key]: next } : r) }, `${path}.${key}`);
            return <div key={i} className="panel">
              <h4>{ctx.texts?.[catalogItem?.name_key] ?? row[idField]} — capacity: {definition?.capacity ?? 'unknown'}</h4>
              <ExtraFields value={row} schema={stationInstanceSchema.fields[field].item} onChange={(next) => onChange({ ...value, [field]: rows.map((r, j) => i === j ? next : r) })} />
              <div className="form-grid">
                <Field label="Units" error={errors(`${path}.units`)}><NumberInput value={row.units} integer={field === 'subjects'} min={0} max={field === 'subjects' ? Math.floor(definition?.capacity) : definition?.capacity} onChange={(v) => set('units', v)} /></Field>
                <Field label="Units per hour" hint="Signed net rate per simulated hour" error={errors(`${path}.units_per_hour`)}><UnitsPerHourInput value={row.units_per_hour} onChange={(v) => set('units_per_hour', v)} /></Field>
              </div>
            </div>;
          })}
        </fieldset>;
      })}
    </>}
    {issues.length > 0 && <div className="callout error">{issues.map((issue, i) => <p key={i}>{issue.path}: {issue.message}</p>)}</div>}
  </section>;
}
