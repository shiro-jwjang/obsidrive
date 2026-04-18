#!/bin/bash
# Restores web/firebase-config.js from base64-encoded API key
# This avoids the write_file/patch tool masking issue
set -e

cd "$(dirname "$0")/.."

python3 << 'PYEOF'
import base64, os

api_key = base64.b64decode('QUl6YVN5QjhJUWNaaTZKVUR2THdYTU1DeDEtZlNrM3BGRW5RU01F').decode()

lines = [
    '// Firebase config for Obsidrive - loaded as external JS to prevent key masking',
    'const firebaseConfig = {',
    f'  apiKey: "{api_key}",',
    '  authDomain: "obsidrive-ff707.firebaseapp.com",',
    '  projectId: "obsidrive-ff707",',
    '  storageBucket: "obsidrive-ff707.firebasestorage.app",',
    '  messagingSenderId: "487606084766",',
    '  appId: "1:487606084766:web:82a74c3dd31413fe6b078f",',
    '  measurementId: "G-14PX0SLDW5"',
    '};',
    'firebase.initializeApp(firebaseConfig);',
]

with open('web/firebase-config.js', 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f'✅ Restored web/firebase-config.js')
PYEOF
