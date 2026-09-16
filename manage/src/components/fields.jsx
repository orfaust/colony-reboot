import { useEffect, useId, useRef, useState } from 'react';
import { hexToRgb, rgbToHex } from '../lib/object.js';
import { parseNumberText, stepNumber } from '../lib/number.js';
import { hoursPerUnitText } from '../lib/rate.js';

export function Field({ label, hint, error, children, wide }) {
  return (
    <label className={`field${wide ? ' wide' : ''}${error ? ' has-error' : ''}`}>
      <span className="field-label">{label}</span>
      {children}
      {error ? <small className="field-error">{error}</small> : hint ? <small className="field-hint">{hint}</small> : null}
    </label>
  );
}

/**
 * Keeps the typed text locally so partial input like "0." or "-" is not lost.
 * A text field, not type="number": the browser locale must not display or accept a
 * comma decimal separator. Text with a comma is flagged and never reported.
 */
export function NumberInput({ value, onChange, integer, min, max, step = 0.1, className = '', title, ...rest }) {
  const format = (v) => (typeof v === 'number' && Number.isFinite(v) ? String(v) : '');
  const [text, setText] = useState(format(value));
  const focused = useRef(false);
  useEffect(() => {
    if (!focused.current) setText(format(value));
  }, [value]);
  const { error } = parseNumberText(text, integer);
  return (
    <input
      {...rest}
      type="text"
      inputMode={integer ? 'numeric' : 'decimal'}
      autoComplete="off"
      spellCheck={false}
      className={`input num${error ? ' invalid' : ''} ${className}`}
      title={error ?? title}
      aria-invalid={error ? true : undefined}
      value={text}
      onFocus={() => (focused.current = true)}
      onBlur={() => {
        focused.current = false;
        setText(format(value));
      }}
      onKeyDown={(e) => {
        rest.onKeyDown?.(e);
        if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
        e.preventDefault();
        const next = stepNumber(value, e.key === 'ArrowUp' ? 1 : -1, integer ? 1 : step, min, max);
        setText(format(next));
        onChange(next);
      }}
      onChange={(e) => {
        setText(e.target.value);
        const parsed = parseNumberText(e.target.value, integer);
        if ('value' in parsed) onChange(integer ? Math.round(parsed.value) : parsed.value);
      }}
    />
  );
}

/** Reciprocal is a read-only preview of the accepted hourly rate. */
export function UnitsPerHourInput(props) {
  return <div className="hourly-rate-input">
    <NumberInput {...props} />
    <small className="field-hint">Hours per unit: <output>{hoursPerUnitText(props.value)}</output></small>
  </div>;
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

/** Stable localization key picker; editing its preview changes only en.json. */
export function TextKeyInput({ value, onChange, texts, onCreateKey, onEditKey, onRenameKey, 'aria-label': ariaLabel }) {
  const listId = useId();
  const text = texts?.[value];
  const missing = typeof text !== 'string' || text.trim() === '';
  return (
    <div className="text-key">
      <TextInput value={value} onChange={onChange} aria-label={ariaLabel} list={listId} className={missing ? 'invalid' : ''} spellCheck={false} />
      {onRenameKey && typeof value === 'string' && value && <button type="button" className="btn tiny"
        aria-label={`Rename translation key ${value}`} onClick={() => onRenameKey(value)}>Rename key…</button>}
      <datalist id={listId}>
        {Object.keys(texts ?? {}).map((k) => (
          <option key={k} value={k}>
            {texts[k]}
          </option>
        ))}
      </datalist>
      {onEditKey && typeof text === 'string' ? (
        <button type="button" className={`text-preview translation-edit${missing ? ' missing' : ''}`}
          aria-label={`Edit English translation for ${value}`} title="Edit translation in en.json (shared by all references)"
          onClick={() => onEditKey(value)}>{missing ? 'Empty text — edit translation' : `“${text}”`}</button>
      ) : missing ? (
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
