"""Drive the real Android UI against disposable local Firebase emulators.

Uses adb/UI Automator and uncached Firestore REST reads, with no app test bridge.
Requires an already-installed APP_MODE=emulator build and USB reverse mappings.
Only synthetic accounts created by this run are changed. Never clears app data.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
PROJECT = json.loads((ROOT / '.firebaserc').read_text())['projects']['default']
PACKAGE = 'com.sandhai.app'


class Phone:
    def __init__(self, adb, serial, artifacts):
        self.adb, self.serial, self.artifacts = adb, serial, artifacts
        self.commands = []

    def run(self, *args, binary=False):
        command = [self.adb, '-s', self.serial, *map(str, args)]
        self.commands.append(command)
        return subprocess.check_output(command, timeout=35, text=not binary)

    def nodes(self):
        file = '/data/local/tmp/sandhai-phase2-window.xml'
        # A cold launch on this device takes about 12 seconds. UI Automator can
        # report a null root during that transition; never reuse the previous XML.
        for _ in range(6):
            dumped = self.run('shell', 'uiautomator', 'dump', file)
            if 'dumped to:' in dumped:
                xml = self.run('exec-out', 'cat', file)
                self.last_xml = xml
                return [n.attrib for n in ET.fromstring(xml).iter('node')
                        if n.attrib.get('package') == PACKAGE]
            time.sleep(.5)
        raise AssertionError('UI Automator did not return a fresh hierarchy')

    @staticmethod
    def label(node):
        return node.get('text', '') + '\n' + node.get('content-desc', '')

    def inspect(self):
        return [{k: n.get(k) for k in ['class', 'text', 'content-desc', 'bounds', 'enabled', 'clickable']}
                for n in self.nodes() if self.label(n).strip() or n.get('class') == 'android.widget.EditText']

    def wait(self, value, timeout=40):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            nodes = self.nodes()
            found = [n for n in nodes if value in self.label(n)]
            if found:
                return found[0]
            time.sleep(.3)
        raise AssertionError(f'Phone did not show {value!r}: {self.inspect()}')

    def wait_any(self, values, timeout=40):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for node in self.nodes():
                if any(value in self.label(node) for value in values):
                    return
            time.sleep(.3)
        raise AssertionError(f'Phone did not show any of {values!r}')

    def absent(self, value):
        assert not any(value in self.label(n) for n in self.nodes()), value

    def tap_node(self, node):
        coords = list(map(int, re.findall(r'\d+', node['bounds'])))
        x1, y1, x2, y2 = coords
        assert x2 > x1 and y2 > y1, node
        assert node.get('enabled') == 'true', node
        self.run('shell', 'input', 'tap', (x1+x2)//2, (y1+y2)//2)
        time.sleep(.35)

    def tap(self, value, seek=False):
        for _ in range(8 if seek else 1):
            matches = [n for n in self.nodes() if value in self.label(n)
                       and n.get('clickable') == 'true']
            if matches:
                self.tap_node(matches[0])
                return
            if seek:
                self.scroll()
        raise AssertionError(f'Cannot tap {value!r}: {self.inspect()}')

    def scroll(self, up=False):
        self.run('shell', 'input', 'swipe', 360, 450 if up else 1080,
                 360, 1080 if up else 450, 350)
        time.sleep(.3)

    def fill(self, hint, value, field_index=None):
        # All input is local synthetic fixture data. Keep adb shell input literal.
        assert re.fullmatch(r'[A-Za-z0-9 @._+\-]*', value), value
        for _ in range(8):
            nodes = self.nodes()
            matches = [n for n in nodes if n.get('class') == 'android.widget.EditText'
                       and hint in n.get('content-desc', '')]
            if not matches and field_index is not None:
                # This Flutter version omits filled InputDecoration labels from
                # Android accessibility. Use the existing form's input order.
                fields = [n for n in nodes if n.get('class') == 'android.widget.EditText']
                matches = fields[field_index:field_index+1]
            if not matches:
                # Existing forms use separate visible labels rather than native
                # input labels. Locate the immediately following input in the
                # accessibility tree; no fixed form coordinates are used.
                for i, n in enumerate(nodes):
                    if self.label(n).strip().startswith(hint):
                        lx1, ly1, lx2, ly2 = map(int, re.findall(r'\d+', n['bounds']))
                        following = []
                        for field in nodes[i+1:]:
                            if field.get('class') != 'android.widget.EditText':
                                continue
                            fx1, fy1, fx2, fy2 = map(int, re.findall(r'\d+', field['bounds']))
                            # Side-by-side price fields have both labels before
                            # both inputs in Android's accessibility order.
                            if fx1 <= (lx1+lx2)//2 <= fx2 and fy1 >= ly1:
                                following.append(field)
                        following.sort(key=lambda field: int(re.findall(r'\d+', field['bounds'])[1])-ly2)
                        if following:
                            matches = following[:1]
                            break
            if matches:
                node = matches[0]
                _, y1, _, y2 = map(int, re.findall(r'\d+', node['bounds']))
                if y2-y1 < 50 or y2 > 1380:
                    self.scroll()
                    continue
                self.tap_node(node)
                old_length = len(node.get('text', ''))
                if old_length:
                    self.run('shell', 'input', 'keyevent', '123', *(['67'] * old_length))
                self.run('shell', 'input', 'text', value.replace(' ', '%s'))
                time.sleep(.4)
                self.run('shell', 'input', 'keyevent', '4')  # Dismiss this field's IME.
                time.sleep(.3)
                print(f'Filled {hint}', flush=True)
                return
            self.scroll()
        raise AssertionError(f'Cannot find field {hint!r}: {self.inspect()}')

    def capture(self, name):
        (self.artifacts / f'{name}.png').write_bytes(self.run('exec-out', 'screencap', '-p', binary=True))
        self.nodes()
        (self.artifacts / f'{name}.xml').write_text(self.last_xml)

    def restart(self):
        old = self.run('shell', 'pidof', PACKAGE).strip()
        self.run('shell', 'am', 'force-stop', PACKAGE)
        self.run('shell', 'am', 'start', '-n', f'{PACKAGE}/{PACKAGE}.MainActivity')
        time.sleep(1)
        new = self.run('shell', 'pidof', PACKAGE).strip()
        assert old != new, (old, new)
        return {'oldPid': old, 'newPid': new}


class Emulator:
    def __init__(self):
        config = json.loads((ROOT / 'firebase.json').read_text())
        self.port = config['emulators']['firestore']['port']
        self.base = f'http://127.0.0.1:{self.port}'
        self.documents = f'/v1/projects/{PROJECT}/databases/(default)/documents'
        self.original_rules = (ROOT / config['firestore']['rules']).read_text()

    def request(self, path, body=None, method=None):
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.base + path, data=data, method=method,
                                         headers={'Content-Type': 'application/json',
                                                  'Authorization': 'Bearer owner'})
        # Avoid proxy settings: all verification requests go to this loopback emulator.
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request, timeout=20) as response:
            return json.load(response)

    @staticmethod
    def decode(value):
        if 'mapValue' in value:
            return {k: Emulator.decode(v) for k, v in value['mapValue'].get('fields', {}).items()}
        if 'arrayValue' in value:
            return [Emulator.decode(v) for v in value['arrayValue'].get('values', [])]
        return next(iter(value.values()))

    def get(self, path):
        raw = self.request(self.documents + '/' + path)
        return {'id': raw['name'].split('/')[-1],
                **{k: self.decode(v) for k, v in raw['fields'].items()}}

    def query(self, collection, field, value):
        results = self.request(self.documents + ':runQuery', {'structuredQuery': {
            'from': [{'collectionId': collection}],
            'where': {'fieldFilter': {'field': {'fieldPath': field}, 'op': 'EQUAL',
                                       'value': {'stringValue': value}}}}})
        return [{'id': row['document']['name'].split('/')[-1],
                 **{k: self.decode(v) for k, v in row['document']['fields'].items()}}
                for row in results if 'document' in row]

    def patch(self, path, field, value):
        return self.request(self.documents + '/' + path + '?updateMask.fieldPaths=' + field,
                            {'fields': {field: {'stringValue': value}}}, method='PATCH')

    def rules(self, content):
        return self.request(f'/emulator/v1/projects/{PROJECT}:securityRules',
                            {'rules': {'files': [{'content': content}]}}, method='PUT')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default=os.environ.get('ADB', 'adb'))
    parser.add_argument('--serial', default='373c972d')
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--inspect', action='store_true')
    parser.add_argument('--tap')
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    phone = Phone(args.adb, args.serial, args.artifacts)
    if args.tap:
        phone.tap(args.tap)
    if args.inspect or args.tap:
        print(json.dumps(phone.inspect(), indent=2))
        return
    emulator = Emulator()
    checks, server = [], {}
    stamp = str(int(time.time()))
    password = 'AndroidPhase2Pass123'
    email_a = f'android-a-{stamp}@example.com'
    email_b = f'android-b-{stamp}@example.com'
    name_a, name_b = f'Android Store A {stamp}', f'Android Store B {stamp}'
    offer_a, offer_b = f'Android Offer A {stamp}', f'Android Offer B {stamp}'
    updated_a, retried_a = f'Android Updated A {stamp}', f'Android Retried A {stamp}'

    def passed(check):
        checks.append(check)
        print('PASS: ' + check, flush=True)

    def register(email, name, already_open=False):
        if not already_open:
            phone.wait('Local development')
            phone.tap('I want to sell excess stock')
        phone.wait('Vendor Registration')
        for _ in range(5):
            phone.scroll(up=True)
        for label, value in [('Store / Business Name', name),
                             ('Phone Number', '9876543210'),
                             ('Business Address', 'Android verification address'),
                             ('Business Description', 'Registered on the physical phone'),
                             ('Email Address', email), ('Password', password),
                             ('Confirm Password', password)]:
            phone.fill(label, value)
        phone.tap('Submit Vendor Registration', seek=True)
        phone.wait('APPROVAL PENDING')
        users = emulator.query('users', 'email', email)
        assert len(users) == 1, users
        user = users[0]
        assert user['role'] == 'vendor' and user['approvalStatus'] == 'pending', user
        assert emulator.get('vendors/' + user['id'])['name'] == name
        return user['id']

    def sign_in(email, name):
        phone.wait('Local development')
        phone.tap('Sign In')
        phone.wait('Welcome Back')
        phone.fill('Email Address', email)
        phone.fill('Password', password)
        phone.tap('Sign In', seek=True)
        phone.wait(name)
        phone.wait('APPROVED')

    def logout():
        phone.tap('Sign Out')
        phone.wait('Local development')
        phone.absent(offer_a)
        phone.absent(offer_b)

    def post_offer(uid, title):
        phone.tap('Post Clearance Offer')
        phone.wait('Offer Title')
        for label, value in [('Offer Title', title),
                             ('Offer Description', 'Persisted from the Android phone'),
                             ('Original Price', '100'), ('Clearance Price', '50')]:
            phone.fill(label, value)
        phone.tap('Publish Clearance Offer', seek=True)
        phone.wait('Your offers')
        phone.wait(title)
        rows = emulator.query('offers', 'vendorId', uid)
        assert len(rows) == 1 and rows[0]['title'] == title, rows
        assert float(rows[0]['newPrice']) == 50 and rows[0]['status'] == 'active'
        return rows[0]['id']

    rules_changed = False
    result = {'serial': args.serial, 'projectId': PROJECT, 'checks': checks,
              'accounts': {'emailA': email_a, 'emailB': email_b}, 'restarts': [], 'server': server}
    try:
        result['restarts'].append(phone.restart())
        phone.wait_any(['Local development', 'Your offers'])
        # Always confirm the visible application mode before creating accounts.
        initial = phone.nodes()
        already_open = any('Vendor Registration' in phone.label(n) for n in initial)
        if already_open:
            phone.tap('Back')
        elif not any('Local development' in phone.label(n) for n in initial):
            phone.tap('Sign Out')
        phone.wait('Local development')
        phone.absent('Demo mode')
        a = register(email_a, name_a)
        result['accounts']['uidA'] = a
        phone.capture('02-a-pending')
        passed('Phone registration creates pending user/store documents, independently read through Firestore REST')
        result['restarts'].append(phone.restart())
        phone.wait(name_a)
        phone.wait('APPROVAL PENDING')
        phone.capture('03-a-pending-restored')
        passed('Force-stop and reopen restores the same pending vendor without login')

        emulator.patch('users/' + a, 'approvalStatus', 'approved')
        phone.wait('APPROVED')
        phone.wait('Post Clearance Offer')
        phone.capture('04-a-live-approved')
        emulator.patch('users/' + a, 'approvalStatus', 'suspended')
        phone.wait('APPROVAL REVOKED / REJECTED')
        locked = phone.wait('Approval required')
        assert locked['enabled'] == 'false', locked
        phone.capture('05-a-live-revoked')
        emulator.patch('users/' + a, 'approvalStatus', 'approved')
        phone.wait('APPROVED')
        passed('Approval and revocation update the active phone session and publishing control')

        phone.tap('Business profile')
        phone.wait('Vendor Profile')
        phone.tap('Edit Profile')
        phone.fill('Store name', updated_a, field_index=0)
        phone.tap('Save profile', seek=True)
        phone.wait('Edit Profile')
        phone.wait(updated_a)
        assert emulator.get('users/' + a)['displayName'] == updated_a
        assert emulator.get('vendors/' + a)['name'] == updated_a
        phone.capture('06-a-profile-saved')
        phone.tap('Back')
        id_a = post_offer(a, offer_a)
        result['offerA'] = id_a
        phone.capture('07-a-offer-saved')
        result['restarts'].append(phone.restart())
        phone.wait(updated_a)
        phone.wait(offer_a)
        phone.capture('08-a-data-restored')
        server['aBeforeFailure'] = {'user': emulator.get('users/' + a),
                                   'vendor': emulator.get('vendors/' + a),
                                   'offer': emulator.get('offers/' + id_a)}
        passed('Profile and offer saved through phone UI survive a process restart and uncached independent REST reads')

        phone.tap('Business profile')
        phone.wait('Vendor Profile')
        phone.tap('Edit Profile')
        phone.fill('Store name', retried_a, field_index=0)
        denied = emulator.original_rules.replace('allow update: if isOwner(uid)',
            f"allow update: if request.resource.data.displayName != '{retried_a}' && isOwner(uid)", 1)
        assert denied != emulator.original_rules
        rules_changed = True
        emulator.rules(denied)
        phone.tap('Save profile', seek=True)
        phone.wait('The server rejected this operation')
        phone.absent('Vendor profile saved.')
        phone.wait(retried_a)
        phone.capture('09-a-save-denied-input-retained')
        assert emulator.get('users/' + a) == server['aBeforeFailure']['user']
        assert emulator.get('vendors/' + a) == server['aBeforeFailure']['vendor']
        emulator.rules(emulator.original_rules)
        rules_changed = False
        phone.tap('Save profile', seek=True)
        phone.wait(retried_a)
        phone.wait('Edit Profile')  # Returned to view mode only after confirmation.
        assert emulator.get('users/' + a)['displayName'] == retried_a
        assert emulator.get('vendors/' + a)['name'] == retried_a
        phone.capture('10-a-retry-confirmed')
        result['restarts'].append(phone.restart())
        phone.wait(retried_a)
        phone.wait(offer_a)
        passed('A real server-denied atomic save shows an error, retains input, changes neither document, and retries successfully')

        logout()
        b = register(email_b, name_b)
        result['accounts']['uidB'] = b
        phone.absent(offer_a)
        emulator.patch('users/' + b, 'approvalStatus', 'approved')
        phone.wait('APPROVED')
        id_b = post_offer(b, offer_b)
        result['offerB'] = id_b
        # Keep a private draft as an isolation fixture, after publication via UI.
        emulator.patch('offers/' + id_b, 'status', 'draft')
        phone.wait('draft')
        phone.absent(offer_a)
        phone.capture('11-b-only-private-offer')
        result['restarts'].append(phone.restart())
        phone.wait(name_b)
        phone.wait(offer_b)
        phone.absent(offer_a)
        logout()
        sign_in(email_a, retried_a)
        phone.wait(offer_a)
        phone.absent(offer_b)
        phone.capture('12-switched-back-a-only')
        result['restarts'].append(phone.restart())
        phone.wait(retried_a)
        phone.wait(offer_a)
        phone.absent(offer_b)
        logout()
        sign_in(email_b, name_b)
        phone.wait(offer_b)
        phone.absent(offer_a)
        phone.capture('13-switched-back-b-only')
        passed('A to B to A to B sign-ins clear previous account state and isolate each persisted dashboard, including a private draft')
        server['aFinal'] = {'user': emulator.get('users/' + a), 'vendor': emulator.get('vendors/' + a),
                            'offers': emulator.query('offers', 'vendorId', a)}
        server['bFinal'] = {'user': emulator.get('users/' + b), 'vendor': emulator.get('vendors/' + b),
                            'offers': emulator.query('offers', 'vendorId', b)}
        assert [o['id'] for o in server['aFinal']['offers']] == [id_a]
        assert [o['id'] for o in server['bFinal']['offers']] == [id_b]
        result['result'] = 'PASS'
    except Exception as error:
        result['result'] = 'FAIL'
        result['error'] = repr(error)
        phone.capture('failure')
        raise
    finally:
        if rules_changed:
            emulator.rules(emulator.original_rules)
        (args.artifacts / 'result.json').write_text(json.dumps(result, indent=2))
        (args.artifacts / 'adb-commands.json').write_text(json.dumps(phone.commands, indent=2))
        print(json.dumps({k: v for k, v in result.items() if k != 'server'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
