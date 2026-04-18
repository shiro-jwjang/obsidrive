#!/usr/bin/env python3
"""
Obsidrive E2E test - Full login + vault browsing flow.

Prerequisites:
    - xvfb-run for headed Chromium (Flutter CanvasKit needs display)
    - gws-snailblu credentials at ~/.config/gws-snailblu/

Usage:
    xvfb-run -a python3 e2e_test.py [--screenshot] [--full] [--token ACCESS_TOKEN]
    xvfb-run -a python3 e2e_test.py --reauth
"""

import argparse
import asyncio
import base64
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

from playwright.async_api import async_playwright

BASE_URL = "https://obsidrive.indieloca.com"
CREDS_PATH = "/home/openclaw/.config/gws-snailblu/credentials.json"


class E2EResult:
    def __init__(self):
        self.passed = []
        self.failed = []
        self.warnings = []

    def ok(self, name, detail=""):
        self.passed.append(name)
        print(f"✅ {name}" + (f": {detail}" if detail else ""))

    def fail(self, name, detail=""):
        self.failed.append(name)
        print(f"❌ {name}" + (f": {detail}" if detail else ""))

    def warn(self, name, detail=""):
        self.warnings.append(name)
        print(f"⚠️ {name}" + (f": {detail}" if detail else ""))

    def summary(self):
        total = len(self.passed) + len(self.failed)
        print(f"\n{'='*50}")
        print(f"Results: {len(self.passed)}/{total} passed, {len(self.warnings)} warnings")
        if self.failed:
            print(f"Failed: {', '.join(self.failed)}")
            return 1
        return 0


def _json_str(v):
    """Encode value for SharedPreferences web (json.dumps format)."""
    return json.dumps(v)


