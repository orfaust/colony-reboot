import { Checkbox, NumberInput } from './fields.jsx';
import { SUBJECT_ROLES } from '../lib/schema.js';
import { isPlainObject } from '../lib/object.js';
import { newBuildingRole, updateBuildingRole } from '../lib/buildingRoles.js';

export const newBuildingRoles = () => ['supervisor', 'worker', 'repairer'].map(newBuildingRole);

export default function BuildingSubjectRoles({ value, onChange, ctx }) {
  const catalog = Array.isArray(ctx.subject_roles) ? ctx.subject_roles : [];
  const roles = catalog.filter((role) => isPlainObject(role) && typeof role.id === 'string');
  const ids = roles.map((role) => role.id);
  const validArray = Array.isArray(value);
  const extraRows = validArray ? value.filter((row) => !isPlainObject(row) || !ids.includes(row.role_id)) : [];
  return <section className="panel building-subject-roles">
    <h3>Subject roles</h3>
    <p className="hint">One row per catalog role. Missing assignments show defaults and are added only when edited. Required is staffing metadata, not an activation gate.</p>
    {!validArray && <p className="callout error">Expected an array. Repair subject_roles in the JSON tab; loaded data has not been converted.</p>}
    {extraRows.length > 0 && <p className="callout error">{extraRows.length} unknown or malformed assignment(s) preserved. Repair them in the JSON tab.</p>}
    {!roles.length ? <p className="empty">No subject roles available. Load or repair config/subject_roles.json.</p> : <div className="table-wrap">
      <table className="building-roles-table">
        <thead><tr><th scope="col">Role name</th><th scope="col">Quantity</th><th scope="col">Required</th></tr></thead>
        <tbody>{roles.map((role, i) => {
          const matches = validArray ? value.filter((row) => isPlainObject(row) && row.role_id === role.id) : [];
          const duplicate = matches.length > 1 || ids.filter((id) => id === role.id).length > 1;
          const blocked = !validArray || duplicate || !SUBJECT_ROLES.includes(role.id);
          const row = matches[0] ?? newBuildingRole(role.id);
          const name = ctx.texts?.[role.name_key] ?? role.id;
          const update = (field, next) => onChange(updateBuildingRole(value, role.id, field, next), `${role.id}.${field}`);
          const quantityOk = typeof row.quantity === 'number' && Number.isFinite(Math.fround(row.quantity)) && row.quantity >= 0;
          return <tr key={i}>
            <th scope="row">{name}
              {!matches.length && <small className="field-hint">Not configured</small>}
              {blocked && <p className="field-error">{duplicate ? 'Duplicate role: repair in the JSON tab.' : 'Invalid role or assignments: repair the JSON data.'}</p>}
            </th>
            <td><fieldset disabled={blocked} className="role-cell">
              <NumberInput aria-label={`${name}: quantity`} min={0} value={row.quantity} onChange={(next) => update('quantity', next)} />
              {!quantityOk && <p className="field-error">Expected a finite nonnegative quantity.</p>}
            </fieldset></td>
            <td><fieldset disabled={blocked} className="role-cell">
              <Checkbox checked={row.required === true} label={`${name}: required`} onChange={(next) => update('required', next)} />
              {typeof row.required !== 'boolean' && <p className="field-error">Choose required or optional.</p>}
            </fieldset></td>
          </tr>;
        })}</tbody>
      </table>
    </div>}
  </section>;
}
