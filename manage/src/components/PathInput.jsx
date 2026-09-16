import { useRef, useState } from 'react';
import { TextInput } from './fields.jsx';

/** Select existing assets; browsing never uploads files or changes JSON before confirmation. */
export default function PathInput({ value, onChange, ...props }) {
  const dialog = useRef(null);
  const [paths, setPaths] = useState([]);
  const [selected, setSelected] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const browse = async () => {
    setSelected(typeof value === 'string' ? value : '');
    setError('');
    setPaths([]);
    setLoading(true);
    dialog.current.showModal();
    try {
      const response = await fetch('/api/sprites');
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? `HTTP ${response.status}`);
      setPaths(result.paths);
    } catch (e) { setError(`Cannot browse assets: ${e.message}`); }
    finally { setLoading(false); }
  };
  return <div className="path-input">
    <div className="btn-row"><TextInput {...props} value={value} onChange={onChange} />
      <button type="button" className="btn tiny" onClick={browse} aria-label="Browse PNG asset paths">Browse…</button>
    </div>
    <dialog ref={dialog} className="path-browser" aria-label="Browse PNG assets">
      <h3>Browse PNG assets</h3>
      <p className="hint">Select an existing asset. No files are uploaded or copied.</p>
      {loading ? <p role="status">Loading…</p> : error ? <p role="alert" className="field-error">{error}</p> : paths.length ?
        <select className="input" size={12} aria-label="PNG asset path" value={paths.includes(selected) ? selected : ''} onChange={(e) => setSelected(e.target.value)}>
          <option value="" disabled>Select a file</option>
          {paths.map((path) => <option key={path} value={path}>{path}</option>)}
        </select> : <p>No PNG files found under assets. Add files there, then browse again.</p>}
      <div className="btn-row">
        <button type="button" className="btn primary" disabled={loading || !paths.includes(selected)} onClick={() => { if (selected !== value) onChange(selected); dialog.current.close(); }}>Use path</button>
        <button type="button" className="btn" onClick={() => dialog.current.close()}>Cancel</button>
      </div>
    </dialog>
  </div>;
}
