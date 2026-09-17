import { NumberInput } from './fields.jsx';
import { STAFFING_MODES, SUBJECT_ROLES } from '../lib/schema.js';
import { isPlainObject } from '../lib/object.js';
import { newBuildingRole, updateBuildingRole } from '../lib/buildingRoles.js';

export const newBuildingRoles = () => ['supervisor', 'worker', 'repairer'].map(newBuildingRole);

const MODE_LABELS = { continuous: 'Continuous', on_demand: 'On demand' };

export default function BuildingSubjectRoles({ value, onChange, ctx }) {
  const catalog = Array.isArray(ctx.subject_roles) ? ctx.subject_roles : [];
  const roles = catalog.filter((role) => isPlainObject(role) && typeof role.id === 'string');
  const ids = roles.map((role) => role.id);
  const validArray = Array.isArray(value);
  const extraRows = validArray ? value.filter((row) => !isPlainObject(row) || !ids.includes(row.role_id)) : [];
  return <section className="panel building-subject-roles">
    <h3>Subject roles</h3>
    <p className="hint">One row per catalog role. Missing assignments show defaults and are added only when edited. Staffing mode is scheduling metadata, not an activation gate.</p>
    {!validArray && <p className="callout error">Expected an array. Repair subject_roles in the JSON tab; loaded data has not been converted.</p>}
    {extraRows.length > 0 && <p className="callout error">{extraRows.length} unknown or malformed assignment(s) preserved. Repair them in the JSON tab.</p>}
    {!roles.length ? <p className="empty">No subject roles available. Load or repair subject_roles.json.</p> : <div className="table-wrap">
      <table className="building-roles-table">
        <thead><tr><th scope="col">Role name</th><th scope="col">Quantity</th><th scope="col">Staffing mode</th></tr></thead>
        <tbody>{roles.map((role, i) => {
          const matches = validArray ? value.filter((row) => isPlainObject(row) && row.role_id === role.id) : [];
          const duplicate = matches.length > 1 || ids.filter((id) => id === role.id).length > 1;
          const blocked = !validArray || duplicate || !SUBJECT_ROLES.includes(role.id);
          const row = matches[0] ?? newBuildingRole(role.id);
          const name = ctx.texts?.[role.name_key] ?? role.id;
          const update = (field, next) => onChange(updateBuildingRole(value, role.id, field, next), `${role.id}.${field}`);
          const quantityOk = Number.isInteger(row.quantity) && row.quantity >= 0;
          const modeOk = STAFFING_MODES.includes(row.staffing_mode);
          return <tr key={i}>
            <th scope="row">{name}
              {!matches.length && <small className="field-hint">Not configured</small>}
              {blocked && <p className="field-error">{duplicate ? 'Duplicate role: repair in the JSON tab.' : 'Invalid role or assignments: repair the JSON data.'}</p>}
            </th>
            <td><fieldset disabled={blocked} className="role-cell">
              <NumberInput integer aria-label={`${name}: quantity`} min={0} value={row.quantity} onChange={(next) => update('quantity', Math.round(next))} />
              {!quantityOk && <p className="field-error">Expected a nonnegative whole number of slots.</p>}
            </fieldset></td>
            <td><fieldset disabled={blocked} className="role-cell">
              <select className="input" aria-label={`${name}: staffing mode`} value={modeOk ? row.staffing_mode : ''} onChange={(e) => update('staffing_mode', e.target.value)}>
                {!modeOk && <option value="">— repair —</option>}
                {STAFFING_MODES.map((mode) => <option key={mode} value={mode}>{MODE_LABELS[mode]}</option>)}
              </select>
              {!modeOk && <p className="field-error">Choose continuous or on demand.</p>}
            </fieldset></td>
          </tr>;
        })}</tbody>
      </table>
    </div>}
  </section>;
}
