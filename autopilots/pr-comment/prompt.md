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

If the PR is not one created by us, add it to "In Review" and assign it to kooper. Set the project based on the GitHub milestone: projects whose description ends with `GitHub milestone: <milestone url>` belong to that milestone. Use the milestone of the issue it closes or references; milestones contain issues, not PRs, so use the PR's own milestone only when it links no issue. Never set or change a milestone on the PR. With no milestone, use the project "No milestone". If the milestone has no project yet, leave it in "No milestone"; the GitHub Issue Sync autopilot creates milestone projects.

## 2. CI failures

For every open PR that is not a draft, check the checks on its current head:

```
gh pr checks <number> --repo <repo> --json name,state,bucket,link
```

Skip PRs whose checks are all passing, or still pending or queued (the next run looks again). For a PR with a failing check (`bucket` is `fail`):

- Report each failure once per head commit. Look at the sub-issue's comments first: if one already contains `CI failed on <first 7 characters of headRefOid>`, skip it.
- Our PR: get the sub-issue with `multica issue get <KEY>`.
  - If the sub-issue is `done` or `cancelled`, skip it.
  - If it is `blocked`, or an agent is already running on it (`multica issue runs <KEY>` shows a `running` or `queued` run), only add the comment below without a mention; the run in progress will see it.
  - Otherwise add a comment on the sub-issue that mentions the Builder ([@Builder](mention://agent/<id>), id from `multica agent list --output json`):
    ```
    CI failed on <short sha>: <check name> (<link>)
    <the first failing test or error line from gh run view <run-id> --repo <repo> --log-failed, at most 10 lines>
    Fix it, or re-run it once if it is unrelated to the change, and hand off again only with CI green.
    ```
    For a PR in a stack, also say which PR it is stacked on; a failure that started after the base branch changed usually needs a restack.
- Not our PR: add the same comment, without mentioning any agent, on the Multica issue that tracks it (the one this autopilot created in step 1).

## 3. Merge conflicts

A PR has a conflict when `mergeable` is `CONFLICTING` (or `mergeStateStatus` is `DIRTY`). `UNKNOWN` means GitHub is still computing it: skip it, the next run looks again. `BEHIND` alone is not a conflict and needs nothing.

For each conflicting PR, report it once per head and base commit: skip it if the sub-issue already has a comment containing `Merge conflict on <short headRefOid> against <baseRefName>@<short baseRefOid>`. Otherwise, with the same rules as for CI failures (skip `done` or `cancelled`; no mention when `blocked` or an agent is running; not our PR: no agent mention, on its tracking issue):

```
Merge conflict on <short headRefOid> against <baseRefName>@<short baseRefOid>: <PR url>
Restack it (gh stack rebase, then gh stack push) and cascade up the stack. A conflict you cannot resolve safely goes to the human.
```

Mention the Builder. If the base is another sub-issue's branch, the conflict usually means a PR lower in the stack changed or was merged; say which.

## 4. Summary

End with one line: PRs checked, comments acted on, CI failures reported, merge conflicts reported, skipped as already reported.
