# GitHub issue sync

One-way sync from the GitHub repository of this workspace into Multica. Each GitHub milestone becomes a Multica project; issues without a milestone go to the project "No milestone".

Only read from GitHub. Never create, edit, comment on or close anything on GitHub. Never @-mention anyone. Never delete a Multica issue, project or comment.

Write every GitHub body to a file in the current directory and pass it with `--description-file` or `--content-file`, so text is copied verbatim. Use `--no-start` on every `multica issue update`, so the sync never wakes an agent.

## 1. Find the repository

```
multica repo list --output json
```

There must be exactly one repository. If there are none or more than one, report that in one line and stop. From its URL take `<owner>/<repo>` (for `https://github.com/ncsa/lumen` that is `ncsa/lumen`) and use it as `<repo>` below. `<repo url>` is the URL itself.

## 2. Sync milestones to projects

```
gh api "repos/<repo>/milestones?state=all&per_page=100" --paginate
multica project list --output json
```

A project belongs to a milestone when the last line of its description is `GitHub milestone: <milestone html_url>`. The project for issues without a milestone is titled "No milestone" and its description ends with `GitHub milestone: none`.

For each milestone:

- No project yet: create one.
  ```
  multica project create --title "<milestone title>" --repo "<repo url>" --status planned --due-date <due_on as YYYY-MM-DD, omit if null> --description "<milestone description>\n\nGitHub milestone: <html_url>"
  ```
  If the milestone is closed, create it with `--status completed`.
- Project exists: if the title, description or due date changed on GitHub, update them with `multica project update`, keeping the `GitHub milestone:` line last. Milestone closed and project not `completed` or `cancelled`: set it to `completed` with `multica project status`. Milestone open and project `completed`: set it to `planned`. Never change a project status in any other case.

Create the "No milestone" project the same way if it does not exist (description: `Issues without a GitHub milestone.\n\nGitHub milestone: none`, status `planned`).

Projects without a `GitHub milestone:` line were not created by this sync: leave them alone. Never delete a project whose milestone was deleted on GitHub; just stop using it.

Every project must have `<repo url>` attached so agents get a checkout. If `multica project resource list <project id>` does not show it, add it with `multica project resource add <project id> --url "<repo url>"`.

Remember the map from milestone number to project id, plus the id of "No milestone".

## 3. Fetch the GitHub issues

```
gh issue list --repo <repo> --state open --limit 2000 --json number,title,body,author,updatedAt,url,milestone,parent,subIssuesSummary
gh issue list --repo <repo> --state closed --search "updated:>=<today minus 3 days, YYYY-MM-DD>" --limit 2000 --json number,title,body,author,updatedAt,url,milestone,parent,subIssuesSummary
```

The second list holds closed issues changed recently, so a milestone change on a closed issue still reaches Multica. Pull requests are not included, which is what we want. The issue's project is the project of its milestone, or "No milestone" when `milestone` is null.

An issue with GitHub sub-issues (`subIssuesSummary.total` greater than 0) is an epic. An epic is a container: the work happens in its sub-issues, so the squad must not plan or build the epic itself. `parent` is the issue's GitHub parent, or null.

## 4. Create or update each issue

Handle open and closed issues the same way, with one exception: never create a Multica issue for a closed GitHub issue.

Look for an existing Multica issue:

```
multica issue list --metadata gh_number=<number> --output json --fields id,title,description,status,assignee_type,project_id,parent_issue_id,metadata
```

Description format, used for both create and update:

```
<GitHub body>

Created by: <author login> (<issue url>)
```

Not found: create it in its project, status backlog, assigned to the Delivery squad. The title is the GitHub title. An epic is created the same way but unassigned (leave out `--assignee`).

```
multica issue create --title "<title>" --description-file <file> --project <project id> --status backlog --assignee "Delivery"
multica issue metadata set <id> --key gh_number --value <number>
multica issue metadata set <id> --key gh_updated_at --type string --value <updatedAt>
```

