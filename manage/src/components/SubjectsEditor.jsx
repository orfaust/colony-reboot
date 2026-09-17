import PathInput from './PathInput.jsx';
import { useCatalogSelection } from './useCatalogSelection.js';
import { ColorInput, CommitInput, Field, NumberInput, TextInput, TextKeyInput } from './fields.jsx';
import ExtraFields from './ExtraFields.jsx';
import { RecipeList } from './BuildingsEditor.jsx';
import { followIdRename } from '../lib/textKeys.js';
import { BUILDINGS_PATH, SPRITE_PATH_ERROR, validSpritePath, subjectTypeSchema } from '../lib/schema.js';
import SubjectRoleAssignments from './SubjectRoleAssignments.jsx';
import { clone, isPlainObject, moveItem, objectItems, rgbToHex, uniqueName } from '../lib/object.js';

function newSubject(id) {
  return {
    id,
    sprite: '',
    width: 64,
    height: 64,
    name_key: `subject_${id}_name`,
    color: { r: 200, g: 200, b: 200 },
    rest_time: 0,
    work_time: 0,
    extra_work_time: 0,
    min_work_health: 0.4,
    min_colony_health: 0.1,
    health_rates: { work_gain_per_hour: 0, rest_gain_per_hour: 0, extra_work_loss_per_hour: 0, max_inactivity_loss_per_hour: 0, inactivity_max_time: 0, station_recovery_per_hour: 0 },
    roles: null,
    needs: [],
    produces: [],
  };
}

/** Subjects in level files that reference a subject type id. */
function levelReferences(docs, id) {
  return Object.entries(docs)
    .filter(([path, doc]) => path.startsWith('levels/') && Array.isArray(doc.data?.subjects))
    .map(([path, doc]) => [path, doc.data.subjects.filter((s) => s?.subject_id === id).length])
    .filter(([, count]) => count > 0);
}

/** Building types whose residents.type is a subject type id. */
const hostsOf = (buildings, id) => objectItems(buildings).filter((b) => isPlainObject(b.residents) && b.residents.type === id);

