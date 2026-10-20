#!/usr/bin/env python3
"""Redeliver the latest GitHub App pull_request event for each PR of a repo.

Multica only links a PR to an issue when it receives a pull_request webhook,
and it only receives events for workspaces bound to the GitHub App at the time.
After connecting a workspace to the App later, run this on the Multica server
to replay one event per PR, so existing PRs get mirrored and linked.

Only the newest delivery per PR is redelivered: replaying older ones could
briefly roll a merged PR back to open. Dry run by default.

    python3 redeliver_pr_events.py <owner/repo> [--days 14] [--env ~/multica/.env] [--apply]

Needs: python3 and openssl. Reads GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY from
the Multica .env file; the key never leaves this machine.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

API = "https://api.github.com"


def read_env(path):
    """Minimal .env parser that handles a double-quoted multi-line value."""
    env, lines, i = {}, open(os.path.expanduser(path)).read().splitlines(), 0
    while i < len(lines):
        line = lines[i].strip()
        i += 1
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key, val = key.strip(), val.strip()
        if val.startswith('"') and not (len(val) > 1 and val.endswith('"')):
            parts = [val[1:]]
            while i < len(lines):
                nxt = lines[i]
                i += 1
                if nxt.rstrip().endswith('"'):
                    parts.append(nxt.rstrip()[:-1])
                    break
                parts.append(nxt)
            val = "\n".join(parts)
        elif len(val) > 1 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        env[key] = val.replace("\\n", "\n")
    return env


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def app_jwt(app_id, private_key):
    now = int(time.time())
    head = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    body = b64url(json.dumps({"iat": now - 60, "exp": now + 540, "iss": str(app_id)}).encode())
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        os.chmod(f.name, 0o600)
        f.write(private_key.strip() + "\n")
        keyfile = f.name
    try:
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", keyfile],
                             input=f"{head}.{body}".encode(), capture_output=True, check=True).stdout
    finally:
        os.unlink(keyfile)
    return f"{head}.{body}.{b64url(sig)}"


def call(method, path, token=None, with_next=False):
    url = path if path.startswith("http") else API + path
    req = urllib.request.Request(url, method=method, headers={
        "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
        **({"Authorization": f"Bearer {token}"} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read()
            data = json.loads(body) if body else None
            if not with_next:
                return data
            nxt = None
            for part in (r.headers.get("Link") or "").split(","):
                if 'rel="next"' in part:
                    nxt = part.split(";")[0].strip().strip("<>")
            return data, nxt
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()[:300]}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("repo", help="owner/repo, e.g. ncsa/lumen")
    ap.add_argument("--days", type=int, default=14, help="look back this many days (GitHub keeps about 30)")
    ap.add_argument("--env", default="~/multica/.env", help="Multica .env with the App credentials")
    ap.add_argument("--apply", action="store_true", help="redeliver (default: dry run)")
    a = ap.parse_args()

    env = read_env(a.env)
    if not env.get("GITHUB_APP_ID") or "PRIVATE KEY" not in env.get("GITHUB_APP_PRIVATE_KEY", ""):
        sys.exit(f"GITHUB_APP_ID / GITHUB_APP_PRIVATE_KEY not found in {a.env}")
    token = app_jwt(env["GITHUB_APP_ID"], env["GITHUB_APP_PRIVATE_KEY"])
    repo_id = call("GET", f"/repos/{a.repo}")["id"]
    since = datetime.now(timezone.utc) - timedelta(days=a.days)

    # Walk deliveries newest first; keep the first (newest) pull_request delivery per PR.
    latest, url, scanned, done = {}, "/app/hook/deliveries?per_page=100", 0, False
    while url and not done:
        page, url = call("GET", url, token, with_next=True)
        if not page:
            break
        for d in page:
            when = datetime.fromisoformat(d["delivered_at"].replace("Z", "+00:00"))
            if when < since:
                done = True
                break
            if d.get("event") != "pull_request" or d.get("repository_id") != repo_id or d.get("redelivery"):
                continue
            scanned += 1
            full = call("GET", f"/app/hook/deliveries/{d['id']}", token)
            pr = ((full.get("request") or {}).get("payload") or {}).get("pull_request") or {}
            if pr.get("number") and pr["number"] not in latest:
                latest[pr["number"]] = (d["id"], d["delivered_at"], d.get("action"), pr.get("state"), pr.get("head", {}).get("ref"))

    print(f"{a.repo}: {scanned} pull_request deliveries in the last {a.days} days, {len(latest)} PRs")
    for number, (did, when, action, state, ref) in sorted(latest.items()):
        print(f"  #{number} {state:6} {ref}  ({action} at {when})")
        if a.apply:
            call("POST", f"/app/hook/deliveries/{did}/attempts", token)
    print("redelivered" if a.apply else "dry run: add --apply to redeliver", len(latest))


if __name__ == "__main__":
    main()
