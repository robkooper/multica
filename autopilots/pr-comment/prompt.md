# Check open PRs: comments, CI and merge conflicts

This workspace has one GitHub repository: get it with `multica repo list --output json` and use its `<owner>/<repo>`. If there is not exactly one repository, report that in one line and stop.

List the open PRs:

```
gh pr list --repo <repo> --state open --json number,title,author,headRefName,headRefOid,baseRefName,baseRefOid,milestone,isDraft,mergeable,mergeStateStatus,url
```

A PR is ours when its branch starts with a Multica issue key in lowercase (for example `lum-73-refresh-key`). That issue is its sub-issue. All agents push as the human's GitHub account, so the author does not tell you whether a PR is ours; the branch does.

Never post anything on GitHub. Everything you report goes in Multica comments.

## 1. Comments

Check every open PR for comments left on GitHub. If there are new comments that are not from us, look at them and see if they indicate something that needs to be fixed. A comment whose first line is "**How to test**" is from us (the Senior Reviewer's testing note): skip it.

A PR that is not ours gets exactly one tracking issue in Multica, ever. It carries the metadata `gh_pr` (the PR number). Before creating one, look for it, whatever its status: `multica issue list --metadata gh_pr=<number> --output json`. Older tracking issues have no metadata yet: also look for a title that starts with `PR #<number> ` or contains `PR #<number> (external)` (page through `multica issue list`), and when you find one, set `gh_pr` on it with `multica issue metadata set <id> --key gh_pr --value <number>`. If a tracking issue exists, never create another one, also when it is `done` or `cancelled`: the human closed it on purpose. Only when none exists, create it: title `PR #<number> (external): <PR title>`, status `in_review`, assigned to the workspace owner (role owner in `multica workspace member list --output json`), then set `gh_pr`. Set the project based on the GitHub milestone: projects whose description ends with `GitHub milestone: <milestone url>` belong to that milestone. Use the milestone of the issue it closes or references; milestones contain issues, not PRs, so use the PR's own milestone only when it links no issue. Never set or change a milestone on the PR. With no milestone, use the project "No milestone". If the milestone has no project yet, leave it in "No milestone"; the GitHub Issue Sync autopilot creates milestone projects.

Close tracking issues of PRs that are no longer open: list the tracking issues that are not `done` or `cancelled` (page through `multica issue list --output json --fields id,status,metadata --limit 100 --offset <n>` until `has_more` is false and keep those with `gh_pr`), and for each one whose PR is not in the open PR list, read it with `gh pr view <number> --repo <repo> --json state,mergedAt,url`. Merged: set the issue to `done`; closed without merging: set it to `cancelled` (`multica issue update <id> --status <status> --no-start`), and add `/note PR <state, lowercase> on GitHub (<url>).`

## 2. CI failures

Only our PRs: never report failing checks on a PR that is not ours; its author handles them. For every open PR of ours that is not a draft, check the checks on its current head:

```
gh pr checks <number> --repo <repo> --json name,state,bucket,link
```

Skip PRs whose checks are all passing, or still pending or queued (the next run looks again). For a PR with a failing check (`bucket` is `fail`):

- Report each failure once per head commit. Look at the sub-issue's comments first: if one already contains `CI failed on <first 7 characters of headRefOid>`, skip it.
- Our PR: get the sub-issue with `multica issue get <KEY>`.
  - If the sub-issue is `done` or `cancelled`, skip it.
  - Otherwise add the comment below on the sub-issue and start the Builder on it: end the comment with a mention of the Builder ([@Builder](mention://agent/<id>), id from `multica agent list --output json`). This autopilot runs as the Lead, and the Lead never reacts to its own comments, so a comment without the mention would start nobody. Leave the mention out only when the sub-issue is `blocked` or an agent is already running on it (`multica issue runs <KEY>` shows a `running` or `queued` run); that run will see the comment.
    ```
    CI failed on <short sha>: <check name> (<link>)
    <the first failing test or error line from gh run view <run-id> --repo <repo> --log-failed, at most 10 lines>
    Fix it, or re-run it once if it is unrelated to the change, and hand off again only with CI green.
    ```
    For a PR in a stack, also say which PR it is stacked on; a failure that started after the base branch changed usually needs a restack.

## 3. Merge conflicts

A PR has a conflict when `mergeable` is `CONFLICTING` (or `mergeStateStatus` is `DIRTY`). `UNKNOWN` means GitHub is still computing it: skip it, the next run looks again. `BEHIND` alone is not a conflict and needs nothing.

Only our PRs: never report a merge conflict on a PR that is not ours; its author resolves it. For each conflicting PR of ours, report it once per head commit, however often the base moves: skip it if the sub-issue already has a comment containing `Merge conflict on <short headRefOid>`. Otherwise, with the same rules as for CI failures (skip `done` or `cancelled`; mention the Builder unless the sub-issue is `blocked` or an agent is already running on it):

```
Merge conflict on <short headRefOid> against <baseRefName>@<short baseRefOid>: <PR url>
Restack it (gh stack rebase, then gh stack push) and cascade up the stack. A conflict you cannot resolve safely goes to the human.
```

If the base is another sub-issue's branch, the conflict usually means a PR lower in the stack changed or was merged; say which.

## 4. Summary

End with one line: PRs checked, comments acted on, CI failures reported, merge conflicts reported, skipped as already reported.
