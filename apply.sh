#!/usr/bin/env bash
# Create or update skills, agents and squads in a workspace from this repo.
# Safe to re-run. From the repo root:
#   ./apply.sh <workspace id, slug or UUID> <runtime match>
# <runtime match> is text that only the VM's runtimes contain, such as its hostname.
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "usage: $0 <workspace id, slug or UUID> <runtime match>"; echo
  multica workspace list
  exit 1
fi
# accept a short ID, slug or full UUID; the API needs the full UUID
WS=$(multica workspace get "$1" --output json | jq -r .id)
mc() { multica --workspace-id "$WS" "$@"; }
if [ $# -lt 2 ]; then
  echo "usage: $0 $1 <runtime match>"
  echo "Pick text that only the VM's runtimes contain (for example its hostname):"; echo
  mc runtime list
  exit 1
fi
RUNTIME_MATCH=$2
id_by_name() { jq -r --arg n "$2" '.[] | select(.name == $n) | .id' <<<"$1" | head -n1; }

runtimes=$(mc runtime list --output json)
runtime_for() {
  local ids n
  ids=$(jq -r --arg p "$1" --arg m "$RUNTIME_MATCH" '
    .[] | select(.provider == $p and (((.name // "") + " " + (.device_info // "")) | contains($m))) | .id' <<<"$runtimes")
  n=$(printf '%s' "$ids" | grep -c . || true)
  if [ "$n" -ne 1 ]; then
    echo "Runtime match \"$RUNTIME_MATCH\" found $n $1 runtimes, need exactly 1." >&2
    echo "Pick text that only the VM's runtimes contain:" >&2; echo >&2
    mc runtime list >&2
    exit 1
  fi
  printf '%s\n' "$ids"
}

# Check every agent's runtime before changing anything
for f in agents/*/agent.json; do
  [ -f "$f" ] || continue
  runtime_for "$(jq -r .provider "$f")" >/dev/null
done

# Skills
existing=$(mc skill list --output json)
for d in skills/*/; do
  [ -f "$d/skill.json" ] || continue
  name=$(jq -r .name "$d/skill.json"); desc=$(jq -r '.description // ""' "$d/skill.json")
  id=$(id_by_name "$existing" "$name")
  if [ -n "$id" ]; then
    mc skill update "$id" --description "$desc" --content-file "${d}SKILL.md" >/dev/null && echo "updated skill $name"
  else
    id=$(mc skill create --name "$name" --description "$desc" --content-file "${d}SKILL.md" --output json | jq -r .id) && echo "created skill $name"
  fi
  # Supporting files: skills/<name>/files/<path> becomes <path> in the skill
  if [ -d "${d}files" ]; then
    find "${d}files" -type f ! -path '*/__pycache__/*' | sort | while read -r f; do
      p=${f#"${d}files/"}
      mc skill files upsert "$id" --path "$p" --content-file "$f" >/dev/null && echo "  file $p"
    done
  fi
done

# Agents
skills_now=$(mc skill list --output json)
agents_now=$(mc agent list --output json)
for d in agents/*/; do
  f="${d}agent.json"; [ -f "$f" ] || continue
  name=$(jq -r .name "$f")
  rid=$(runtime_for "$(jq -r .provider "$f")") || exit 1
  args=(
    --description "$(jq -r '.description // ""' "$f")"
    --instructions "$(cat "${d}instructions.md")"
    --runtime-id "$rid"
    --model "$(jq -r '.model // ""' "$f")"
    --thinking-level "$(jq -r '.thinking_level // ""' "$f")"
    --custom-args "$(jq -c '.custom_args // []' "$f")"
    --max-concurrent-tasks "$(jq -r '.max_concurrent_tasks // 6' "$f")"
  )
  if [ "$(jq -r .public_to_workspace "$f")" = true ]; then
    args+=(--permission-mode public_to --public-to-workspace)
  else
    args+=(--permission-mode private)
  fi
  id=$(id_by_name "$agents_now" "$name")
  if [ -n "$id" ]; then
    mc agent update "$id" "${args[@]}" >/dev/null && echo "updated agent $name"
  else
    id=$(mc agent create --name "$name" "${args[@]}" --output json | jq -r .id) && echo "created agent $name"
  fi
  skill_ids=$(jq -r '.skills[]?' "$f" | while read -r s; do id_by_name "$skills_now" "$s"; done | paste -sd, -)
  [ -n "$skill_ids" ] && mc agent skills set "$id" --skill-ids "$skill_ids" >/dev/null
done

# Squads
agents_now=$(mc agent list --output json)
squads_now=$(mc squad list --output json)
for d in squads/*/; do
  f="${d}squad.json"; [ -f "$f" ] || continue
  name=$(jq -r .name "$f"); desc=$(jq -r '.description // ""' "$f"); leader=$(jq -r .leader "$f")
  sid=$(id_by_name "$squads_now" "$name")
  if [ -z "$sid" ]; then
    sid=$(mc squad create --name "$name" --description "$desc" --leader "$leader" --output json | jq -r .id)
    echo "created squad $name"
  fi
  mc squad update "$sid" --description "$desc" --leader "$leader" --instructions "$(cat "${d}instructions.md")" >/dev/null
  members_now=$(mc squad member list "$sid" --output json)
  jq -c '.members[]' "$f" | while read -r m; do
    aid=$(id_by_name "$agents_now" "$(jq -r .name <<<"$m")"); role=$(jq -r .role <<<"$m")
    if [ -z "$aid" ]; then echo "  warning: agent $(jq -r .name <<<"$m") not found"; continue; fi
    if jq -e --arg i "$aid" 'any(.[]; .member_id == $i)' <<<"$members_now" >/dev/null; then
      mc squad member set-role "$sid" --member-id "$aid" --role "$role" >/dev/null
    else
      mc squad member add "$sid" --member-id "$aid" --type agent --role "$role" >/dev/null
    fi
  done
  echo "updated squad $name"
  [ "$(jq '.human_members | length' "$f")" -gt 0 ] && echo "  note: add the human members of $name by hand (people differ per workspace)"
done

# Autopilots (new ones are created paused, so they never run in two workspaces at once)
projects_now=$(mc project list --output json)
autopilots_now=$(mc autopilot list --output json | jq '.autopilots // .')
for d in autopilots/*/; do
  f="${d}autopilot.json"; [ -f "$f" ] || continue
  title=$(jq -r .title "$f")
  if [ "$(jq -r .assignee_type "$f")" != agent ]; then echo "  skip autopilot $title: not assigned to an agent"; continue; fi
  agent=$(jq -r .agent "$f")
  [ -n "$(id_by_name "$agents_now" "$agent")" ] || { echo "  skip autopilot $title: agent $agent not found"; continue; }
  project_id=""
  pname=$(jq -r '.project // empty' "$f")
  if [ -n "$pname" ]; then
    project_id=$(jq -r --arg n "$pname" '.[] | select(.title == $n) | .id' <<<"$projects_now" | head -n1)
    [ -n "$project_id" ] || echo "  note: project $pname not found for autopilot $title; created without a project"
  fi
  args=(--description "$(cat "${d}prompt.md")" --agent "$agent" --mode "$(jq -r .mode "$f")")
  tmpl=$(jq -r '.issue_title_template // empty' "$f"); [ -n "$tmpl" ] && args+=(--issue-title-template "$tmpl")
  aid=$(jq -r --arg n "$title" '.[] | select(.title == $n) | .id' <<<"$autopilots_now" | head -n1)
  if [ -n "$aid" ]; then
    mc autopilot update "$aid" --title "$title" "${args[@]}" --project "$project_id" --status "$(jq -r .status "$f")" >/dev/null
    echo "updated autopilot $title"
  else
    [ -n "$project_id" ] && args+=(--project "$project_id")
    aid=$(mc autopilot create --title "$title" "${args[@]}" --output json | jq -r '.autopilot.id // .id')
    mc autopilot update "$aid" --status paused >/dev/null
    echo "created autopilot $title (paused: pause the old one, then multica autopilot update $aid --status active)"
  fi
  # Triggers: add schedules that are missing (matched on cron and timezone); add a webhook if none exists
  existing_t=$(mc autopilot trigger-list "$aid" --output json | jq '.triggers // .')
  jq -c '.triggers[]' "$f" | while read -r t; do
    kind=$(jq -r .kind <<<"$t"); label=$(jq -r '.label // ""' <<<"$t")
    if [ "$kind" = schedule ]; then
      cron=$(jq -r .cron <<<"$t"); tz=$(jq -r '.timezone // "UTC"' <<<"$t")
      if ! jq -e --arg c "$cron" --arg z "$tz" 'any(.[]; .kind == "schedule" and .cron_expression == $c and ((.timezone // "UTC") == $z))' <<<"$existing_t" >/dev/null; then
        mc autopilot trigger-add "$aid" --kind schedule --cron "$cron" --timezone "$tz" --label "$label" >/dev/null
        echo "  added schedule $cron ($tz)"
      fi
    elif [ "$kind" = webhook ]; then
      if ! jq -e 'any(.[]; .kind == "webhook")' <<<"$existing_t" >/dev/null; then
        url=$(mc autopilot trigger-add "$aid" --kind webhook --label "$label" --output json | jq -r '.webhook_url // .trigger.webhook_url // empty')
        echo "  added webhook trigger: point the sender (e.g. GitHub) at ${url:-the URL shown in the UI},"
        echo "  and set its signing secret and event filters in the UI"
      fi
    fi
  done
done
