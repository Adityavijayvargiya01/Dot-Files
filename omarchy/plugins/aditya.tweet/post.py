#!/usr/bin/env python3
"""Post to X using the default browser's signed-in session, after consent."""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

from twikit import Client

HOME = Path.home()
STATE = HOME / ".local/state/omarchy"
CONSENT_PATH = STATE / "tweet-consent.json"
BEARER_UA = (
    "Mozilla/5.0 (X11; Linux x86_64; rv:142.0) Gecko/20100101 Firefox/142.0"
)

FIREFOX_DESKTOPS = {
    "zen": "Zen",
    "zen-browser": "Zen",
    "firefox": "Firefox",
    "firefox-esr": "Firefox",
    "librewolf": "LibreWolf",
    "floorp": "Floorp",
    "waterfox": "Waterfox",
}

CHROMIUM_DESKTOPS = {
    "chromium": ("Chromium", HOME / ".config/chromium"),
    "chromium-browser": ("Chromium", HOME / ".config/chromium"),
    "google-chrome": ("Google Chrome", HOME / ".config/google-chrome"),
    "google-chrome-stable": ("Google Chrome", HOME / ".config/google-chrome"),
    "google-chrome-beta": ("Chrome Beta", HOME / ".config/google-chrome-beta"),
    "brave-browser": ("Brave", HOME / ".config/BraveSoftware/Brave-Browser"),
    "brave": ("Brave", HOME / ".config/BraveSoftware/Brave-Browser"),
    "vivaldi-stable": ("Vivaldi", HOME / ".config/vivaldi"),
    "vivaldi": ("Vivaldi", HOME / ".config/vivaldi"),
    "microsoft-edge": ("Edge", HOME / ".config/microsoft-edge"),
    "microsoft-edge-stable": ("Edge", HOME / ".config/microsoft-edge"),
    "helium": ("Helium", HOME / ".config/net.imput.helium"),
    "net.imput.helium": ("Helium", HOME / ".config/net.imput.helium"),
}


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def desktop_id() -> str:
    try:
        raw = subprocess.check_output(
            ["xdg-settings", "get", "default-web-browser"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if raw:
            return Path(raw).name
    except (OSError, subprocess.CalledProcessError):
        pass
    env = os.environ.get("BROWSER", "")
    return Path(env).name if env else ""


def desktop_stem(desktop: str) -> str:
    name = desktop.lower()
    if name.endswith(".desktop"):
        name = name[: -len(".desktop")]
    return name


def browser_meta() -> dict:
    desktop = desktop_id()
    stem = desktop_stem(desktop)
    if stem in FIREFOX_DESKTOPS:
        return {
            "desktop": desktop,
            "engine": "firefox",
            "name": FIREFOX_DESKTOPS[stem],
            "id": stem,
        }
    if stem in CHROMIUM_DESKTOPS:
        label, root = CHROMIUM_DESKTOPS[stem]
        return {
            "desktop": desktop,
            "engine": "chromium",
            "name": label,
            "id": stem,
            "root": str(root),
        }
    # Prefix match: google-chrome-unstable, brave-browser-beta, zen-...
    for key, label in FIREFOX_DESKTOPS.items():
        if stem.startswith(key):
            return {"desktop": desktop, "engine": "firefox", "name": label, "id": key}
    for key, (label, root) in CHROMIUM_DESKTOPS.items():
        if stem.startswith(key):
            return {
                "desktop": desktop,
                "engine": "chromium",
                "name": label,
                "id": key,
                "root": str(root),
            }
    return {
        "desktop": desktop or "",
        "engine": "",
        "name": "your default browser",
        "id": stem,
    }


def firefox_roots(browser_id: str) -> list[Path]:
    mapping = {
        "zen": [HOME / ".config/zen", HOME / ".zen"],
        "zen-browser": [HOME / ".config/zen", HOME / ".zen"],
        "firefox": [HOME / ".mozilla/firefox"],
        "firefox-esr": [HOME / ".mozilla/firefox"],
        "librewolf": [HOME / ".librewolf", HOME / ".config/librewolf"],
        "floorp": [HOME / ".floorp", HOME / ".config/floorp"],
        "waterfox": [HOME / ".waterfox", HOME / ".config/waterfox"],
    }
    return [p for p in mapping.get(browser_id, []) if p.is_dir()]


def firefox_cookie_dbs(browser_id: str) -> list[Path]:
    found: list[Path] = []
    for root in firefox_roots(browser_id):
        ini = root / "profiles.ini"
        ordered: list[str] = []
        if ini.is_file():
            install_default = None
            paths: list[str] = []
            section = ""
            for raw in ini.read_text(encoding="utf-8").splitlines():
                line = raw.strip()
                if line.startswith("[") and line.endswith("]"):
                    section = line[1:-1]
                    continue
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key == "Path":
                    paths.append(value)
                if section.startswith("Install") and key == "Default":
                    install_default = value
            if install_default:
                ordered.append(install_default)
            ordered.extend(p for p in paths if p not in ordered)
        for rel in ordered:
            db = (root / rel / "cookies.sqlite").resolve()
            if db.is_file() and db not in found:
                found.append(db)
        for db in root.glob("*/cookies.sqlite"):
            resolved = db.resolve()
            if resolved not in found:
                found.append(resolved)
    return found


def read_firefox_cookies(db_path: Path) -> dict[str, str]:
    uri = f"file:{db_path}?immutable=1"
    con = sqlite3.connect(uri, uri=True)
    try:
        rows = con.execute(
            "SELECT name, value FROM moz_cookies "
            "WHERE host LIKE '%x.com' OR host LIKE '%twitter.com'"
        ).fetchall()
    finally:
        con.close()
    return {name: value for name, value in rows}


def chromium_profile_dir(root: Path) -> Path:
    local_state = root / "Local State"
    if local_state.is_file():
        try:
            data = json.loads(local_state.read_text(encoding="utf-8"))
            info = data.get("profile", {})
            last = info.get("last_used") or info.get("last_active")
            if last and (root / last / "Cookies").is_file():
                return root / last
        except (OSError, json.JSONDecodeError):
            pass
    for name in ("Default", "Profile 1", "Profile 2"):
        if (root / name / "Cookies").is_file():
            return root / name
    for cookies in root.glob("*/Cookies"):
        return cookies.parent
    return root / "Default"


def chrome_key() -> bytes:
    try:
        import secretstorage  # type: ignore

        bus = secretstorage.dbus_init()
        collection = secretstorage.get_default_collection(bus)
        for item in collection.get_all_items():
            label = item.get_label() or ""
            if "Safe Storage" in label and any(
                n in label for n in ("Chrome", "Chromium", "Brave", "Vivaldi", "Edge", "Helium")
            ):
                secret = item.get_secret()
                if secret:
                    from hashlib import pbkdf2_hmac

                    return pbkdf2_hmac("sha1", secret, b"saltysalt", 1, 16)
    except Exception:
        pass
    from hashlib import pbkdf2_hmac

    return pbkdf2_hmac("sha1", b"peanuts", b"saltysalt", 1, 16)


def decrypt_chrome_value(blob: bytes, key: bytes) -> str:
    if not blob:
        return ""
    prefix = blob[:3]
    data = blob[3:] if prefix in (b"v10", b"v11") else blob
    if len(data) < 16:
        return ""
    try:
        from Crypto.Cipher import AES

        cipher = AES.new(key, AES.MODE_CBC, IV=b" " * 16)
        plain = cipher.decrypt(data)
        pad = plain[-1]
        if 1 <= pad <= 16:
            plain = plain[:-pad]
        return plain.decode("utf-8", errors="ignore")
    except Exception:
        return ""


def read_chromium_cookies(root: Path) -> dict[str, str]:
    profile = chromium_profile_dir(root)
    db_path = profile / "Cookies"
    if not db_path.is_file():
        return {}
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(prefix="tweet-cookies-")
        os.close(fd)
        shutil.copy2(db_path, tmp)
        con = sqlite3.connect(f"file:{tmp}?immutable=1", uri=True)
        rows = con.execute(
            "SELECT name, value, encrypted_value FROM cookies "
            "WHERE host_key LIKE '%x.com' OR host_key LIKE '%twitter.com'"
        ).fetchall()
        con.close()
    except sqlite3.Error:
        return {}
    finally:
        if tmp:
            Path(tmp).unlink(missing_ok=True)

    key = chrome_key()
    cookies: dict[str, str] = {}
    for name, value, encrypted in rows:
        if value:
            cookies[name] = value
            continue
        decoded = decrypt_chrome_value(encrypted or b"", key)
        if decoded:
            cookies[name] = decoded
    return cookies


def load_session_cookies() -> tuple[dict[str, str], dict]:
    meta = browser_meta()
    engine = meta.get("engine")
    cookies: dict[str, str] = {}
    if engine == "firefox":
        for db in firefox_cookie_dbs(meta["id"]):
            cookies = read_firefox_cookies(db)
            if cookies.get("auth_token") and cookies.get("ct0"):
                break
    elif engine == "chromium":
        cookies = read_chromium_cookies(Path(meta["root"]))
    else:
        fail(
            "Default browser is not Firefox or Chromium based. "
            "Set Firefox, Zen, Chrome, Chromium, or Brave as default."
        )
    return cookies, meta


def require_consent() -> None:
    if not CONSENT_PATH.is_file():
        fail("Session access is not granted yet.")
    try:
        data = json.loads(CONSENT_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        fail("Session access is not granted yet.")
    if data.get("session") != "allow":
        fail("Session access was denied. Allow it from the composer to post.")


def session_payload(need_values: bool) -> dict:
    meta = browser_meta()
    signed_in = False
    if meta.get("engine") and need_values:
        cookies, _ = load_session_cookies()
        signed_in = bool(cookies.get("auth_token") and cookies.get("ct0"))
    elif meta.get("engine") == "firefox":
        for db in firefox_cookie_dbs(meta["id"]):
            names = set(read_firefox_cookies(db))
            if "auth_token" in names and "ct0" in names:
                signed_in = True
                break
    elif meta.get("engine") == "chromium":
        cookies = read_chromium_cookies(Path(meta["root"]))
        signed_in = bool(cookies.get("auth_token") and cookies.get("ct0"))
    return {
        "ok": True,
        "browser": meta.get("name") or "your default browser",
        "engine": meta.get("engine") or "",
        "desktop": meta.get("desktop") or "",
        "signedIn": signed_in,
    }


def media_kind(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if suffix in {".mp4", ".mov", ".webm", ".mkv", ".m4v"}:
        return "video"
    if suffix == ".gif":
        return "gif"
    return "image"


async def upload_files(client: Client, paths: list[str]) -> list[str]:
    ids: list[str] = []
    for raw in paths:
        path = Path(raw).expanduser()
        if not path.is_file():
            fail(f"Missing attachment: {path}")
        kind = media_kind(str(path))
        kwargs: dict = {}
        if kind == "video":
            kwargs["wait_for_completion"] = True
        elif kind == "gif":
            kwargs["wait_for_completion"] = True
            kwargs["media_category"] = "tweet_gif"
        media_id = await client.upload_media(str(path), **kwargs)
        ids.append(str(media_id))
    return ids


async def post_text(text: str, media: list[str] | None = None) -> str:
    cookies, meta = load_session_cookies()
    if "auth_token" not in cookies or "ct0" not in cookies:
        fail(
            f"Not signed into X in {meta.get('name') or 'your browser'}. "
            "Open x.com, sign in, then try again."
        )
    client = Client(language="en-US", user_agent=BEARER_UA)
    client.set_cookies(
        {
            "auth_token": cookies["auth_token"],
            "ct0": cookies["ct0"],
            "twid": cookies.get("twid", ""),
            "guest_id": cookies.get("guest_id", ""),
        }
    )
    media = [p for p in (media or []) if str(p).strip()]
    try:
        media_ids = await upload_files(client, media) if media else None
        tweet = await client.create_tweet(
            text=text or "",
            media_ids=media_ids,
        )
    except Exception as exc:
        msg = str(exc) or exc.__class__.__name__
        if "KEY_BYTE" in msg:
            fail("X changed its request signing. Update the composer poster and try again.")
        fail(msg)
    tweet_id = getattr(tweet, "id", None) or getattr(tweet, "rest_id", None)
    if not tweet_id:
        fail("X accepted the request but did not return a post id.")
    return str(tweet_id)


def read_body() -> str:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if args:
        return Path(args[0]).read_text(encoding="utf-8")
    return sys.stdin.read()


def main() -> None:
    if "--probe" in sys.argv:
        print(json.dumps(session_payload(need_values=False)))
        return

    require_consent()

    if "--check" in sys.argv:
        print(json.dumps(session_payload(need_values=True)))
        return

    raw = read_body()
    text = raw
    media: list[str] = []
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict) and ("text" in parsed or "media" in parsed):
            text = str(parsed.get("text") or "")
            media = [str(p) for p in (parsed.get("media") or []) if str(p).strip()]
    except json.JSONDecodeError:
        pass
    if not text.replace("\n", "").strip() and not media:
        fail("Empty post.")
    tweet_id = asyncio.run(post_text(text, media))
    print(json.dumps({"ok": True, "id": tweet_id}))


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        fail(str(exc) or exc.__class__.__name__)
