#!/usr/bin/env python3
"""
Obsidrive smoke test: build → deploy → verify.

Usage:
    python3 smoke_test.py              # build + deploy + test
    python3 smoke_test.py --test-only  # test only (no build/deploy)
"""
import argparse, subprocess, sys

FLUTTER = "/home/openclaw/flutter/bin/flutter"
PROJECT = "/home/openclaw/projects/obsidrive"
E2E = f"{PROJECT}/e2e_test.py"

def run(cmd, cwd=PROJECT):
    print(f"\n>>> {cmd}")
    r = subprocess.run(cmd, shell=True, cwd=cwd)
    if r.returncode != 0:
        print(f"❌ Failed (exit {r.returncode})")
        return False
    return True

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-only", action="store_true")
    args = parser.parse_args()

    if not args.test_only:
        print("=" * 50)
        print("Obsidrive Smoke Test: Build → Deploy → Verify")
        print("=" * 50)

        # 1. Build
        if not run(f"{FLUTTER} build web"):
            return 1

        # 2. Verify Firebase config intact
        r = subprocess.run(
            ['python3', '-c', """
import re
with open('build/web/index.html') as f: html = f.read()
assert 'firebase-config.js' in html, 'Missing firebase-config.js reference'
assert 'firebase-app-compat.js' in html, 'Missing compat SDK'
print('✅ Firebase compat SDK OK')
with open('build/web/firebase-config.js') as f: js = f.read()
keys = re.findall(r'AIzaSy[a-zA-Z0-9_-]{32}', js)
assert len(keys) == 1, f'Expected 1 API key in firebase-config.js, found {len(keys)}'
print(f'✅ API key OK (firebase-config.js)')
assert 'firebase.initializeApp' in js, 'Missing initializeApp'
print('✅ Firebase config OK')
"""],
            capture_output=True, text=True, cwd=PROJECT
        )
        print(r.stdout)
        if r.returncode != 0:
            print(r.stderr)
            return 1

        # 3. Deploy
        if not run("docker exec obsidrive-web nginx -s reload"):
            return 1

        print("\n✅ Build & deploy complete. Running E2E...")

    # 4. E2E test
    return subprocess.run(
        f"xvfb-run -a python3 {E2E} --screenshot --full",
        shell=True, cwd=PROJECT
    ).returncode

if __name__ == "__main__":
    sys.exit(main())
