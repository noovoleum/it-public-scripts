"""Offline check of the M365 -> Snipe-IT license sync matching and seat planning."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('sync', Path(__file__).with_name('sync-m365-licenses-snipeit.py'))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

snipe = [
    {'id': 1, 'username': 'rpw', 'email': 'raisal.wardana@noovoleum.com', 'first_name': 'Raisal', 'last_name': 'Wardana'},
    {'id': 2, 'username': 'abidin.gama', 'email': None, 'first_name': 'Abidin', 'last_name': 'Gama'},
    {'id': 3, 'username': 'faris.arya.permana', 'email': None, 'first_name': 'Faris Arya', 'last_name': 'Permana'},
    {'id': 4, 'username': 'budi.a', 'email': None, 'first_name': 'Budi', 'last_name': 'Santoso'},
    {'id': 5, 'username': 'budi.b', 'email': None, 'first_name': 'Budi', 'last_name': 'Santoso'},
]
entra = [
    {'id': 'a', 'userPrincipalName': 'Raisal.Wardana@noovoleum.com', 'displayName': 'Raisal Pradipta Wardana'},  # email
    {'id': 'b', 'userPrincipalName': 'abidin.gama@noovoleum.com', 'displayName': 'Abidin G'},  # username
    {'id': 'c', 'userPrincipalName': 'faris.permana@noovoleum.com', 'displayName': 'Faris  Arya Permana'},  # unique name
    {'id': 'd', 'userPrincipalName': 'budi@noovoleum.com', 'displayName': 'Budi Santoso'},  # ambiguous name
    {'id': 'e', 'userPrincipalName': 'shared@noovoleum.com', 'displayName': 'Shared Mailbox'},  # absent
]
matched, unmatched = sync.match_users(entra, snipe)
assert matched == {'a': 1, 'b': 2, 'c': 3}, matched
assert [u['id'] for u in unmatched] == ['d', 'e']

seats = [
    {'id': 10, 'assigned_user': {'id': 1}},  # keep
    {'id': 11, 'assigned_user': {'id': 1}},  # duplicate -> check in
    {'id': 12, 'assigned_user': {'id': 9}},  # lost the SKU in M365 -> check in
    {'id': 13, 'assigned_asset': {'id': 7}},  # asset seat, untouched but counted
    {'id': 14},
]
checkin, count, checkout = sync.plan_seats(seats, {1, 2, 3}, units=2)
assert checkin == [11, 12], checkin
assert checkout == [2, 3], checkout
assert count == 4, count  # 3 users + 1 asset seat beat the 2 purchased units
assert sync.plan_seats([], set(), 0) == ([], 1, [])  # Snipe needs >= 1 seat
print('ok')
