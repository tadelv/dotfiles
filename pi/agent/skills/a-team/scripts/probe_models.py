#!/usr/bin/env python3
"""Check that the models in a subagent routing profile can actually run an agent loop.

Routing itself is native: `subagents.agentOverrides` in settings.json, or a saved
profile under ~/.pi/agent/profiles/pi-subagents/. Pi-subagents resolves one
model per launch; model retries are explicit later launches, not part of this
probe.

This checks two protocol failures:

  - tool calls emitted as text (`<tool_call>` XML) instead of structured
    `tool_calls`: the provider reports success and the agent loop stalls;
  - tool results rejected outright (e.g. Cohere wants `outputs`): HTTP 200 on the
    first turn, 400 on the second.

Run it when a profile starts misbehaving, or after editing one. Output is one
line per model plus a verdict; exit 1 if any probed model fails.

Usage:
    probe_models.py                       # default profile (daily)
    probe_models.py --profile daily      # profiles/pi-subagents/<name>.json
    probe_models.py --profile free
    probe_models.py --settings            # the effective agentOverrides in settings.json
    probe_models.py -m MODEL [-m MODEL]   # explicit models
    probe_models.py --show-free           # OpenRouter's currently free model ids
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://openrouter.ai/api/v1"
AUTH = os.path.expanduser("~/.pi/agent/auth.json")
SETTINGS = os.path.expanduser("~/.pi/agent/settings.json")
PROFILE_DIR = os.path.expanduser("~/.pi/agent/profiles/pi-subagents")
DEFAULT_PROFILE = "daily"
PER_REQUEST_TIMEOUT = 90
PROBE_PREFIX = "openrouter/"

# Providers that pass the generic shape but reject pi's serialization in ways the
# probe cannot reproduce. Keep the exact error beside each entry.
DENYLIST = {
    # "invalid request: all elements in tool_results must have the 'outputs'
    # property specified." (Cohere's native validator, via OpenRouter)
    "cohere/north-mini-code:free",
}

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "bash",
            "description": "Run a shell command",
            "parameters": {
                "type": "object",
                "properties": {"command": {"type": "string"}},
                "required": ["command"],
            },
        },
    }
]

XML_MARKERS = ("<tool_call>", "<function=", "<invoke", "<dots_function_call>")


def log(message: str) -> None:
    print(message, file=sys.stderr)


def api_key() -> str:
    with open(AUTH) as fh:
        key = json.load(fh).get("openrouter", {}).get("key", "")
    if not key:
        sys.exit("no openrouter key in auth.json")
    return key


def post(key: str, payload: dict) -> tuple[int, dict]:
    req = urllib.request.Request(
        f"{API}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=PER_REQUEST_TIMEOUT) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as err:
        body = err.read().decode(errors="replace")
        try:
            return err.code, json.loads(body)
        except json.JSONDecodeError:
            return err.code, {"error": {"message": body[:200]}}
    except Exception as err:  # timeout, DNS, reset
        return 0, {"error": {"message": f"{type(err).__name__}: {err}"}}


def error_of(payload: dict) -> str:
    err = payload.get("error")
    if not err:
        return ""
    if isinstance(err, dict):
        return str(err.get("message") or err)[:120]
    return str(err)[:120]


def probe(key: str, model: str) -> tuple[bool, str, float]:
    """Two turns: a structured tool call, then our tool result accepted back."""
    started = time.time()
    turn1 = {
        "model": model,
        "max_tokens": 300,
        "messages": [{"role": "user", "content": "Run `ls` using the bash tool."}],
        "tools": TOOLS,
    }
    status, body = post(key, turn1)
    if status != 200:
        return False, f"HTTP {status} {error_of(body)}", time.time() - started

    try:
        message = body["choices"][0]["message"]
    except (KeyError, IndexError):
        return False, "no choices in response", time.time() - started

    calls = message.get("tool_calls")
    if not calls:
        content = str(message.get("content") or "")
        reason = (
            "tool call emitted as text, not structured"
            if any(marker in content for marker in XML_MARKERS)
            else "no structured tool_calls"
        )
        return False, reason, time.time() - started

    turn2 = {
        "model": model,
        "max_tokens": 300,
        "messages": [
            turn1["messages"][0],
            {"role": "assistant", "content": None, "tool_calls": calls},
            {
                "role": "tool",
                "tool_call_id": calls[0].get("id", "call_1"),
                "content": "CHANGELOG.md  README.md",
            },
        ],
    }
    status, body = post(key, turn2)
    if status != 200:
        return False, f"tool result rejected: HTTP {status} {error_of(body)}", time.time() - started

    return True, "ok", time.time() - started


def live_free_models(key: str) -> list[str]:
    req = urllib.request.Request(f"{API}/models", headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.load(resp).get("data", [])
    except Exception as err:
        log(f"could not list live models: {type(err).__name__}: {err}")
        return []
    free = []
    for entry in data:
        pricing = entry.get("pricing") or {}
        try:
            zero = float(pricing.get("prompt", 1)) == 0 and float(pricing.get("completion", 1)) == 0
        except (TypeError, ValueError):
            continue
        if zero and entry.get("id"):
            free.append((entry.get("created") or 0, entry["id"]))
    free.sort(reverse=True)
    return [model_id for _, model_id in free]


def profile_overrides(name: str) -> dict:
    """agentOverrides from a saved profile, or from settings.json."""
    if name == "--settings":
        path, label = SETTINGS, "settings.json"
    else:
        path = os.path.join(PROFILE_DIR, f"{name}.json")
        label = path
    try:
        with open(path) as fh:
            data = json.load(fh)
    except FileNotFoundError:
        available = sorted(
            f[: -len(".json")] for f in os.listdir(PROFILE_DIR) if f.endswith(".json")
        ) if os.path.isdir(PROFILE_DIR) else []
        sys.exit(f"no profile at {path}\navailable: {', '.join(available) or 'none'}")
    except json.JSONDecodeError as err:
        sys.exit(f"{path} is not valid JSON: {err}")
    log(f"profile: {label}")
    return (data.get("subagents") or {}).get("agentOverrides") or {}


def models_in(overrides: dict) -> list[tuple[str, str]]:
    """(agent, model) pairs: every configured primary, deduped in order."""
    seen: set[str] = set()
    pairs: list[tuple[str, str]] = []
    for agent, fields in overrides.items():
        model = fields.get("model")
        if model and model not in seen:
            seen.add(model)
            pairs.append((agent, model))
    return pairs


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Verify routing-profile models can run an agent loop.")
    parser.add_argument("--profile", default=DEFAULT_PROFILE, help=f"saved profile (default: {DEFAULT_PROFILE})")
    parser.add_argument("--settings", action="store_true", help="read agentOverrides from settings.json")
    parser.add_argument("-m", "--model", action="append", default=[], help="explicit model (repeatable)")
    parser.add_argument("--show-free", action="store_true", help="print OpenRouter's free model ids and exit")
    args = parser.parse_args(argv)

    key = api_key()

    if args.show_free:
        for model in live_free_models(key):
            print(f"{PROBE_PREFIX}{model}")
        return 0

    if args.model:
        pairs = [("(explicit)", model) for model in args.model]
    else:
        overrides = profile_overrides("--settings" if args.settings else args.profile)
        pairs = models_in(overrides)
        if not pairs:
            sys.exit("no models found to probe")

    checked: list[tuple[str, str, str]] = []
    skipped = [m for _, m in pairs if m.startswith(PROBE_PREFIX) and m[len(PROBE_PREFIX):] in DENYLIST]

    for agent, model in pairs:
        bare = model[len(PROBE_PREFIX):] if model.startswith(PROBE_PREFIX) else model
        if model in skipped:
            print(f"  [skip]          {model:56} denylisted: known pi-incompatible")
            checked.append((model, "skip", "denylisted"))
            continue
        if not model.startswith(PROBE_PREFIX):
            # Non-OpenRouter providers need their own API; not probed here.
            print(f"  [--]            {model:56} not an OpenRouter model, not probed")
            continue
        usable, reason, seconds = probe(key, bare)
        state = "OK  " if usable else "FAIL"
        print(f"  [{state}] {seconds:5.1f}s  {model:56} {reason}")
        checked.append((model, "ok" if usable else "fail", reason))

    failures = [m for m, state, _ in checked if state == "fail"]
    denylisted = [m for m, state, _ in checked if state == "skip"]
    if failures:
        print(f"\n{len(failures)} model(s) cannot run an agent loop:")
        for model in failures:
            print(f"  - {model}")
        print("Replace them in the profile before relying on it.")
        return 1

    probed = sum(1 for _, state, _ in checked if state == "ok")
    other = len(pairs) - len(checked)
    if probed == 0 and other > 0:
        print(f"\nNo OpenRouter models to probe — {other} non-OpenRouter model(s) skipped.")
        return 0
    extra = f", {len(skipped)} denylisted" if skipped else ""
    print(f"\n{probed} model(s) OK{extra}, {other} not probed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
