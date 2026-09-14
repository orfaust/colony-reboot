import { useEffect, useId, useRef, useState } from 'react';
import { hexToRgb, rgbToHex } from '../lib/object.js';

export function Field({ label, hint, error, children, wide }) {
  return (
    <label className={`field${wide ? ' wide' : ''}${error ? ' has-error' : ''}`}>
      <span className="field-label">{label}</span>
      {children}
      {error ? <small className="field-error">{error}</small> : hint ? <small className="field-hint">{hint}</small> : null}
    </label>
  );
}

/** Keeps the typed text locally so partial input like "0." or "-" is not lost. */
export function NumberInput({ value, onChange, integer, min, max, step = 'any', className = '', ...rest }) {
  const format = (v) => (typeof v === 'number' && Number.isFinite(v) ? String(v) : '');
  const [text, setText] = useState(format(value));
  const focused = useRef(false);
  useEffect(() => {
    if (!focused.current) setText(format(value));
  }, [value]);
  return (
    <input
      {...rest}
      type="number"
      className={`input num ${className}`}
      value={text}
      min={min}
      max={max}
      step={integer ? 1 : step}
      onFocus={() => (focused.current = true)}
      onBlur={() => {
        focused.current = false;
        setText(format(value));
      }}
      onChange={(e) => {
        setText(e.target.value);
        const n = Number(e.target.value);
        if (e.target.value.trim() !== '' && Number.isFinite(n)) onChange(integer ? Math.round(n) : n);
      }}
    />
  );
}

export function TextInput({ value, onChange, className = '', ...rest }) {
  return (
    <input
      {...rest}
      type="text"
      className={`input ${className}`}
      value={typeof value === 'string' ? value : ''}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}

/** Text input that only reports its value on blur or Enter (used for renames). */
export function CommitInput({ value, onCommit, className = '', ...rest }) {
  const [text, setText] = useState(value);
  useEffect(() => setText(value), [value]);
  const commit = () => {
    if (text !== value && !onCommit(text)) setText(value);
  };
  return (
    <input
      {...rest}
      type="text"
      className={`input ${className}`}
      value={text}
      onChange={(e) => setText(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === 'Enter') e.currentTarget.blur();
        if (e.key === 'Escape') setText(value);
      }}
    />
  );
}

export function Checkbox({ checked, onChange, label }) {
  return (
    <label className="checkbox">
      <input type="checkbox" checked={!!checked} onChange={(e) => onChange(e.target.checked)} />
      {label && <span>{label}</span>}
    </label>
  );
}

export function ColorInput({ value, onChange }) {
  const color = value ?? { r: 0, g: 0, b: 0 };
  return (
    <div className="color-input">
      <input type="color" value={rgbToHex(color)} onChange={(e) => onChange(hexToRgb(e.target.value))} />
      {['r', 'g', 'b'].map((channel) => (
        <span key={channel} className="channel">
          <em>{channel.toUpperCase()}</em>
          <NumberInput integer min={0} max={255} value={color[channel]} onChange={(n) => onChange({ ...color, [channel]: n })} />
        </span>
      ))}
    </div>
  );
}

/** Select that still shows (and flags) a current value missing from the options. */
export function RefSelect({ value, options, onChange, placeholder = '— select —' }) {
  const known = options.some((o) => o.value === value);
  return (
    <select className={`input${known || !value ? '' : ' invalid'}`} value={value ?? ''} onChange={(e) => onChange(e.target.value)}>
      {!value && <option value="">{placeholder}</option>}
      {!known && value && <option value={value}>{value} (missing)</option>}
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label ?? o.value}
        </option>
      ))}
    </select>
  );
}

/** Localization key picker with a live preview of the English text. */
export function TextKeyInput({ value, onChange, texts, onCreateKey }) {
  const listId = useId();
  const text = texts?.[value];
  const missing = typeof text !== 'string' || text.trim() === '';
  return (
    <div className="text-key">
      <TextInput value={value} onChange={onChange} list={listId} className={missing ? 'invalid' : ''} spellCheck={false} />
      <datalist id={listId}>
        {Object.keys(texts ?? {}).map((k) => (
          <option key={k} value={k}>
            {texts[k]}
          </option>
        ))}
      </datalist>
      {missing ? (
        <div className="text-preview missing">
          <span>Missing in en.json</span>
          {onCreateKey && value && (
            <button type="button" className="btn tiny" onClick={() => onCreateKey(value)}>
              + Add text
            </button>
          )}
        </div>
      ) : (
        <div className="text-preview">“{text}”</div>
      )}
    </div>
  );
}
