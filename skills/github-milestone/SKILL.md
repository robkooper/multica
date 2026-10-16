# GitHub milestone

Each Multica workspace has one GitHub repository (`multica repo list --output json`; `<repo>` below is its `<owner>/<repo>`). Each GitHub milestone is a Multica project. A project belongs to a milestone when the last line of its description is `GitHub milestone: <milestone html_url>`; the project "No milestone" ends with `GitHub milestone: none`. Work an agent does must end up on one milestone, the same in GitHub and in Multica.

## Find the milestone for an issue

1. Get the issue's project; for a sub-issue the Architect created (no `gh_number`), the parent's project instead (a sub-issue with `gh_number` is a GitHub child of an epic and keeps its own milestone). Read it with `multica issue get <key> --output json` (field `project_id`), then `multica project get <project_id> --output json` (field `description`).
2. If the description ends with `GitHub milestone: <url>`, the milestone number is the last part of the URL. Check it: `gh api repos/<repo>/milestones/<number> --jq '{number,title,state,html_url}'`. If it is open, that is the milestone.
3. Otherwise (the project is "No milestone", the milestone is closed, or the project has no marker) use the current milestone: the open milestone with the earliest due date, or, when no open milestone has a due date, the one with the lowest version number in its title.
   `gh api "repos/<repo>/milestones?state=open&per_page=100" --jq '.[] | {number,title,due_on,html_url}'`
4. If there is no open milestone, there is no milestone: leave milestones and projects unchanged, and say so in one line in your comment.

## Find or create its Multica project

`multica project list --output json`, and pick the project whose description ends with `GitHub milestone: <html_url>`. If there is none yet, create it the way the GitHub Issue Sync autopilot does, so the sync adopts it instead of making a second one:

```
multica project create --title "<milestone title>" --repo "https://github.com/<repo>" --status planned --description "<milestone description>\n\nGitHub milestone: <html_url>"
```

Add `--due-date <YYYY-MM-DD>` when the milestone has a due date.

## Put an issue on the milestone

- Multica: `multica issue update <key> --project <project id> --no-start`.
- GitHub, only for an issue that came from GitHub (it has metadata `gh_number`): `gh issue edit <gh_number> --repo <repo> --milestone "<milestone title>"`. Do both, or the daily sync moves the Multica issue back to the GitHub milestone.

## Put a PR on the milestone

- New PR: add `--milestone "<milestone title>"` to `gh pr create`.
- Existing PR: `gh pr edit <pr> --repo <repo> --milestone "<milestone title>"`.
- Check: `gh pr view <pr> --json milestone --jq .milestone.title` must print the title.

Changing a milestone never posts a comment, and it is the only GitHub change this skill allows besides the PR itself.
