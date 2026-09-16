import { useEffect, useId, useRef, useState } from 'react';

/** Disclosure navigation: native buttons keep normal Tab/Shift+Tab behavior. */
export default function FilesMenu({ groups, active, allIssues, dirtyPaths, onSelect, onCreateLevel }) {
  const [open, setOpen] = useState(false);
  const container = useRef(null);
  const trigger = useRef(null);
  const panelId = useId();
  const close = (restoreFocus = false) => {
    setOpen(false);
    if (restoreFocus) trigger.current?.focus();
  };
  useEffect(() => {
    if (!open) return;
    const outside = (event) => {
      if (!container.current?.contains(event.target)) setOpen(false);
    };
    document.addEventListener('pointerdown', outside);
    document.addEventListener('focusin', outside);
    return () => {
      document.removeEventListener('pointerdown', outside);
      document.removeEventListener('focusin', outside);
    };
  }, [open]);
  const createLevel = () => {
    close(true);
    onCreateLevel();
  };
  return <div className="files-menu" ref={container} onKeyDown={(event) => {
    if (event.key === 'Escape' && open) {
      event.preventDefault();
      event.stopPropagation();
      close(true);
    }
  }}>
    <button ref={trigger} type="button" className="btn files-menu-trigger" aria-expanded={open} aria-controls={panelId}
      onClick={() => setOpen((value) => !value)}>
      <span>Files</span><span className="files-menu-current">{active ?? 'Select a file'}</span><span aria-hidden="true">{open ? '▴' : '▾'}</span>
    </button>
    <nav id={panelId} className="files-menu-panel" aria-label="Asset files" hidden={!open}>
      {Object.entries(groups).map(([dir, list]) => <div key={dir} className="file-group">
        <div className="group-title">{dir}
          {dir === 'levels' && <button type="button" className="btn tiny ghost" onClick={createLevel} title="New level" aria-label="New level">+</button>}
        </div>
        {list.map((file) => {
          const errors = (allIssues[file.path] ?? []).filter((issue) => issue.level === 'error').length;
          return <button key={file.path} type="button" className={`file${file.path === active ? ' active' : ''}`}
            aria-current={file.path === active ? 'page' : undefined}
            onClick={() => { onSelect(file.path); close(true); }}>
            <span className="file-name">{file.path.split('/').pop()}</span>
            {errors > 0 && <span className="badge error" aria-label={`${errors} errors`}>{errors}</span>}
            {dirtyPaths.includes(file.path) && <span className="dirty" title="Unsaved changes" aria-label="Unsaved changes" />}
          </button>;
        })}
      </div>)}
      {Object.keys(groups).length === 0 && <p className="empty">No files available.</p>}
      {!groups.levels && Object.keys(groups).length > 0 && <button type="button" className="btn tiny" onClick={createLevel}>+ New level</button>}
    </nav>
  </div>;
}
