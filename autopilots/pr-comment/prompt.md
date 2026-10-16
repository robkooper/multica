# check comments on PR

This workspace has one GitHub repository: get it with `multica repo list --output json` and use its `<owner>/<repo>`. If there is not exactly one repository, report that in one line and stop.

All open PRs in that repository should be checked on GitHub to see if any comments are left. If new comments are left and are not from us, then look at them and see if they indicate something that needs to be fixed.

If the PR is not one created by us, add to “In Review” and assign to kooper. Make sure to set the project based on the GitHub milestone: projects whose description ends with `GitHub milestone: <milestone url>` belong to that milestone. Use the PR's milestone, or the milestone of the issue it closes when the PR has none. With no milestone, use the project "No milestone". If the milestone has no project yet, leave it in "No milestone"; the GitHub Issue Sync autopilot creates milestone projects.
