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

## Link a Multica issue to GitHub

For a Multica issue that is not a sub-issue the Architect created (it has no parent, or it has `gh_number`), make sure it has a GitHub issue on the right milestone. First find the milestone as above, and put the Multica issue in that milestone's project if it is not there yet.

1. The issue has `gh_number` (`multica issue metadata list <key>`): read it with `gh issue view <gh_number> --repo <repo> --json number,url,milestone`. If its milestone is not the milestone you found, set it with `gh issue edit <gh_number> --repo <repo> --milestone "<milestone title>"`. Done.
2. No `gh_number`: look for the same issue on GitHub, which may not have been synced yet:
   `gh issue list --repo <repo> --state all --search "in:title <title>" --limit 20 --json number,title,url,milestone`
   Only an issue whose title is exactly the Multica title (ignoring case and surrounding spaces) counts.
   - Exactly one match: check it is not already synced to another Multica issue (`multica issue list --metadata gh_number=<number> --output json`). If it is, the two are duplicates: say so in one line, set this issue to blocked and mention the human. Otherwise set its milestone as in step 1, then link it (step 4).
   - More than one match: do not guess. Say so in one line, set the issue to blocked and mention the human.
   - No match: create it (step 3).
3. Create the GitHub issue. Write the Multica description to a file in the current directory, with every mention link (`[@Name](mention://...)`) removed, and no `@` character, Multica issue keys, or names of Multica agents or members left in it. Then:
   `gh issue create --repo <repo> --title "<Multica title>" --body-file <file> --milestone "<milestone title>"`
   Leave out `--milestone` only when there is no open milestone (step 4 of "Find the milestone").
4. Link it in Multica, after any milestone change (that changes `updatedAt`), so the GitHub Issue Sync adopts this issue instead of creating a second one:
   ```
   multica issue metadata set <key> --key gh_number --value <number>
   multica issue metadata set <key> --key gh_updated_at --type string --value "$(gh issue view <number> --repo <repo> --json updatedAt --jq .updatedAt)"
   ```

Creating an issue, linking it and setting its milestone never post a comment on GitHub.

## Pull requests and milestones

Milestones contain issues, never pull requests. A PR reaches its milestone through the GitHub issue it is linked to: the parent's `gh_number`, referenced in the commits and PR body ("Part of #<gh_number>", and "Fixes #<gh_number>" on the last PR of the stack).

- Never pass `--milestone` to `gh pr create` or `gh pr edit`.
- A PR of ours that has a milestone gets it removed: `gh pr edit <pr> --repo <repo> --remove-milestone`.
- Check: `gh pr view <pr> --json milestone --jq .milestone` must print `null`, and the issue `#<gh_number>` must be on the milestone.

Changing a milestone never posts a comment. Besides the PR itself, changing issue milestones, removing PR milestones and creating the issue in "Link a Multica issue to GitHub" are the only GitHub changes this skill allows.
