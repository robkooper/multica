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

Requires `multica` (logged in) and `jq`. Run from the repo root. <workspace>
is an ID, slug or UUID; run a script without arguments to list workspaces.
<runtime match> is text only the VM's runtimes contain, such as its hostname;
leave it out to see the runtime list.

Dump a workspace once:

    ./dump.sh <workspace>

Apply to a workspace (creates what is missing, updates the rest):

    ./apply.sh <workspace> <runtime match>

Files in `skills/<name>/files/` are uploaded as the skill's supporting files.

Not stored here: custom environment variables and MCP configs (secrets),
and human squad members (people differ per workspace). Set those in the UI.
New autopilots are created paused so they never run in two workspaces at
once: pause the old one, then activate the new one. Webhook triggers get a new
URL, and their signing secret and event filters must be set in the UI.
Agents, squads and autopilots are matched by name, so renaming one creates a new one.

Layout: one workspace per GitHub repository (added under Settings → Code, exactly one per workspace) and one Multica project per GitHub milestone. The GitHub Issue Sync autopilot finds the repo with `multica repo list`, creates and updates the milestone projects, and puts issues without a milestone in the project "No milestone". The same autopilots work unchanged in every workspace.
