#!/usr/bin/env python3
"""Writes site/pages/cli.html from the app's own command list (`macminion help --json`), so the
reference always matches the CLI. Run after changing Sources/MacMinion/Agent/AgentCommands.swift:

    python3 tools/gen-cli-docs.py [path-to-macminion]
"""
import html
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
binary = sys.argv[1] if len(sys.argv) > 1 else "macminion"
commands = json.loads(subprocess.check_output([binary, "help", "--json"]))["commands"]

GROUPS = [("Status and catalog", ["status", "catalog", "categories", "folders", "history", "open"]),
          ("Addons", ["addons", "updates", "libraries", "refresh"]),
          ("Backups", ["backups"]),
          ("AI", ["ai"])]


def group_of(name: str) -> str:
    noun = name.split()[0]
    for title, nouns in GROUPS:
        if noun in nouns:
            return title
    return "Other"


def render(c: dict) -> str:
    summary, _, example = c["description"].partition(" Example: ")
    props = c["inputSchema"].get("properties", {})
    required = set(c["inputSchema"].get("required", []))
    kind = "reads only" if c.get("readOnly") else ("asks for --yes" if c.get("destructive") else "changes things")
    rows = "".join(
        f"<tr><td><code>--{html.escape(n)}</code>{' (required)' if n in required else ''}</td>"
        f"<td>{html.escape(p.get('type', 'string'))}</td><td>{html.escape(p.get('description', ''))}</td></tr>"
        for n, p in props.items()
    )
    table = f"<table><tr><th>Option</th><th>Type</th><th>Meaning</th></tr>{rows}</table>" if rows else ""
    anchor = c["name"].replace(" ", "-")
    return (f'<h3 id="{anchor}"><code>macminion {html.escape(c["name"])}</code> <small>· {kind}</small></h3>\n'
            f"<p>{html.escape(summary)}</p>\n{table}\n<pre><code>{html.escape(example)}</code></pre>\n")


parts = ["""<!-- title: Command Line -->
<!-- description: The macminion command: every command, its options, and examples. Generated from the app. -->
<h1>Command line</h1>
<p class="lead"><code>macminion</code> runs commands in the MacMinion app, so the window updates as they run. If the
app is closed, a command opens it in the background.</p>
<h2>Basics</h2>
<ul>
  <li>Put it on your PATH: see <a href="install.html#cli">Install</a>.</li>
  <li>Add <code>--json</code> for output scripts and AI agents can read. Errors come back as <code>{"error": {"code", "message"}}</code> with a nonzero exit code.</li>
  <li>Addons are named by their ESOUI id: the number in <code>esoui.com/downloads/info&lt;id&gt;</code>.</li>
  <li>Commands that remove things only report what they would do until you add <code>--yes</code>.</li>
  <li><code>macminion help</code> lists everything; <code>macminion help &lt;command&gt;</code> shows one.</li>
  <li><code>macminion mcp</code> serves the same commands to MCP clients such as Claude Desktop.</li>
</ul>
<pre><code>macminion status --json
macminion addons list --status update --json
macminion updates install --json</code></pre>
<p>This page is generated from the app's own command list.</p>
"""]
by_group: dict[str, list] = {}
for c in commands:
    by_group.setdefault(group_of(c["name"]), []).append(c)
for title, _ in GROUPS + [("Other", [])]:
    if title in by_group:
        parts.append(f"<h2>{title}</h2>\n" + "".join(render(c) for c in by_group[title]))
out = ROOT / "site/pages/cli.html"
out.write_text("".join(parts))
print(f"wrote {out} ({len(commands)} commands)")
