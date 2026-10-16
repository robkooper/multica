# AGENTS.md

Multica squad configuration as code. `story.md` is the owner's Medium article this setup started from, published at https://medium.com/@rob.kooper/running-a-coding-agent-squad-with-multica-on-your-own-vm-8655aba5d3a5. Medium often blocks automated fetches, so do not rely on reading the URL: the user downloads the article and saves it as `story.md` in the repo root (it is gitignored, so it is missing in a fresh clone; ask for it if you need it). Read it for background when present, but the files here are the source of truth and have moved past it:

- One Multica workspace per GitHub repo (exactly one repo under Settings → Code, found with `multica repo list`), not one workspace with a project per repo. Workspaces: `lumen` (ncsa/lumen), `taloscluster` (ncsa/taloscluster), and `ncsa`, the old all-in-one workspace that still has a project per repo and the old "GitHub Issue Sync Lumen" autopilot.
- One Multica project per GitHub milestone. The link is the last line of the project description: `GitHub milestone: <milestone html_url>`, or `GitHub milestone: none` for the "No milestone" project. Prompts and autopilots rely on this marker; do not change it in one place only.
- The `github-milestone` skill (used by Architect and Builder) holds the milestone rules: the issue's open milestone, otherwise the current one (earliest due date, else lowest version). Sub-issues go in that milestone's project, PRs get `--milestone`, and a parent with `gh_number` is moved on GitHub too so the sync does not move it back. Keep the skill, the sync autopilot and the PR Comment autopilot in agreement.
- Synced issues carry metadata `gh_number` (number) and `gh_updated_at`. Issues without `gh_number` (Architect sub-issues) are not synced but move with their parent.
- GitHub sub-issues are mirrored as Multica parent links by the sync autopilot. An issue with GitHub sub-issues is an epic: created unassigned, never planned or split (Lead rule 1, Architect). A sub-issue with `gh_number` is a GitHub epic child and a full issue of its own with its own milestone; only sub-issues without `gh_number` follow the Architect/Builder sub-issue flow. The GitHub Issue Sync autopilot is the only sync; there is no separate resync script.
- Extra agents not in the article: Senior Reviewer (in the squad), Monkey and Release Agent (standalone). The Builder uses `gh stack` for stacked PRs.

## Pitfalls

- `apply.sh` matches agents, squads and autopilots by name: a rename creates a new one and leaves the old one running. New autopilots are created paused.
- `dump.sh` overwrites the files here with what is in the workspace. Prompt edits made in the Multica UI are lost on the next `apply.sh` unless dumped first.
- Autopilots have `project: null` and must stay repo-agnostic so the same files work in every workspace.
- The Lead (a small model) routes on the exact strings agents post (`Verdict: approve|changes requested`, `Senior verdict: approve|changes requested`). Change a verdict string in an agent prompt and the squad rules together.
- On sub-issues the agents hand off directly (Architect sets the first to todo; Builder mentions reviewers, then the Senior Reviewer, then moves the next sub-issue to todo; Senior Reviewer sets in_review). Approvals are per commit: any new commit, including fixes for the Senior Reviewer, goes back to both Reviewer A and Reviewer B, and the Senior Reviewer refuses a head that both have not approved. The squad rules for sub-issues are only a fallback for a missing hand-off. Do not add a squad rule that duplicates an agent's own hand-off, or agents get started twice.
- `multica` CLI facts that are easy to get wrong:
  - `issue create` has no metadata flag; use `multica issue metadata set <id> --key K --value V`.
  - `issue list --limit` max is 100; page with `--offset` until `has_more` is false.
  - Project statuses: planned, in_progress, paused, completed, cancelled. Issue statuses: backlog, todo, in_progress, in_review, done, blocked, cancelled. Backlog never starts a run.
  - `--description-file` / `--content-file` must be inside the current directory.
  - `issue update --no-start` avoids waking the assignee. Editing a comment re-triggers every agent it mentions.
- All agents use the owner's GitHub account (one token on the VM), so anything they post on GitHub appears as the owner. Reviews stay in Multica only: Reviewer A, Reviewer B and the Senior Reviewer are read-only on GitHub, and the Builder only pushes branches and writes PR bodies. Do not reintroduce `gh pr comment` or `gh pr review` in a prompt.
- Never commit or push unless asked.
