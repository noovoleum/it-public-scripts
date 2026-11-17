#!/usr/bin/env python3
"""Mirror Microsoft 365 license assignments into Snipe-IT licenses.

One Snipe-IT license per paid M365 SKU (bound by skuId in `order_number`), seats =
purchased units, one seat checked out to each Snipe-IT user holding that SKU in Entra.
Microsoft is the source of truth: seats held by users who no longer have the SKU are
checked in. Seats checked out to assets and Snipe users are never created or deleted.

Dry run by default; pass --apply to write.

Env:
  SNIPEIT_TOKEN                     Snipe-IT API token (required)
  SNIPEIT_URL                       default https://it.noovoleum.site
  CF_ACCESS_CLIENT_ID/_SECRET       Cloudflare Access service token, if the URL is gated
  GRAPH_TOKEN                       Graph token with Organization.Read.All + User.Read.All;
                                    unset = taken from a signed-in CLI for Microsoft 365 (`m365`)
"""
import argparse, json, os, re, subprocess, sys, time, unicodedata, urllib.error, urllib.parse, urllib.request

GRAPH = 'https://graph.microsoft.com/v1.0/'
# Graph only returns part numbers; names for the ones we buy, part number otherwise.
FRIENDLY = {
    'O365_BUSINESS_ESSENTIALS': 'Microsoft 365 Business Basic',
    'O365_BUSINESS_PREMIUM': 'Microsoft 365 Business Standard',
    'SPB': 'Microsoft 365 Business Premium',
    'EXCHANGESTANDARD': 'Exchange Online (Plan 1)',
}
FREE_UNITS = 10000  # ponytail: free/viral SKUs (Flow Free, Power BI Standard, ...) show 10k+ units; use --sku to override.


