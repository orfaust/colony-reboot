import { useState } from 'react';
import { Checkbox, ColorInput, CommitInput, NumberInput, TextInput, TextKeyInput } from './fields.jsx';
import { clone, isColor, isPlainObject, renameKey, uniqueName } from '../lib/object.js';

const TEMPLATES = {
  string: '',
  number: 0,
  boolean: false,
  object: {},
  array: [],
  color: { r: 255, g: 255, b: 255 },
};

function typeOf(value) {
  if (Array.isArray(value)) return 'array';
  if (value === null) return 'null';
  return typeof value;
}

function AddControl({ onAdd, needsName }) {
  const [name, setName] = useState('');
  const [type, setType] = useState('string');
  return (
    <div className="add-control">
      {needsName && <input className="input" placeholder="new field name" value={name} onChange={(e) => setName(e.target.value)} />}
      <select className="input" value={type} onChange={(e) => setType(e.target.value)}>
        {Object.keys(TEMPLATES).map((t) => (
          <option key={t}>{t}</option>
        ))}
      </select>
      <button
        type="button"
        className="btn tiny"
        disabled={needsName && !name.trim()}
        onClick={() => {
          onAdd(name.trim(), clone(TEMPLATES[type]));
          setName('');
        }}
      >
        + Add
      </button>
    </div>
  );
}

function JsonNode({ name, value, onChange, onRemove, onRename, ctx, depth }) {
  const [open, setOpen] = useState(depth < 2);
  const type = typeOf(value);
  const header = (
    <div className="node-head">
      {onRename ? (
        <CommitInput className="node-key" value={name} onCommit={onRename} />
      ) : (
        <span className="node-key static">{name}</span>
      )}
      {onRemove && (
        <button type="button" className="btn tiny ghost danger" title="Remove" onClick={onRemove}>
          ✕
        </button>
      )}
    </div>
  );

  if (isColor(value))
    return (
      <div className="node leaf">
        {header}
        <ColorInput value={value} onChange={onChange} />
      </div>
    );

  if (type === 'object' || type === 'array') {
    const entries = type === 'array' ? value.map((v, i) => [i, v]) : Object.entries(value);
    return (
      <div className="node branch">
        <div className="node-head">
          <button type="button" className="twisty" onClick={() => setOpen(!open)}>
            {open ? '▾' : '▸'}
          </button>
          {onRename ? <CommitInput className="node-key" value={name} onCommit={onRename} /> : <span className="node-key static">{name}</span>}
          <span className="node-meta">{type === 'array' ? `[${value.length}]` : `{${entries.length}}`}</span>
          {onRemove && (
            <button type="button" className="btn tiny ghost danger" title="Remove" onClick={onRemove}>
              ✕
            </button>
          )}
        </div>
        {open && (
          <div className="node-children">
            {entries.map(([key, child]) => (
              <JsonNode
                key={key}
                name={String(key)}
                value={child}
                depth={depth + 1}
                ctx={ctx}
                onChange={(next) => {
                  if (type === 'array') onChange(value.map((v, i) => (i === key ? next : v)));
                  else onChange({ ...value, [key]: next });
                }}
                onRemove={() => {
                  if (type === 'array') onChange(value.filter((_, i) => i !== key));
                  else {
                    const { [key]: _removed, ...rest } = value;
                    onChange(rest);
                  }
                }}
                onRename={
                  type === 'object'
                    ? (next) => {
                        if (!next.trim() || next in value) return false;
                        onChange(renameKey(value, key, next));
                        return true;
                      }
                    : undefined
                }
              />
            ))}
            {type === 'array' ? (
              <div className="add-control">
                {value.length > 0 && (
                  <button type="button" className="btn tiny" onClick={() => onChange([...value, clone(value[value.length - 1])])}>
                    + Duplicate last item
                  </button>
                )}
                <AddControl onAdd={(_, item) => onChange([...value, item])} />
              </div>
            ) : (
              <AddControl needsName onAdd={(key, item) => onChange({ ...value, [uniqueName(key, Object.keys(value))]: item })} />
            )}
          </div>
        )}
      </div>
    );
  }

  let input;
  if (type === 'boolean') input = <Checkbox checked={value} onChange={onChange} label={String(value)} />;
  else if (type === 'number') input = <NumberInput value={value} onChange={onChange} />;
  else if (type === 'string' && name.endsWith('_key') && ctx.texts)
    input = <TextKeyInput value={value} onChange={onChange} texts={ctx.texts} onCreateKey={ctx.onCreateTextKey} />;
  else if (type === 'string') input = <TextInput value={value} onChange={onChange} />;
  else
    input = (
      <button type="button" className="btn tiny" onClick={() => onChange('')}>
        null → string
      </button>
    );

  return (
    <div className="node leaf">
      {header}
      {input}
    </div>
  );
}

export default function GenericEditor({ data, onChange, ctx }) {
  if (!isPlainObject(data) && !Array.isArray(data))
    return <p className="empty">The root value is not an object or array. Use the JSON tab.</p>;
  return (
    <div className="panel generic-editor">
      <JsonNode name="root" value={data} onChange={(next) => onChange(next)} ctx={ctx} depth={0} />
    </div>
  );
}
