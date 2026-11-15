# Multica agent configuration

Skills, agents and squads for Multica, kept as code. Prompts live in plain
Markdown so changes show up as readable diffs.

    skills/<name>/SKILL.md        skill content (plus skill.json, files/)
    agents/<name>/instructions.md agent prompt
    agents/<name>/agent.json      runtime provider, model, access, skills
    squads/<name>/instructions.md squad (leader) instructions
    squads/<name>/squad.json      leader and members by agent name
    autopilots/<name>/prompt.md   autopilot prompt
    autopilots/<name>/autopilot.json  mode, agent, project, schedule triggers

To set up a blank Ubuntu VM (server in Docker behind Caddy, a `multica` user with Claude Code, Codex, OpenCode, the daemon as a systemd user service), copy `setup-vm.sh` to it and run `./setup-vm.sh install` (it asks for the domain and the agents' git identity); it prints the manual logins and the next steps (`lockdown`, then `daemon`). Only the git email you give it can sign up; others need an invitation. With `SMTP_HOST` and `SMTP_FROM_EMAIL` set, `install` also sets up email for login codes and invitations; `./setup-vm.sh mail` adds it to an existing install (run the script without arguments for the other `SMTP_*` options). Later, `./setup-vm.sh upgrade` backs up the database to `~/multica-backups`, updates the server and the `multica` CLI, and restarts the daemon; the coding CLIs update themselves nightly.

Requires `multica` (logged in) and `jq`. Run from the repo root. <workspace>
is an ID, slug or UUID; run a script without arguments to list workspaces.
<runtime match> is text only the VM's runtimes contain, such as its hostname;
leave it out to see the runtime list.

Dump a workspace once:

    ./dump.sh <workspace>

Apply to a workspace (creates what is missing, updates the rest):

    ./apply.sh <workspace> <runtime match>

After connecting a workspace to the GitHub App, existing PRs are not linked until GitHub sends a new event for them. On the Multica server, replay the latest event per PR (dry run without `--apply`):

    python3 redeliver_pr_events.py <owner/repo> [--days 14] [--apply]

Files in `skills/<name>/files/` are uploaded as the skill's supporting files.

Not stored here: custom environment variables and MCP configs (secrets),
and human squad members (people differ per workspace). Set those in the UI.
New autopilots are created paused so they never run in two workspaces at
once: pause the old one, then activate the new one. Webhook triggers get a new
URL, and their signing secret and event filters must be set in the UI.
Agents, squads and autopilots are matched by name, so renaming one creates a new one.

Layout: one workspace per GitHub repository (added under Settings → Code, exactly one per workspace) and one Multica project per GitHub milestone. The GitHub Issue Sync autopilot finds the repo with `multica repo list`, creates and updates the milestone projects, and puts issues without a milestone in the project "No milestone". The same autopilots work unchanged in every workspace.