def http(method, url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    for attempt in range(6):
        req = urllib.request.Request(url, data, {**headers, 'Content-Type': 'application/json'}, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == 5:
                raise SystemExit(f'{method} {url}: HTTP {e.code} {e.read()[:300]!r}')
            time.sleep(int(e.headers.get('Retry-After') or 5 * (attempt + 1)))


class Snipe:
    def __init__(self, url, token, cf_id, cf_secret):
        self.base = url.rstrip('/') + '/api/v1/'
        self.h = {'Authorization': f'Bearer {token}', 'Accept': 'application/json', 'User-Agent': 'noov-m365-license-sync'}
        if cf_id:
            self.h |= {'CF-Access-Client-Id': cf_id, 'CF-Access-Client-Secret': cf_secret}

    def call(self, method, path, body=None):
        r = http(method, self.base + path, self.h, body)
        if method != 'GET':
            time.sleep(1)  # Snipe throttles writes hard
        if r.get('status') == 'error':  # Snipe reports errors as HTTP 200
            raise SystemExit(f'{method} {path}: {r.get("messages")}')
        return r

    def all(self, path, **q):
        rows, offset = [], 0
        while True:
            r = self.call('GET', f'{path}?{urllib.parse.urlencode({**q, "limit": 500, "offset": offset})}')
            rows += r['rows']
            offset += len(r['rows'])
            if not r['rows'] or offset >= r['total']:
                return rows

    def find_or_create(self, path, name, **extra):
        hit = [r for r in self.all(path, search=name) if r['name'].lower() == name.lower()]
        return hit[0]['id'] if hit else self.call('POST', path, {'name': name, **extra})['payload']['id']


def graph_all(url, token):
    h, out = {'Authorization': f'Bearer {token}'}, []
    while url:
        if not url.startswith(GRAPH):
            raise SystemExit(f'refusing unexpected Graph nextLink {url}')
        r = http('GET', url, h)
        out += r['value']
        url = r.get('@odata.nextLink')
    if len({x['id'] if 'id' in x else x['skuId'] for x in out}) != len(out):
        raise SystemExit('duplicate ids in Graph snapshot; refusing to sync')
    return out


def norm(s):
    s = unicodedata.normalize('NFKD', s or '').encode('ascii', 'ignore').decode().lower()
    return ' '.join(re.sub(r'\(.*?\)|[^a-z ]', ' ', s).split())


def match_users(entra_users, snipe_users):
    """Entra id -> Snipe user id via email, then UPN local part = username, then unique full name."""
    by_email = {u['email'].lower(): u['id'] for u in snipe_users if u.get('email')}
    by_username = {u['username'].lower(): u['id'] for u in snipe_users}
    by_name = {}
    for u in snipe_users:
        by_name.setdefault(norm(f"{u.get('first_name') or ''} {u.get('last_name') or ''}"), []).append(u['id'])
    matched, unmatched = {}, []
    for e in entra_users:
        upn = e['userPrincipalName'].lower()
        names = by_name.get(norm(e.get('displayName')), [])
        sid = (by_email.get(upn) or by_email.get((e.get('mail') or '').lower())
               or by_username.get(upn.split('@')[0]) or (names[0] if len(names) == 1 else None))
        (matched.__setitem__(e['id'], sid) if sid else unmatched.append(e))
    return matched, unmatched


def plan_seats(seats, want_user_ids, units):
    """Return (checkin seat ids, seat count to set, user ids to check out)."""
    held = {}
    for s in seats:
        if s.get('assigned_user'):
            held.setdefault(s['assigned_user']['id'], []).append(s['id'])
    checkin = [sid for uid, sids in held.items() for sid in (sids if uid not in want_user_ids else sids[1:])]
    checkout = sorted(want_user_ids - held.keys())
    on_assets = sum(1 for s in seats if s.get('assigned_asset'))
    return checkin, max(units, len(want_user_ids) + on_assets, 1), checkout


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--apply', action='store_true', help='write changes (default: dry run)')
    ap.add_argument('--sku', action='append', help='skuPartNumber to sync (repeatable; default: all paid SKUs)')
    a = ap.parse_args()

    gtoken = os.environ.get('GRAPH_TOKEN') or subprocess.run(
        ['m365', 'util', 'accesstoken', 'get', '--resource', 'https://graph.microsoft.com', '--output', 'text'],
        capture_output=True, text=True, check=True).stdout.strip()
    skus = [s for s in graph_all(GRAPH + 'subscribedSkus', gtoken)
            if (s['skuPartNumber'] in a.sku if a.sku else 0 < s['prepaidUnits']['enabled'] < FREE_UNITS)]
    users = graph_all(GRAPH + 'users?$top=999&$select=id,userPrincipalName,mail,displayName,accountEnabled,assignedLicenses', gtoken)

    sn = Snipe(os.environ.get('SNIPEIT_URL', 'https://it.noovoleum.site'), os.environ['SNIPEIT_TOKEN'],
               os.environ.get('CF_ACCESS_CLIENT_ID'), os.environ.get('CF_ACCESS_CLIENT_SECRET'))
    licensed = [u for u in users if any(l['skuId'] in {s['skuId'] for s in skus} for l in u['assignedLicenses'])]
    matched, unmatched = match_users(licensed, sn.all('users'))
    cat = mfr = None

    print(f"{'APPLY' if a.apply else 'DRY RUN'}: {len(skus)} SKUs, {len(licensed)} licensed users, {len(unmatched)} not in Snipe-IT")
    for s in skus:
        name = FRIENDLY.get(s['skuPartNumber'], s['skuPartNumber'])
        units = s['prepaidUnits']['enabled']
        want = {matched[u['id']] for u in licensed if u['id'] in matched and any(l['skuId'] == s['skuId'] for l in u['assignedLicenses'])}
        lic = next(iter(sn.all('licenses', order_number=s['skuId'])), None)
        seats = sn.all(f"licenses/{lic['id']}/seats") if lic else []
        checkin, count, checkout = plan_seats(seats, want, units)
        print(f"  {name}: {units} bought, {s['consumedUnits']} assigned in M365, {len(want)} matched"
              f"{'' if lic else ' [new license]'}; check in {len(checkin)}, check out {len(checkout)}, seats -> {count}")
        if not a.apply:
            continue
        if not lic:
            cat = cat or sn.find_or_create('categories', 'Microsoft 365', category_type='license')
            mfr = mfr or sn.find_or_create('manufacturers', 'Microsoft')
            lic = sn.call('POST', 'licenses', {'name': name, 'seats': count, 'category_id': cat, 'manufacturer_id': mfr,
                                               'order_number': s['skuId'], 'reassignable': True, 'maintained': True,
                                               'notes': f"Synced from Microsoft 365 ({s['skuPartNumber']})."})['payload']
        for sid in checkin:
            sn.call('PATCH', f"licenses/{lic['id']}/seats/{sid}", {'assigned_to': None, 'notes': 'M365 license removed'})
        if count != lic['seats']:
            sn.call('PATCH', f"licenses/{lic['id']}", {'seats': count})
        free = [x['id'] for x in sn.all(f"licenses/{lic['id']}/seats") if not x.get('assigned_user') and not x.get('assigned_asset')]
        for uid, sid in zip(checkout, free, strict=False):
            sn.call('PATCH', f"licenses/{lic['id']}/seats/{sid}", {'assigned_to': uid, 'notes': 'M365 license assigned'})
    for u in sorted(unmatched, key=lambda u: u['userPrincipalName']):
        print(f"  not in Snipe-IT: {u['userPrincipalName']}{'' if u['accountEnabled'] else ' (sign-in blocked)'}")


if __name__ == '__main__':
    sys.exit(main())
