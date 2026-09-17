import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import * as api from './api.js';
import { BUILDINGS_PATH, detectKind, RESOURCES_PATH, SUBJECTS_PATH, SUBJECT_ROLES_PATH, SHIPS_PATH, STATIONS_PATH, TEXTS_PATH, validateDoc } from './lib/schema.js';
import { syncStationInstance } from './lib/station.js';
import { editTranslation } from './lib/translation.js';
import { planTranslationRename, applyRenameTransaction, stepRenameTransaction } from './lib/translationRename.js';
import { detectStyle, formatJson } from './lib/format.js';
import BuildingsEditor from './components/BuildingsEditor.jsx';
import ResourcesEditor from './components/ResourcesEditor.jsx';
import SubjectsEditor from './components/SubjectsEditor.jsx';
import SubjectRolesEditor from './components/SubjectRolesEditor.jsx';
import { ShipsEditor, SpaceStationsEditor } from './components/StationEditors.jsx';
import KeyBindingsEditor from './components/KeyBindingsEditor.jsx';
import LevelEditor from './components/LevelEditor.jsx';
import LocalizationEditor from './components/LocalizationEditor.jsx';
import GenericEditor from './components/GenericEditor.jsx';
import CatalogGrid from './components/CatalogGrid.jsx';
import { GRID_SCHEMAS } from './lib/catalogGrid.js';
import RawEditor from './components/RawEditor.jsx';
import IssuesPanel from './components/IssuesPanel.jsx';
import FilesMenu from './components/FilesMenu.jsx';
import VersionMenu from './components/VersionMenu.jsx';

const HISTORY_LIMIT = 200;
const COALESCE_MS = 1200;
const EDITORS = {
  buildings: BuildingsEditor,
  resources: ResourcesEditor,
  subjects: SubjectsEditor,
  subject_roles: SubjectRolesEditor,
  key_bindings: KeyBindingsEditor,
  ships: ShipsEditor,
  space_stations: SpaceStationsEditor,
  level: LevelEditor,
  localization: LocalizationEditor,
};

// A doc is { data, style, saved (formatted text last on disk), mtime, past, future, lastKey, lastTime, loadError }.
function makeDoc(text, mtime) {
  const style = detectStyle(text);
  try {
    const data = JSON.parse(text);
    return { data, style, saved: formatJson(data, style), mtime, past: [], future: [] };
  } catch (error) {
    return { data: undefined, style, saved: null, mtime, past: [], future: [], loadError: error.message, rawText: text };
  }
}

const isDirty = (doc) => doc && doc.data !== undefined && formatJson(doc.data, doc.style) !== doc.saved;

