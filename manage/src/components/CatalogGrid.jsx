import { useEffect, useRef, useState } from 'react';
import PathInput from './PathInput.jsx';
import { Checkbox, ColorInput, NumberInput, TextInput, TextKeyInput, UnitsPerHourInput } from './fields.jsx';
import { GRID_SCHEMAS, commonGridFields, updateGridCell } from '../lib/catalogGrid.js';
import { validateDoc } from '../lib/schema.js';

export default function CatalogGrid({ Editor, kind, path, data, onChange, ctx }) {
  const [grid, setGrid] = useState(false);
  const [gridSelection, setGridSelection] = useState(null);
  const openRow = (index) => { setGridSelection({ index }); setGrid(false); };
  const focusRow = useRef(false);
  const detailRef = useRef(null);
  const wasGrid = useRef(false);
  useEffect(() => {
    let frame;
    if (!grid && wasGrid.current) {
      const selector = focusRow.current ? '.item-list button.active' : '.catalog-grid-title';
      frame = requestAnimationFrame(() => detailRef.current?.querySelector(selector)?.focus());
    }
    wasGrid.current = grid;
    return () => { if (frame !== undefined) cancelAnimationFrame(frame); };
  }, [grid]);
  const schema = GRID_SCHEMAS[kind];
  const fields = schema ? commonGridFields(data, schema) : [];
  const issues = grid ? validateDoc(path, ctx.docs) : [];
  return <>
    <div ref={detailRef} hidden={grid}>
      <Editor data={data} onChange={onChange} ctx={{ ...ctx, gridSelection, onOpenGrid: schema ? () => setGrid(true) : undefined }} />
    </div>
    {grid && <section className="panel catalog-grid" aria-label="Catalog grid">
      <div className="detail-header"><h2>Grid — {path}</h2>
        <button type="button" className="btn" autoFocus onClick={() => { focusRow.current = false; setGrid(false); }}>Back to details</button>
      </div>
      <p className="hint">Edit common fields directly. IDs, nested lists and fields missing from some rows are edited in the detail view. Changes use normal validation, undo and saving.</p>
      {!fields.length ? <p className="empty">No common editable fields. Add elements or repair malformed rows in the detail/JSON view.</p> :
        <div className="catalog-grid-scroll" tabIndex={0} aria-label="Scrollable editable catalog table">
          <table className="catalog-grid-table"><thead><tr><th scope="col">ID</th>{fields.map(([key]) => <th scope="col" key={key}>{key}</th>)}</tr></thead>
            <tbody>{data.map((row, index) => <tr key={index}>
              <th scope="row"><button type="button" className="catalog-row-link"
                aria-label={`Open details for ${typeof row.id === 'string' ? row.id : `row ${index}`}`}
                onClick={() => { focusRow.current = true; openRow(index); }}>{typeof row.id === 'string' ? row.id : `#${index}`}</button></th>
              {fields.map(([key, field]) => {
                const cellPath = `$[${index}].${key}`;
                const set = (value) => onChange(updateGridCell(data, index, key, value, schema), `grid:${cellPath}`);
                const errors = issues.filter((issue) => issue.path === cellPath || issue.path.startsWith(`${cellPath}.`));
                const props = { value: row[key], onChange: set, 'aria-label': `${row.id ?? index}: ${key}` };
                return <td key={key}>
                  <div role="group" aria-label={`Row ${index}, ${key}`}>
                    {key === 'color' ? <ColorInput value={row[key]} onChange={set} />
                      : key.endsWith('_key') ? <TextKeyInput {...props} texts={ctx.texts} onCreateKey={ctx.onCreateTextKey} onEditKey={ctx.onEditTextKey} onRenameKey={ctx.onRenameTextKey} />
                        : field.type === 'bool' ? <Checkbox checked={row[key]} onChange={set} label={key} />
                          : field.format === 'asset-path' ? <PathInput {...props} />
                          : field.type === 'string' ? <TextInput {...props} />
                            : key === 'units_per_hour' ? <UnitsPerHourInput {...props} />
                              : <NumberInput {...props} integer={['int', 'u8'].includes(field.type)} />}
                    {errors.map((issue, i) => <p key={i} className="field-error">{issue.message}</p>)}
                  </div>
                </td>;
              })}
            </tr>)}</tbody>
          </table>
        </div>}
    </section>}
  </>;
}