Then add all of its GitHub comments as described in step 5.

Found, and `updatedAt` differs from `gh_updated_at`:

- Title or description changed on GitHub: update them, using the same format.
- Milestone changed (the Multica issue is in a different project than the one step 3 gives): move it with `multica issue update <id> --project <project id> --no-start`. Move all its sub-issues with it, at every level: walk them with `multica issue children <id> --output json` and move each one the same way, whatever its status. Skip a sub-issue that has its own `gh_number`; it follows its own milestone.
- Never change the status, assignee or anything else.
- Then set `gh_updated_at` to `updatedAt`.

Multica issues without `gh_number` (such as sub-issues created by the Architect) are not part of the sync. Never touch them, except to move them with their parent as described above.

## 4b. Epics and parent links

After all issues are created, check every issue from step 3, whether or not `updatedAt` changed. Linking or unlinking a sub-issue on GitHub does not change `updatedAt`, so this cannot wait for it.

Epics: an epic that is in backlog and assigned to the Delivery squad gets unassigned with `multica issue assign <id> --unassign --no-start`. An epic in any other status keeps its assignee and gets `/note Now an epic on GitHub; plan its sub-issues instead.` once.

Parent links:

- GitHub `parent` is set and that parent has a Multica issue (by `gh_number`): if the child's `parent_issue_id` is not that issue, set it with `multica issue update <child id> --parent <parent id> --no-start`. If the parent has no Multica issue (an old closed issue), leave the child as it is.
- GitHub `parent` is null and the Multica issue has a parent that has a `gh_number`: the link was removed on GitHub, so clear it with `multica issue update <child id> --parent "" --no-start`.
- Never clear or change a parent that has no `gh_number`; a human or an agent set it.

A child keeps its own milestone and project; it does not move with its epic.

## 5. Comments

Fetch comments created or edited in the last three days, for the whole repository at once:

```
gh api "repos/<repo>/issues/comments?since=<now minus 3 days, ISO 8601>&per_page=100" --paginate
```

Skip comments whose `html_url` contains `/pull/` (those belong to pull requests) and comments on issues that have no Multica issue. For an issue created in this run, fetch all its comments instead with `gh api "repos/<repo>/issues/<number>/comments?per_page=100" --paginate`.

A comment is already synced when its `html_url` appears in the "Created by" line of a Multica comment on that issue (`multica issue comment list <id> --output json --full`).

- Not synced yet: add it, in exactly this format, with no `/note` or other prefix:
  ```
  <comment body>

  Created by: <author login> (<comment html_url>)
  ```
  `multica issue comment add <id> --content-file <file>`
- Already synced, and the GitHub body differs from the Multica comment body (the text above the "Created by" line): update it with `multica issue comment update <comment id> --content-file <file> --expected-revision <revision>`, keeping the same footer. Take the revision from the comment list.

Never edit or delete comments that were not created by this sync.

## 6. Closed issues

List the Multica issues that have `gh_number` and are not `done` or `cancelled`. Page through `multica issue list --output json --fields id,status,metadata --limit 100 --offset <n>` until `has_more` is false and keep those with a `gh_number`. For each one whose number was not in the open list from step 3 (the closed list does not count), check it:

```
gh issue view <number> --repo <repo> --json state,stateReason,url
```

- Still open (for example it was not returned because of the limit): do nothing.
- Closed and the Multica issue is in `backlog`: set it to `done`, or to `cancelled` when `stateReason` is `NOT_PLANNED`.
- Closed and the Multica issue is in any other status: add a comment `/note Closed on GitHub (<url>).` unless that note is already there. Do not change the status.
- Not found (deleted or transferred): add a comment `/note No longer on GitHub.` unless that note is already there.

## 7. Summary

End with one line: repo, projects created, projects updated, issues created, issues updated, issues moved (sub-issues counted separately), parent links set or cleared, comments added, comments updated, issues closed.
