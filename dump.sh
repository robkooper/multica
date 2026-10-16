#!/usr/bin/env bash
# Dump the skills, agents and squads of one Multica workspace into this repo.
# Run once from the repo root:  ./dump.sh <workspace id, slug or UUID>
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "usage: $0 <workspace id, slug or UUID>"; echo
  multica workspace list
  exit 1
fi
# accept a short ID, slug or full UUID; the API needs the full UUID
WS=$(multica workspace get "$1" --output json | jq -r .id)
mc() { multica --workspace-id "$WS" "$@"; }
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'; }

runtimes=$(mc runtime list --output json)
mkdir -p skills agents squads

# Skills: SKILL.md plus any supporting files
mc skill list --output json | jq -r '.[].id' | while read -r id; do
  s=$(mc skill get "$id" --output json)
  d="skills/$(slug "$(jq -r .name <<<"$s")")"
  mkdir -p "$d"
  jq -r .content <<<"$s" > "$d/SKILL.md"
  jq '{name, description, config}' <<<"$s" > "$d/skill.json"
  jq -c '.files[]?' <<<"$s" | while read -r f; do
    p=$(jq -r .path <<<"$f")
    case "$p" in /*|*..*) echo "skip unsafe path $p in $d"; continue;; esac
    mkdir -p "$d/files/$(dirname "$p")"
    jq -r .content <<<"$f" > "$d/files/$p"
  done
  echo "skill  $d"
done

# Agents: instructions.md plus portable settings (runtime stored as provider)
mc agent list --output json | jq -r '.[] | select((.system_key // "") == "") | .id' | while read -r id; do
  a=$(mc agent get "$id" --output json)
  d="agents/$(slug "$(jq -r .name <<<"$a")")"
  mkdir -p "$d"
  jq -r .instructions <<<"$a" > "$d/instructions.md"
  provider=$(jq -r --arg r "$(jq -r .runtime_id <<<"$a")" '.[] | select(.id == $r) | .provider' <<<"$runtimes")
  jq --arg p "$provider" '{
      name, description, provider: $p, model, thinking_level, service_tier,
      custom_args, max_concurrent_tasks,
      public_to_workspace: ([.invocation_targets[]? | select(.target_type == "workspace")] | length > 0),
      skills: [.skills[]?.name],
      conversation_starters
    }' <<<"$a" > "$d/agent.json"
  [ "$(jq -r .has_custom_env <<<"$a")" = true ] && echo "  note: $d has custom env vars, not exported (secrets)"
  [ "$(jq -r '.mcp_config != null' <<<"$a")" = true ] && echo "  note: $d has an MCP config, not exported (may hold tokens)"
  echo "agent  $d"
done

# Squads: instructions.md plus leader and members by agent name
agents=$(mc agent list --output json)
mc squad list --output json | jq -r '.[].id' | while read -r id; do
  s=$(mc squad get "$id" --output json)
  m=$(mc squad member list "$id" --output json)
  d="squads/$(slug "$(jq -r .name <<<"$s")")"
  mkdir -p "$d"
  jq -r .instructions <<<"$s" > "$d/instructions.md"
  jq -n --argjson s "$s" --argjson m "$m" --argjson a "$agents" '
    def aname($id): ($a[] | select(.id == $id) | .name) // $id;
    { name: $s.name, description: $s.description, leader: aname($s.leader_id),
      members: [ $m[] | select(.member_type == "agent") | {name: aname(.member_id), role} ],
      human_members: [ $m[] | select(.member_type == "member") | {member_id, role} ] }' > "$d/squad.json"
  echo "squad  $d"
done

# Autopilots: prompt.md plus settings and triggers (agent and project by name)
projects=$(mc project list --output json)
mkdir -p autopilots
mc autopilot list --output json | jq -r '(.autopilots // .)[].id' | while read -r id; do
  a=$(mc autopilot get "$id" --output json | jq '.autopilot // .')
  t=$(mc autopilot trigger-list "$id" --output json | jq '.triggers // .')
  d="autopilots/$(slug "$(jq -r .title <<<"$a")")"
  mkdir -p "$d"
  jq -r '.description // ""' <<<"$a" > "$d/prompt.md"
  jq -n --argjson a "$a" --argjson t "$t" --argjson ag "$agents" --argjson p "$projects" '
    { title: $a.title,
      mode: $a.execution_mode,
      status: $a.status,
      assignee_type: $a.assignee_type,
      agent: (($ag[] | select(.id == $a.assignee_id) | .name) // $a.assignee_id),
      project: (if $a.project_id then (($p[] | select(.id == $a.project_id) | .title) // null) else null end),
      issue_title_template: $a.issue_title_template,
      triggers: [ $t[] | {kind, enabled, cron: .cron_expression, timezone, label} ] }' > "$d/autopilot.json"
  jq -e '.assignee_type != "agent"' "$d/autopilot.json" >/dev/null && echo "  note: $d is assigned to a $(jq -r .assignee_type "$d/autopilot.json"); apply only supports agents"
  jq -e 'any(.triggers[]; .kind == "webhook")' "$d/autopilot.json" >/dev/null && echo "  note: $d has a webhook trigger; its URL, secret and event filters are not exported"
  echo "autopilot $d"
done
