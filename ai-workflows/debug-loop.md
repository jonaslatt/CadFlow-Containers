# Debug Loop

An autonomous workflow for catching and fixing test failures and build errors during active development.

## Startup Procedure

1. Ensure the workspace is up to date: `cd /workspace && git pull`
2. Activate the Python environment: `source /workspace/.venv/bin/activate`
3. Install any new dependencies: `cd /workspace && pnpm install`
4. Run the full test suite once to capture the baseline:
   ```bash
   cd /workspace && pnpm test 2>&1 | tail -50
   ```
5. Note any pre-existing failures — these are the baseline, not regressions to fix.

## Loop Behavior

On each iteration:

1. Run the full test suite and capture output.
2. If there are new failures (not in the baseline):
   - Read the relevant source files and error messages to identify the root cause.
   - Apply the minimal fix.
   - Commit with a concise message.
3. If tests pass, check for TypeScript errors: `pnpm typecheck`.
4. Report a brief status summary (pass/fail counts, what was fixed).

Start the loop by entering `/loop 120s` in the Claude Code session.
