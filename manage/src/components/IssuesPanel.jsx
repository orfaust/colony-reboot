export default function IssuesPanel({ issues, onCreateTextKey }) {
  const errors = issues.filter((i) => i.level === 'error').length;
  const warnings = issues.length - errors;
  return (
    <details className="issues" open={issues.length > 0}>
      <summary>
        {issues.length === 0 ? (
          <span className="ok">✓ No problems — the game loader should accept this file</span>
        ) : (
          <>
            {errors > 0 && <span className="count error">{errors} error{errors === 1 ? '' : 's'}</span>}
            {warnings > 0 && <span className="count warning">{warnings} warning{warnings === 1 ? '' : 's'}</span>}
          </>
        )}
      </summary>
      <ul>
        {issues.map((issue, i) => (
          <li key={i} className={issue.level}>
            <code>{issue.path}</code>
            <span>{issue.message}</span>
            {issue.textKey && onCreateTextKey && (
              <button type="button" className="btn tiny" onClick={() => onCreateTextKey(issue.textKey)}>
                + Add text
              </button>
            )}
          </li>
        ))}
      </ul>
    </details>
  );
}
