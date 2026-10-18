# Check open PRs: comments and CI

This workspace has one GitHub repository: get it with `multica repo list --output json` and use its `<owner>/<repo>`. If there is not exactly one repository, report that in one line and stop.

List the open PRs:

```
gh pr list --repo <repo> --state open --json number,title,author,headRefName,headRefOid,baseRefName,milestone,isDraft,url
```

A PR is ours when its branch starts with a Multica issue key in lowercase (for example `lum-73-refresh-key`). That issue is its sub-issue. All agents push as the human's GitHub account, so the author does not tell you whether a PR is ours; the branch does.

Never post anything on GitHub. Everything you report goes in Multica comments.

## 1. Comments

Check every open PR for comments left on GitHub. If there are new comments that are not from us, look at them and see if they indicate something that needs to be fixed.

If the PR is not one created by us, add it to "In Review" and assign it to kooper. Set the project based on the GitHub milestone: projects whose description ends with `GitHub milestone: <milestone url>` belong to that milestone. Use the PR's milestone, or the milestone of the issue it closes when the PR has none. With no milestone, use the project "No milestone". If the milestone has no project yet, leave it in "No milestone"; the GitHub Issue Sync autopilot creates milestone projects.

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

## 3. Summary

End with one line: PRs checked, comments acted on, CI failures reported, skipped as already reported.
