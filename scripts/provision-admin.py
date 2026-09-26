"""Create the local-only first admin; keep credentials out of deployment output."""
import json
import secrets
import urllib.request
from pathlib import Path

ROOT = Path(r'C:\AI\yanai')
BASE = 'http://127.0.0.1:8082'
credential_path = ROOT / '.secrets' / 'first-login.json'

def request(path, payload=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    data = json.dumps(payload).encode() if payload is not None else None
    with urllib.request.urlopen(urllib.request.Request(BASE + path, data=data, headers=headers), timeout=60) as response:
        return json.load(response)

if credential_path.exists():
    credentials = json.loads(credential_path.read_text())
    user = request('/api/v1/auths/signin', credentials)
else:
    credentials = {'email': 'ethanxucoder@gmail.com', 'password': secrets.token_urlsafe(24)}
    # Write before the request so an interrupted run can safely sign in on retry.
    credential_path.write_text(json.dumps(credentials), encoding='utf-8')
    user = request('/api/v1/auths/signup', {**credentials, 'name': 'Ethan'})
assert user['role'] == 'admin', 'Expected initial administrator'
token = user['token']
# Signup is open, so every later account must start pending (no model access) until approved.
admin_config = request('/api/v1/auths/admin/config', token=token)
assert admin_config['DEFAULT_USER_ROLE'] == 'pending', 'New signups would not need approval; do not publish'
config = request('/api/config')
assert not config.get('onboarding'), 'Admin onboarding is still enabled'
(ROOT / '.secrets' / 'first-login.txt').write_text(
    'YanAI\nhttps://ai.ethanyanxu.com\n\nEmail: ' + credentials['email'] +
    '\nPassword: ' + credentials['password'] +
    '\n\nChange this password in Settings > Account after signing in.\n', encoding='utf-8')
print('Admin account ready; new signups need approval; credentials saved in .secrets/first-login.txt')