export default function App() {
  const [files, setFiles] = useState([]);
  const [docs, setDocs] = useState({});
  const [active, setActive] = useState(null);
  const [profiles, setProfiles] = useState([]);
  const [profile, setProfile] = useState(null);
  const [tab, setTab] = useState('visual');
  const [status, setStatus] = useState(null);
  const docsRef = useRef(docs);
  docsRef.current = docs;

  const flash = (message, kind = 'info') => setStatus({ message, kind, at: Date.now() });
  useEffect(() => {
    if (!status) return;
    const timer = setTimeout(() => setStatus(null), status.kind === 'error' ? 8000 : 3000);
    return () => clearTimeout(timer);
  }, [status]);

  // Every document path is relative to the selected configuration version.
  const loadAll = useCallback(async (version, keepActive = false) => {
    const { files } = await api.listFiles(version);
    setFiles(files);
    const loaded = await Promise.all(files.map(async (f) => [f.path, await api.readFile(version, f.path)]));
    setDocs(Object.fromEntries(loaded.map(([path, { text, mtime }]) => [path, makeDoc(text, mtime)])));
    setActive((current) => (keepActive && files.some((f) => f.path === current) ? current : (files[0]?.path ?? null)));
  }, []);

  useEffect(() => {
    (async () => {
      const { profiles } = await api.listProfiles();
      setProfiles(profiles);
      const initial = profiles.some((entry) => entry.name === 'default') ? 'default' : profiles[0]?.name;
      if (!initial) { flash('No configuration version found under assets/config.', 'error'); return; }
      setProfile(initial);
      await loadAll(initial);
    })().catch((e) => flash(`Cannot load configuration versions: ${e.message}`, 'error'));
  }, [loadAll]);

  // Drop every loaded document; callers set the destination version first.
  const clearDocuments = () => {
    setFiles([]);
    setDocs({});
    setActive(null);
  };

  /** Switching versions reloads every document; unsaved edits are never merged across them. */
  const switchProfile = (name) => {
    if (!name || name === profile) return;
    if (Object.values(docsRef.current).some(isDirty) && !confirm(`Discard unsaved changes and switch to version "${name}"?`)) return;
    setProfile(name);
    clearDocuments();
    setTab('visual');
    loadAll(name)
      .then(() => flash(`Version ${name} loaded`))
      .catch((e) => flash(`Cannot load version ${name}: ${e.message}`, 'error'));
  };

  const refreshProfiles = async () => {
    const { profiles } = await api.listProfiles();
    setProfiles(profiles);
    return profiles;
  };

  const createVersion = async () => {
    if (Object.values(docsRef.current).some(isDirty)) { flash('Save or discard changes before creating a version.', 'error'); return; }
    const raw = prompt(`New version name. It becomes a full copy of "${profile}":`, '');
    if (raw === null) return;
    const name = raw.trim();
    try {
      await api.createProfile(name, profile);
      await refreshProfiles();
      setProfile(name);
      clearDocuments();
      await loadAll(name);
      flash(`Created version ${name}`);
    } catch (e) {
      flash(`Cannot create version: ${e.message}`, 'error');
    }
  };

  const deleteVersion = async () => {
    if (profile === 'default') return;
    if (Object.values(docsRef.current).some(isDirty)) { flash('Save or discard changes before deleting a version.', 'error'); return; }
    if (!confirm(`Delete version "${profile}" and every JSON file in it? This cannot be undone.`)) return;
    try {
      await api.deleteProfile(profile);
      const profiles = await refreshProfiles();
      const fallback = profiles.some((entry) => entry.name === 'default') ? 'default' : profiles[0]?.name;
      setProfile(fallback ?? null);
      clearDocuments();
      if (fallback) await loadAll(fallback);
      flash(`Deleted version ${profile}`);
    } catch (e) {
      flash(`Cannot delete version: ${e.message}`, 'error');
    }
  };

  const dirtyPaths = Object.keys(docs).filter((p) => isDirty(docs[p]));

  useEffect(() => {
    const onBeforeUnload = (e) => {
      if (Object.values(docsRef.current).some(isDirty)) e.preventDefault();
    };
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => window.removeEventListener('beforeunload', onBeforeUnload);
  }, []);

  /** Applies an edit; consecutive edits with the same historyKey merge into one undo step. */
  const updateDoc = useCallback((path, dataOrUpdater, historyKey) => {
    setDocs((all) => {
      const doc = all[path];
      if (!doc || doc.data === undefined) return all;
      const data = typeof dataOrUpdater === 'function' ? dataOrUpdater(doc.data) : dataOrUpdater;
      const now = Date.now();
      const coalesce = historyKey && doc.lastKey === historyKey && now - doc.lastTime < COALESCE_MS;
      const past = coalesce ? doc.past : [...doc.past, doc.data].slice(-HISTORY_LIMIT);
      return { ...all, [path]: { ...doc, data, past, future: [], lastKey: historyKey, lastTime: now } };
    });
  }, []);

  const undo = useCallback((path) => {
    const transaction = stepRenameTransaction(docsRef.current, path, 'undo');
    if (transaction?.error) { flash(transaction.error, 'error'); return; }
    if (transaction) { setDocs(transaction.docs); return; }
    setDocs((all) => {
      const doc = all[path];
      if (!doc?.past.length) return all;
      return {
        ...all,
        [path]: { ...doc, data: doc.past[doc.past.length - 1], past: doc.past.slice(0, -1), future: [doc.data, ...doc.future], lastKey: null },
      };
    });
  }, []);

  const redo = useCallback((path) => {
    const transaction = stepRenameTransaction(docsRef.current, path, 'redo');
    if (transaction?.error) { flash(transaction.error, 'error'); return; }
    if (transaction) { setDocs(transaction.docs); return; }
    setDocs((all) => {
      const doc = all[path];
      if (!doc?.future.length) return all;
      return { ...all, [path]: { ...doc, data: doc.future[0], past: [...doc.past, doc.data], future: doc.future.slice(1), lastKey: null } };
    });
  }, []);

  const issuesFor = (path, all) =>
    all[path]?.loadError ? [{ level: 'error', path: '$', message: `invalid JSON on disk: ${all[path].loadError}` }] : validateDoc(path, all);
  const allIssues = useMemo(() => Object.fromEntries(Object.keys(docs).map((p) => [p, issuesFor(p, docs)])), [docs]);

  const save = useCallback(async (path) => {
    const doc = docsRef.current[path];
    if (!doc || doc.data === undefined) return;
    const errors = issuesFor(path, docsRef.current).filter((i) => i.level === 'error').length;
    if (errors && !confirm(`${path} has ${errors} error(s) that the game loader will reject. Save anyway?`)) return;
    const text = formatJson(doc.data, doc.style);
    const write = (force) => api.saveFile(profile, path, text, doc.mtime, force);
    try {
      let result;
      try {
        result = await write(false);
      } catch (e) {
        if (e.status !== 409 || !confirm(`${path} was modified on disk after it was loaded.\nOverwrite it with your version?`)) throw e;
        result = await write(true);
      }
      setDocs((all) => ({ ...all, [path]: { ...all[path], saved: text, mtime: result.mtime } }));
      flash(`Saved ${path}`);
    } catch (e) {
      flash(`Save failed for ${path}: ${e.message}`, 'error');
    }
  }, []);

  const reload = async (path) => {
    if (isDirty(docs[path]) && !confirm(`Discard unsaved changes to ${path}?`)) return;
    try {
      const { text, mtime } = await api.readFile(profile, path);
      setDocs((all) => ({ ...all, [path]: makeDoc(text, mtime) }));
      flash(`Reloaded ${path} from disk`);
    } catch (e) {
      flash(`Reload failed: ${e.message}`, 'error');
    }
  };

  const createLevel = async () => {
    const stations = docs[STATIONS_PATH]?.data;
    const station = Array.isArray(stations) ? stations.find((s) => s && typeof s.id === 'string' && s.id) : null;
    if (!station) { flash('Create a space station template before creating a level.', 'error'); return; }
    const taken = new Set(files.map((f) => f.path));
    let n = 0;
    while (taken.has(`levels/level_${n}.json`)) n++;
    const name = prompt('New level file name (inside levels/ of this version):', `level_${n}.json`);
    if (!name) return;
    const path = `levels/${name.endsWith('.json') ? name : `${name}.json`}`;
    try {
      await api.createFile(profile, path, formatJson({ version: 1, level: n, buildings: [], subjects: [], space_station: syncStationInstance(null, station) }));
      await loadAll(profile, true);
      setActive(path);
      flash(`Created ${path}`);
    } catch (e) {
      flash(`Cannot create ${path}: ${e.message}`, 'error');
    }
  };

  const renameTextKey = (key) => {
    const before = docsRef.current;
    const nextKey = prompt(`Rename translation key "${key}". All schema-defined references will be updated:`, key);
    if (nextKey === null || nextKey === key) return;
    const plan = planTranslationRename(before, active, key, nextKey);
    if (plan.error) { flash(plan.error, 'error'); return; }
    const files = Object.keys(plan.changes);
    if (!confirm(`Rename "${key}" to "${nextKey}"?\nUpdate all ${plan.count} reference(s) in ${files.length - 1} file(s), preserving the translated text.\nAffected files: ${files.join(', ')}\nUse Save all to persist every affected file.`)) return;
    setDocs(applyRenameTransaction(before, plan.changes));
    flash(`Renamed "${key}". Use Save all for all ${files.length} affected files. Undo/redo is coordinated across them.`);
  };

  const editTextKey = useCallback((key) => {
    const texts = docsRef.current[TEXTS_PATH]?.data;
    const next = editTranslation(texts, key, (message, value) => prompt(message, value));
    if (!next) return;
    updateDoc(TEXTS_PATH, next);
    flash(`Updated "${key}" in ${TEXTS_PATH} (unsaved). Save that file or use Save all; undo is in en.json.`);
  }, [updateDoc]);

  // Adds a missing localization key to en.json (kept unsaved so it can be reviewed).
  const createTextKey = useCallback(
    (key) => {
      const texts = docsRef.current[TEXTS_PATH]?.data;
      if (!texts || key in texts) return;
      const value = prompt(`English text for "${key}":`, '');
      if (value === null) return;
      updateDoc(TEXTS_PATH, { ...texts, [key]: value });
      flash(`Added "${key}" to ${TEXTS_PATH} (unsaved)`);
    },
    [updateDoc],
  );

  useEffect(() => {
    const onKey = (e) => {
      if (!active || !(e.ctrlKey || e.metaKey)) return;
      const key = e.key.toLowerCase();
      const inText = e.target.closest?.('input, textarea');
      if (key === 's') {
        e.preventDefault();
        if (e.shiftKey) dirtyPaths.forEach((p) => save(p));
        else save(active);
      } else if (!inText && key === 'z' && !e.shiftKey) {
        e.preventDefault();
        undo(active);
      } else if (!inText && (key === 'y' || (key === 'z' && e.shiftKey))) {
        e.preventDefault();
        redo(active);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [active, dirtyPaths, save, undo, redo]);

  const doc = docs[active];
  const kind = active ? detectKind(active) : null;
  const ctx = useMemo(
    () => ({
      docs,
      texts: docs[TEXTS_PATH]?.data,
      buildings: docs[BUILDINGS_PATH]?.data,
      resources: docs[RESOURCES_PATH]?.data,
      subjects: docs[SUBJECTS_PATH]?.data,
      subject_roles: docs[SUBJECT_ROLES_PATH]?.data,
      ships: docs[SHIPS_PATH]?.data,
      space_stations: docs[STATIONS_PATH]?.data,
      onCreateTextKey: createTextKey,
      onEditTextKey: editTextKey,
      updateDoc,
    }),
    [docs, createTextKey, editTextKey, updateDoc],
  );
  const onChange = (data, historyKey) => updateDoc(active, data, historyKey);

  const groups = files.reduce((acc, f) => {
    const dir = f.path.includes('/') ? f.path.slice(0, f.path.lastIndexOf('/')) : '.';
    (acc[dir] ??= []).push(f);
    return acc;
  }, {});

  let editor = null;
  if (doc?.loadError)
    editor = (
      <div className="panel">
        <div className="callout error">This file is not valid JSON and cannot be edited visually: {doc.loadError}</div>
        <pre className="raw-dump">{doc.rawText}</pre>
      </div>
    );
  else if (doc && tab === 'json') editor = <RawEditor data={doc.data} onChange={onChange} />;
  else if (doc) {
    const Editor = EDITORS[kind] ?? GenericEditor;
    editor = GRID_SCHEMAS[kind]
      ? <CatalogGrid key={active} Editor={Editor} kind={kind} path={active} data={doc.data} onChange={onChange} ctx={{ ...ctx, onRenameTextKey: renameTextKey }} />
      : <Editor key={active} data={doc.data} onChange={onChange} ctx={{ ...ctx, onRenameTextKey: renameTextKey }} />;
  }

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="logo">◆</span>
          <div>
            <strong>Colony Reboot</strong>
            <span className="subtitle">Asset Manager</span>
          </div>
        </div>
        <VersionMenu
          profiles={profiles}
          profile={profile}
          dirty={dirtyPaths.length > 0}
          onSwitch={switchProfile}
          onCreate={createVersion}
          onDelete={deleteVersion}
        />
        <FilesMenu groups={groups} active={active} allIssues={allIssues} dirtyPaths={dirtyPaths} onSelect={setActive} onCreateLevel={createLevel} />
        <div className="btn-row">
          <button type="button" className="btn" onClick={() => loadAll(profile, true)} disabled={dirtyPaths.length > 0} title="Reload every file from disk">
            ⟳ Rescan
          </button>
          <button type="button" className="btn primary" disabled={dirtyPaths.length === 0} onClick={() => dirtyPaths.forEach((p) => save(p))} title="Ctrl+Shift+S">
            Save all ({dirtyPaths.length})
          </button>
        </div>
      </header>

      <main className="main">
        {doc ? (
          <>
            <div className="doc-bar">
              <div className="doc-title">
                <h1>{active}</h1>
                <span className="kind-tag">{kind}</span>
                {isDirty(doc) && <span className="unsaved">● unsaved</span>}
              </div>
              <div className="tabs">
                <button type="button" className={tab === 'visual' ? 'active' : ''} onClick={() => setTab('visual')}>
                  Visual
                </button>
                <button type="button" className={tab === 'json' ? 'active' : ''} onClick={() => setTab('json')}>
                  JSON
                </button>
              </div>
              <div className="btn-row">
                <button type="button" className="btn" disabled={!doc.past.length} onClick={() => undo(active)} title="Ctrl+Z">
                  ↶ Undo
                </button>
                <button type="button" className="btn" disabled={!doc.future.length} onClick={() => redo(active)} title="Ctrl+Y">
                  ↷ Redo
                </button>
                <button type="button" className="btn" onClick={() => reload(active)}>
                  Revert
                </button>
                <button type="button" className="btn primary" disabled={!isDirty(doc)} onClick={() => save(active)} title="Ctrl+S">
                  Save
                </button>
              </div>
            </div>
            <div className="editor-area">{editor}</div>
            <IssuesPanel issues={allIssues[active] ?? []} onCreateTextKey={createTextKey} />
          </>
        ) : (
          <p className="empty">{files.length ? 'Select a file.' : 'Loading assets…'}</p>
        )}
      </main>

      {status && <div className={`toast ${status.kind}`}>{status.message}</div>}
    </div>
  );
}
