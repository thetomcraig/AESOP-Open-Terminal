# AGENTS.md — Project Development

Applies to AI agents working on projects in this workspace.

## 1. Before changing code

- Inspect the project structure, `git status`, and relevant files.
- Read the project README and applicable `AGENTS.md` files.
- Follow existing architecture, conventions, and tooling.
- Identify relevant tests and dependencies before making changes.
- Never assume uncommitted changes are yours.

## 2. Implementation rules

- Make the smallest change that satisfies the request.
- Avoid unrelated refactoring, cleanup, or new dependencies.
- Preserve existing behavior and public interfaces unless asked to change them.
- Handle errors explicitly; do not silently suppress failures.
- Never hardcode credentials or environment-specific configuration.
- Update relevant tests and documentation when behavior or setup changes.
- Ask before making decisions that materially exceed the requested scope.

## 3. Git rules

- Preserve existing staged and unstaged changes.
- Review `git diff` before finishing.
- Never commit, push, amend, force-push, or rewrite history unless explicitly requested.
- Never commit secrets or credentials.

## 4. Validation

- Run relevant tests and project checks after changes.
- Fix regressions introduced by the change.
- Never claim a check passed unless it was executed successfully.
- Report checks that could not be run and why.

## 5. Completion report

Briefly state:
- What changed and which files were affected.
- Tests and checks performed, with results.
- Any remaining issues or assumptions.
