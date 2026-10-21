#!/usr/bin/env python3
"""Search and download GIFs from Tenor's public website (no API key)."""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HOME = Path.home()
STATE = HOME / ".local/state/omarchy"
GIF_DIR = STATE / "tweet-gifs"
MAX_BYTES = 15 * 1024 * 1024
LIMIT = 24
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:142.0) Gecko/20100101 Firefox/142.0"
TENOR_HOST_RE = re.compile(r"(^|\.)tenor\.com$", re.I)
STORE_RE = re.compile(
    r'<script id="store-cache" type="text/x-cache"[^>]*>([^<]+)</script>'
)


def fail(message: str, code: int = 1) -> None:
    print(json.dumps({"ok": False, "error": message}))
    raise SystemExit(code)


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False))


def get(url: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "*/*",
            "Referer": "https://tenor.com/",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.read()
    except urllib.error.HTTPError as exc:
        fail(f"GIF search failed ({exc.code}).")
    except urllib.error.URLError:
        fail("Could not reach Tenor. Check the network and try again.")
    except TimeoutError:
        fail("GIF search timed out.")
    return b""


def slug(query: str) -> str:
    text = re.sub(r"[^a-z0-9]+", "-", query.lower()).strip("-")
    return text


def search_url(query: str) -> str:
    s = slug(query)
    if not s:
        return "https://tenor.com/"
    return f"https://tenor.com/search/{urllib.parse.quote(s)}-gifs"


def walk_results(obj) -> list[dict]:
    found: list[dict] = []

    def walk(node) -> None:
        if found:
            return
        if isinstance(node, dict):
            rows = node.get("results")
            if (
                isinstance(rows, list)
                and rows
                and isinstance(rows[0], dict)
                and "media_formats" in rows[0]
            ):
                found.extend(rows)
                return
            for value in node.values():
                walk(value)
                if found:
                    return
        elif isinstance(node, list):
            for value in node:
                walk(value)
                if found:
                    return

    walk(obj)
    return found


def allowed_url(url: str) -> bool:
    host = urllib.parse.urlparse(url).hostname or ""
    return bool(url.startswith("https://") and TENOR_HOST_RE.search(host))


def pick_source(formats: dict) -> tuple[str, str, int]:
    ranked = ("gif", "mediumgif", "tinygif")
    fallback = ("", "", 0)
    for name in ranked:
        item = formats.get(name) or {}
        url = str(item.get("url") or "")
        size = int(item.get("size") or 0)
        if not url or not allowed_url(url):
            continue
        if size > MAX_BYTES:
            fallback = (url, name, size)
            continue
        return url, name, size
    return fallback


def compact(item: dict) -> dict | None:
    formats = item.get("media_formats") or {}
    url, _kind, size = pick_source(formats)
    preview = str((formats.get("tinygif") or formats.get("nanogif") or {}).get("url") or "")
    if not url:
        return None
    if preview and not allowed_url(preview):
        preview = url
    if not preview:
        preview = url
    title = (
        str(item.get("content_description") or item.get("title") or item.get("h1_title") or "")
        .strip()
    )
    return {
        "id": str(item.get("id") or ""),
        "title": title,
        "preview": preview,
        "url": url,
        "bytes": size,
    }


def cmd_search(query: str) -> None:
    html = get(search_url(query)).decode("utf-8", "ignore")
    match = STORE_RE.search(html)
    if not match:
        fail("Tenor changed its search page. GIFs could not be listed.")
    try:
        store = json.loads(match.group(1))
    except json.JSONDecodeError:
        fail("Could not read GIF results.")
    items = []
    seen: set[str] = set()
    for raw in walk_results(store):
        row = compact(raw)
        if not row or not row["id"] or row["id"] in seen:
            continue
        seen.add(row["id"])
        items.append(row)
        if len(items) >= LIMIT:
            break
    emit({"ok": True, "query": query, "items": items})


def prune_cache() -> None:
    files = sorted(GIF_DIR.glob("*.gif"), key=lambda p: p.stat().st_mtime, reverse=True)
    for stale in files[24:]:
        stale.unlink(missing_ok=True)


def cmd_fetch(url: str, gif_id: str) -> None:
    if not allowed_url(url):
        fail("That GIF is not from Tenor.")
    GIF_DIR.mkdir(parents=True, exist_ok=True)
    safe_id = re.sub(r"[^a-zA-Z0-9_-]+", "", gif_id)[:40] or "gif"
    dest = GIF_DIR / f"{safe_id}.gif"
    if dest.is_file() and dest.stat().st_size > 0:
        prune_cache()
        emit({"ok": True, "path": str(dest)})
        return
    data = get(url)
    if len(data) > MAX_BYTES:
        fail("That GIF is larger than X allows (15 MB).")
    if not data:
        fail("Downloaded GIF was empty.")
    dest.write_bytes(data)
    prune_cache()
    emit({"ok": True, "path": str(dest)})


def main() -> None:
    args = sys.argv[1:]
    if not args or args[0] not in {"search", "fetch"}:
        fail("Usage: gif.py search [query] | gif.py fetch <url> [id]")
    if args[0] == "search":
        cmd_search(" ".join(args[1:]).strip())
        return
    if len(args) < 2:
        fail("Usage: gif.py fetch <url> [id]")
    cmd_fetch(args[1], args[2] if len(args) > 2 else "")


if __name__ == "__main__":
    main()