function SubjectForm({ index, subject, data, onChange, ctx }) {
  const resources = objectItems(ctx.resources);
  const set = (field, value) => onChange({ ...subject, [field]: value }, `${index}.${field}`);
  const rates = isPlainObject(subject.health_rates) ? subject.health_rates : {};
  const setRate = (field, value) => onChange({ ...subject, health_rates: { ...rates, [field]: value } }, `${index}.health_rates.${field}`);
  const unitOf = (id) => ctx.texts?.[resources.find((r) => r.id === id)?.unit_type_key] ?? 'unit';

  const renameId = (next) => {
    next = next.trim();
    if (!next || data.some((s, i) => i !== index && s?.id === next)) return false;
    const refs = levelReferences(ctx.docs, subject.id);
    onChange({ ...followIdRename(subject, 'subject', subject.id, next, ctx), id: next });
    const total = refs.reduce((sum, [, n]) => sum + n, 0);
    if (total && confirm(`${total} level subject(s) reference "${subject.id}" (${refs.map(([p]) => p).join(', ')}).\nUpdate them to "${next}"?`))
      for (const [path] of refs)
        ctx.updateDoc(path, (level) => ({
          ...level,
          subjects: level.subjects.map((s) => (s?.subject_id === subject.id ? { ...s, subject_id: next } : s)),
        }));
    const hosts = hostsOf(ctx.buildings, subject.id);
    if (hosts.length && confirm(`${hosts.length} building type(s) host "${subject.id}" (${hosts.map((b) => b.id).join(', ')}).\nUpdate their residents.type to "${next}"?`))
      ctx.updateDoc(BUILDINGS_PATH, (buildings) =>
        buildings.map((b) => (isPlainObject(b) && isPlainObject(b.residents) && b.residents.type === subject.id ? { ...b, residents: { ...b.residents, type: next } } : b)),
      );
    return true;
  };

  return (
    <div className="form">
      <ExtraFields value={subject} schema={subjectTypeSchema} onChange={(v) => onChange(v)} />
      <div className="form-grid">
        <Field label="ID" hint="Unique; referenced by level subjects as subject_id (applied on Enter/blur); the name key follows it">
          <CommitInput value={subject.id ?? ''} onCommit={renameId} spellCheck={false} />
        </Field>
        <Field label="Sprite path" hint="Optional assets/.../*.png path; empty means unset. Catalog metadata only." error={validSpritePath(subject.sprite) ? null : SPRITE_PATH_ERROR}>
          <PathInput value={subject.sprite} onChange={(v) => set('sprite', v)} />
        </Field>
        {['width', 'height'].map((field) => (
          <Field key={field} label={`${field} (pixels)`} hint="Positive pixel dimension at 100% zoom; catalog metadata only." error={typeof subject[field] === 'number' && Number.isFinite(Math.fround(subject[field])) && Math.fround(subject[field]) > 0 ? null : 'Must be a finite positive f32'}>
            <NumberInput value={subject[field]} onChange={(v) => set(field, v)} />
          </Field>
        ))}
        <Field label="Color" hint="Distinguishes this subject type">
          <ColorInput value={subject.color} onChange={(v) => set('color', v)} />
        </Field>
        <Field label="Name key" wide>
          <TextKeyInput value={subject.name_key} onChange={(v) => set('name_key', v)} texts={ctx.texts} onCreateKey={ctx.onCreateTextKey} onEditKey={ctx.onEditTextKey} onRenameKey={ctx.onRenameTextKey} />
        </Field>
        <Field label="Rest time" hint="Consecutive hours it must rest (≥ 0)" error={subject.rest_time < 0 ? 'Must be ≥ 0' : null}>
          <NumberInput value={subject.rest_time} min={0} onChange={(v) => set('rest_time', v)} />
        </Field>
        <Field label="Work time" hint="Consecutive hours it can work (≥ 0)" error={subject.work_time < 0 ? 'Must be ≥ 0' : null}>
          <NumberInput value={subject.work_time} min={0} onChange={(v) => set('work_time', v)} />
        </Field>
        <Field label="Extra work time" hint="Maximum overtime hours after work_time (≥ 0)" error={subject.extra_work_time < 0 ? 'Must be ≥ 0' : null}>
          <NumberInput value={subject.extra_work_time} min={0} onChange={(v) => set('extra_work_time', v)} />
        </Field>
        <Field label="Min work health" hint="Health floor to start or continue work; 0 < value ≤ 1 and above min colony health">
          <NumberInput value={subject.min_work_health} min={0} onChange={(v) => set('min_work_health', v)} />
        </Field>
        <Field label="Min colony health" hint="Medical evacuation threshold; 0 ≤ value < min work health">
          <NumberInput value={subject.min_colony_health} min={0} onChange={(v) => set('min_colony_health', v)} />
        </Field>
      </div>
      <fieldset className="recipe">
        <legend>Health rates</legend>
        <p className="hint">Nonnegative hourly magnitudes; logic decides gain or loss and clamps health to [0,1].</p>
        <div className="form-grid">
          {[
            ['work_gain_per_hour', 'Work gain / hour'],
            ['rest_gain_per_hour', 'Rest gain / hour'],
            ['extra_work_loss_per_hour', 'Extra work loss / hour'],
            ['max_inactivity_loss_per_hour', 'Max inactivity loss / hour'],
            ['inactivity_max_time', 'Inactivity max time (hours)'],
            ['station_recovery_per_hour', 'Station recovery / hour'],
          ].map(([field, label]) => (
            <Field key={field} label={label} error={typeof rates[field] === 'number' && Number.isFinite(Math.fround(rates[field])) && rates[field] >= 0 ? null : 'Must be a finite nonnegative number'}>
              <NumberInput value={rates[field]} min={0} onChange={(v) => setRate(field, v)} />
            </Field>
          ))}
        </div>
      </fieldset>
      <SubjectRoleAssignments key={index} value={subject.roles} subjectSprite={subject.sprite} ctx={ctx} onChange={(value, field) => onChange({ ...subject, roles: value }, `${index}.roles${field ? `.${field}` : ''}`)} />
      <div className="form-split">
        <RecipeList
          title="Needs"
          addLabel="Add need"
          items={subject.needs}
          amountFields={['amount_per_hour']}
          amountHint={(it) => `${unitOf(it.resource_id)} per hour`}
          extraFields={[
            { field: 'shortage_alert_time', label: 'Shortage alert (hours before complaining)' },
            { field: 'shortage_max_time', label: 'Shortage max (hours before dying/shutdown)' },
            { field: 'satisfied_health_gain_per_hour', label: 'Satisfied health gain / hour' },
            { field: 'max_shortage_health_loss_per_hour', label: 'Max shortage health loss / hour' },
          ]}
          resources={resources}
          onChange={(v) => set('needs', v)}
        />
        <RecipeList
          title="Produces"
          addLabel="Add product"
          items={subject.produces}
          amountFields={['units_per_hour']}
          amountHint={(it) => `${unitOf(it.resource_id)} per hour`}
          resources={resources}
          onChange={(v) => set('produces', v)}
        />
      </div>
    </div>
  );
}