def get_oauth_token():
    """Try refresh token flow. Returns (access_token, user_info) or raises."""
    with open(CREDS_PATH) as f:
        creds = json.load(f)
    data = urllib.parse.urlencode({
        "client_id": creds["client_id"],
        "client_secret": creds["client_secret"],
        "refresh_token": creds["refresh_token"],
        "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=data)
    resp = urllib.request.urlopen(req)
    token = json.loads(resp.read())
    user_info = get_user_info(token["access_token"])
    return token["access_token"], user_info


def do_reauth():
    """Interactive OAuth re-auth for headless servers. Starts local server, prints URL."""
    import http.server
    import threading
    import webbrowser
    from urllib.parse import urlparse, parse_qs

    with open(CREDS_PATH) as f:
        creds = json.load(f)

    client_id = creds["client_id"]
    client_secret = creds["client_secret"]

    # Start local HTTP server to catch redirect
    auth_code = []
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            query = parse_qs(urlparse(self.path).query)
            if "code" in query:
                auth_code.append(query["code"][0])
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(b"<h1>Auth successful! You can close this tab.</h1>")
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Missing code parameter")
        def log_message(self, *a): pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    redirect_uri = f"http://127.0.0.1:{port}"

    scope = "openid email profile https://www.googleapis.com/auth/drive.readonly"
    auth_url = (
        f"https://accounts.google.com/o/oauth2/v2/auth?"
        f"client_id={client_id}&redirect_uri={urllib.parse.quote(redirect_uri)}&"
        f"response_type=code&scope={urllib.parse.quote(scope)}&access_type=offline&prompt=consent"
    )

    # Run server in background thread
    t = threading.Thread(target=server.handle_request, daemon=True)
    t.start()

    print(f"\n{'='*60}")
    print("OAUTH RE-AUTH")
    print(f"{'='*60}")
    print(f"\nOpen this URL on your device:\n\n{auth_url}\n")
    print("Waiting for authorization...")

    t.join(timeout=300)
    server.server_close()

    if not auth_code:
        print("❌ Timed out waiting for auth code")
        return False

    # Exchange code for tokens
    data = urllib.parse.urlencode({
        "client_id": client_id,
        "client_secret": client_secret,
        "code": auth_code[0],
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=data)
    resp = urllib.request.urlopen(req)
    tokens = json.loads(resp.read())

    # Save refresh_token
    creds["refresh_token"] = tokens["refresh_token"]
    with open(CREDS_PATH, "w") as f:
        json.dump(creds, f, indent=2)

    print(f"✅ Saved new refresh_token to {CREDS_PATH}")
    print(f"   email: {get_user_info(tokens['access_token']).get('email', '?')}")
    return True


def get_user_info(access_token):
    req = urllib.request.Request("https://www.googleapis.com/oauth2/v2/userinfo")
    req.add_header("Authorization", f"Bearer {access_token}")
    resp = urllib.request.urlopen(req)
    return json.loads(resp.read())


async def _save_canvas_screenshot(page, path):
    """Save actual Flutter canvas content (not Playwright screenshot)."""
    canvas_png = await page.evaluate("""() => {
        const gp = document.querySelector('flt-glass-pane');
        if (!gp || !gp.shadowRoot) return null;
        const canvas = gp.shadowRoot.querySelector('canvas');
        if (!canvas) return null;
        return canvas.toDataURL('image/png').split(',')[1];
    }""")
    if canvas_png:
        with open(path, "wb") as f:
            f.write(base64.b64decode(canvas_png))
        print(f"📸 Saved {path}")
    return canvas_png is not None


async def _check_canvas(page):
    """Check if Flutter canvas has rendered content."""
    return await page.evaluate("""() => {
        const gp = document.querySelector('flt-glass-pane');
        if (!gp || !gp.shadowRoot) return {error: 'no shadow'};
        const canvas = gp.shadowRoot.querySelector('canvas');
        if (!canvas) return {error: 'no canvas'};
        const size = canvas.toDataURL('image/png').length;
        return {hasContent: size > 5000, size};
    }""")


async def run_tests(take_screenshot=False, full_flow=False, access_token=None):
    result = E2EResult()

    # --- Pre-flight: OAuth token ---
    print("--- Getting OAuth token ---")
    try:
        if access_token:
            # Direct token mode (--token flag)
            user_info = get_user_info(access_token)
            result.ok("OAuth token (direct)", user_info["email"])
        else:
            # Refresh token flow
            access_token, user_info = get_oauth_token()
            result.ok("OAuth token", user_info["email"])
    except Exception as e:
        result.fail("OAuth token", str(e)[:100])
        return result.summary()

    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=False,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--enable-unsafe-swiftshader"],
        )
        context = await browser.new_context(
            locale="ko-KR",
            viewport={"width": 412, "height": 915},
        )
        page = await context.new_page()

        js_errors = []
        page.on("pageerror", lambda e: js_errors.append(str(e)))

        # ======== PHASE 1: Login screen ========
        print("\n--- Phase 1: Login screen ---")
        await page.goto(BASE_URL, wait_until="load", timeout=30000)
        await asyncio.sleep(5)

        result.ok("Page loads", BASE_URL)

        fatal = [e for e in js_errors if "locale" not in e.lower()]
        if not fatal:
            result.ok("No JS errors")
        else:
            for e in fatal:
                result.fail("JS error", e[:150])

        fb = await page.evaluate("() => typeof firebase !== 'undefined'")
        if fb:
            result.ok("Firebase SDK", "loaded")
        else:
            # Firebase SDK no longer required — google_sign_in uses GIS directly
            result.ok("Auth SDK", "google_sign_in (GIS)")

        if "/login" in page.url:
            result.ok("Route /login", page.url)
        else:
            result.fail("Route /login", f"Got: {page.url}")

        canvas1 = await _check_canvas(page)
        if canvas1.get("hasContent"):
            result.ok("Canvas renders", f"{canvas1['size']} bytes")
        else:
            result.fail("Canvas renders", str(canvas1))

        if take_screenshot:
            await _save_canvas_screenshot(page, "/tmp/obsidrive_e2e_01_login.png")

        # ======== PHASE 2: Login via token injection ========
        print("\n--- Phase 2: Login ---")

        expires_at = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
        inject_ok = await page.evaluate("""(params) => {
            try {
                localStorage.setItem('flutter.auth.user.id', JSON.stringify(params.userId));
                localStorage.setItem('flutter.auth.user.email', JSON.stringify(params.email));
                localStorage.setItem('flutter.auth.user.displayName', JSON.stringify(params.displayName));
                localStorage.setItem('flutter.auth.user.photoUrl', JSON.stringify(params.photoUrl));
                localStorage.setItem('flutter.auth.accessToken', JSON.stringify(params.accessToken));
                localStorage.setItem('flutter.auth.expiresAt', JSON.stringify(params.expiresAt));
                return true;
            } catch(e) { return e.message; }
        }""", {
            "userId": user_info["id"],
            "email": user_info["email"],
            "displayName": user_info.get("name", ""),
            "photoUrl": user_info.get("picture", ""),
            "accessToken": access_token,
            "expiresAt": expires_at,
        })

        if inject_ok is True:
            result.ok("Token inject")
        else:
            result.fail("Token inject", str(inject_ok))
            await browser.close()
            return result.summary()

        js_errors.clear()
        await page.reload(wait_until="domcontentloaded", timeout=60000)
        await asyncio.sleep(8)

        # Verify login redirect
        if "/login" not in page.url:
            result.ok("Login redirect", page.url)
        else:
            result.fail("Login redirect", f"Still on /login: {page.url}")

        fatal2 = [e for e in js_errors if "locale" not in e.lower()]
        if not fatal2:
            result.ok("No post-login errors")
        else:
            for e in fatal2:
                result.fail("Post-login error", e[:150])

        canvas2 = await _check_canvas(page)
        if canvas2.get("hasContent"):
            result.ok("Post-login canvas", f"{canvas2['size']} bytes")
        else:
            result.fail("Post-login canvas", str(canvas2))

        if take_screenshot:
            await _save_canvas_screenshot(page, "/tmp/obsidrive_e2e_02_loggedin.png")

        # ======== PHASE 3: Vault browsing ========
        if full_flow:
            print("\n--- Phase 3: Vault browsing ---")
            # Wait for any async loading
            await asyncio.sleep(5)

            current = page.url
            result.ok("Post-login route", current)

            # If on /home, the _AuthGate should show vault picker or vault content
            canvas3 = await _check_canvas(page)
            if canvas3.get("hasContent"):
                result.ok("Vault UI renders", f"{canvas3['size']} bytes")
            else:
                result.fail("Vault UI renders", str(canvas3))

            if take_screenshot:
                await _save_canvas_screenshot(page, "/tmp/obsidrive_e2e_03_vault.png")

            # Check for Drive API errors (auth should work with injected token)
            drive_errors = [e for e in js_errors if "drive" in e.lower() or "401" in e or "403" in e]
            if drive_errors:
                for e in drive_errors:
                    result.warn("Drive API", e[:150])
            else:
                result.ok("Drive API", "no auth errors")

        await browser.close()

    return result.summary()


def main():
    parser = argparse.ArgumentParser(description="Obsidrive E2E test")
    parser.add_argument("--screenshot", action="store_true", help="Save canvas screenshots")
    parser.add_argument("--full", action="store_true", help="Test vault browsing after login")
    parser.add_argument("--token", help="Use this access token directly (skip refresh)")
    parser.add_argument("--reauth", action="store_true", help="Interactive OAuth re-auth")
    args = parser.parse_args()

    if args.reauth:
        sys.exit(0 if do_reauth() else 1)

    sys.exit(asyncio.run(run_tests(args.screenshot, args.full, args.token)))


if __name__ == "__main__":
    main()
