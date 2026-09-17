import { useId } from 'react';

/**
 * Configuration version selector. A version is one self-contained directory under
 * assets/config/, so switching reloads every document from that directory and the
 * Odin loader reads the same set with `--config <name>`.
 */
export default function VersionMenu({ profiles, profile, dirty, onSwitch, onCreate, onDelete }) {
  const id = useId();
  const names = profiles.map((entry) => entry.name);
  const current = profiles.find((entry) => entry.name === profile);
  // The default version ships with the game and is the loader fallback, so it stays.
  const canDelete = profile !== 'default' && names.length > 1;
  return (
    <div className="version-menu">
      <label htmlFor={id}>Version</label>
      <select id={id} value={profile ?? ''} onChange={(event) => onSwitch(event.target.value)} title="Configuration version to edit">
        {names.map((name) => (
          <option key={name} value={name}>
            {name} ({profiles.find((entry) => entry.name === name)?.files ?? 0})
          </option>
        ))}
      </select>
      <button type="button" className="btn tiny" onClick={onCreate} title="Duplicate the current version to experiment">
        + New
      </button>
      <button
        type="button"
        className="btn tiny"
        onClick={onDelete}
        disabled={!canDelete}
        title={canDelete ? 'Delete this version and its JSON files' : 'The default version cannot be deleted'}
      >
        Delete
      </button>
      {current && <span className="version-files">{current.files} files</span>}
      {dirty && (
        <span className="unsaved" title="Switching versions discards unsaved changes">
          ● unsaved
        </span>
      )}
    </div>
  );
}