export default function SubjectsEditor({ data, onChange, ctx }) {
  const [selected, setSelected] = useCatalogSelection(ctx.gridSelection);
  if (!Array.isArray(data)) return <p className="empty">Expected an array of subject types. Fix the file in the JSON tab.</p>;
  const current = selected !== null && selected < data.length ? selected : null;
  const subject = current !== null ? data[current] : null;

  const add = () => {
    onChange([...data, newSubject(uniqueName('new_subject', data.map((s) => s?.id)))]);
    setSelected(data.length);
  };
  const duplicate = (index) => {
    const copy = clone(data[index]);
    if (isPlainObject(copy)) copy.id = uniqueName(`${copy.id}_copy`, data.map((s) => s?.id));
    onChange([...data.slice(0, index + 1), copy, ...data.slice(index + 1)]);
    setSelected(index + 1);
  };
  const remove = (index) => {
    const id = data[index]?.id;
    const refs = levelReferences(ctx.docs, id);
    const hosts = hostsOf(ctx.buildings, id);
    const uses = [...refs.map(([p, n]) => `${n} subject(s) in ${p}`), ...(hosts.length ? [`residents of ${hosts.map((b) => b.id).join(', ')}`] : [])];
    const warning = uses.length ? `\nIt is still used by ${uses.join(', ')}.` : '';
    if (!confirm(`Delete subject type "${id}"?${warning}`)) return;
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
          <h3><button type="button" className="catalog-grid-title" onClick={ctx.onOpenGrid} title="Open editable grid">Subject types ({data.length})</button></h3>
          <button type="button" className="btn tiny" onClick={add}>
            + New
          </button>
        </div>
        {data.length === 0 && <p className="empty small">No subject types yet.</p>}
        <ul className="item-list">
          {data.map((s, index) => (
            <li key={index}>
              <button type="button" className={current === index ? 'active' : ''} onClick={() => setSelected(index)}>
                <span className="swatch" style={{ background: rgbToHex(s?.color) }} />
                <span className="item-title">{ctx.texts?.[s?.name_key] ?? s?.id}</span>
                <span className="item-meta">{s?.id}</span>
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
        {current === null && <p className="empty">Select a subject type on the left, or create one.</p>}
        {current !== null && (
          <>
            <div className="detail-header">
              <div>
                <span className="eyebrow">Subject type #{current}</span>
                <h2>{ctx.texts?.[subject?.name_key] ?? subject?.id}</h2>
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
            {isPlainObject(subject) ? (
              <SubjectForm
                key={current}
                index={current}
                subject={subject}
                data={data}
                ctx={ctx}
                onChange={(next, historyKey) => onChange(data.map((s, i) => (i === current ? next : s)), historyKey)}
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
