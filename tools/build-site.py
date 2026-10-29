#!/usr/bin/env python3
"""Builds the GitHub Pages site: site/pages/*.html fragments + site/template.html -> _site/.

Each fragment starts with `<!-- title: ... -->` (and optionally `<!-- description: ... -->`).
`<!-- shot: name | caption -->` becomes a light/dark screenshot from site/images/name-{light,dark}.png.
No dependencies beyond Python 3, so the Pages workflow runs it as is.

    python3 tools/build-site.py            # writes _site/
    python3 -m http.server -d _site 8000   # look at it
"""
import html
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
OUT = ROOT / "_site"

# Navigation order: (file, label).
NAV = [
    ("index.html", "Home"),
    ("install.html", "Install"),
    ("overview.html", "Overview"),
    ("browsing.html", "Installed & Find More"),
    ("updates.html", "Updates"),
    ("backups.html", "Backups"),
    ("ai.html", "AI"),
    ("settings.html", "Settings"),
    ("cli.html", "Command Line"),
    ("minion.html", "Coming from Minion"),
    ("troubleshooting.html", "Troubleshooting"),
]


def meta(text: str, key: str, default: str = "") -> str:
    m = re.search(rf"<!--\s*{key}:\s*(.*?)\s*-->", text)
    return m.group(1) if m else default


def shots(text: str) -> str:
    def picture(m: re.Match) -> str:
        name, caption = m.group(1).strip(), (m.group(2) or "").strip()
        alt = html.escape(caption or name)
        cap = f"<figcaption>{caption}</figcaption>" if caption else ""
        return (
            f'<figure class="shot"><picture>'
            f'<source srcset="images/{name}-dark.png" media="(prefers-color-scheme: dark)">'
            f'<img src="images/{name}-light.png" alt="{alt}" loading="lazy"></picture>{cap}</figure>'
        )

    return re.sub(r"<!--\s*shot:\s*([^|>]+?)(?:\|\s*(.*?))?\s*-->", picture, text)


def nav(current: str) -> str:
    items = []
    for file, label in NAV:
        here = ' aria-current="page"' if file == current else ""
        items.append(f'<li><a href="{file}"{here}>{html.escape(label)}</a></li>')
    return "\n".join(items)


def main() -> None:
    template = (SITE / "template.html").read_text()
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    for file, label in NAV:
        source = (SITE / "pages" / file).read_text()
        title = meta(source, "title", label)
        page = (
            template.replace("{{title}} · MacMinion" if title == "MacMinion" else "{{title}}", html.escape(title))
            .replace("{{description}}", html.escape(meta(source, "description", "MacMinion documentation")))
            .replace("{{nav}}", nav(file))
            .replace("{{content}}", shots(source))
        )
        (OUT / file).write_text(page)
    for extra in ["style.css", "appcast.xml"]:
        shutil.copy(SITE / extra, OUT / extra)
    shutil.copytree(SITE / "images", OUT / "images")
    (OUT / ".nojekyll").write_text("")
    print(f"built {len(NAV)} pages into {OUT}")


if __name__ == "__main__":
    main()
