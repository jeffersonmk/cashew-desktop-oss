#!/usr/bin/env python3
"""Decrypt a Cashew Desktop encrypted backup (.enc) without the app.

Usage:
    uv run --with argon2-cffi --with cryptography decrypt-backup.py BACKUP.enc [OUT.zip]
    (or: pip install argon2-cffi cryptography; python3 decrypt-backup.py ...)

Type the backup password or the recovery key when asked (not shown). The
result is the normal backup .zip: db.sqlite + attachments/. Format: see
budget/lib/struct/backupEncryption.dart.
"""
import base64
import getpass
import re
import struct
import sys

from argon2.low_level import Type, hash_secret_raw
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.x25519 import (
    X25519PrivateKey, X25519PublicKey)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

MAGIC = b"CASHEWENC"
WRAP = 12 + 32 + 16
RECOVERY_INFO = b"cashew-desktop backup recovery v1"


class WrongSecret(Exception):
    pass


def parse(data):
    if data[:9] != MAGIC:
        raise ValueError("not a Cashew Desktop encrypted backup")
    if data[9] != 1:
        raise ValueError("unsupported format version %d" % data[9])
    memory, iterations = struct.unpack(">II", data[10:18])
    parallelism = data[18]
    salt = data[19:35]
    pos = 35
    password_wrap = data[pos:pos + WRAP]
    pos += WRAP
    has_recovery = data[pos]
    pos += 1
    ephemeral = recovery_wrap = None
    if has_recovery == 1:
        ephemeral = data[pos:pos + 32]
        recovery_wrap = data[pos + 32:pos + 32 + WRAP]
        pos += 32 + WRAP
    nonce = data[pos:pos + 12]
    pos += 12
    return dict(memory=memory, iterations=iterations, parallelism=parallelism,
                salt=salt, password_wrap=password_wrap, ephemeral=ephemeral,
                recovery_wrap=recovery_wrap, nonce=nonce, header=data[:pos])


def unwrap(wrapped, key):
    try:
        return AESGCM(key).decrypt(wrapped[:12], wrapped[12:], None)
    except InvalidTag:
        raise WrongSecret()


def recovery_seed(text):
    clean = re.sub(r"[\s-]", "", text.upper())
    clean = clean.replace("0", "O").replace("1", "I").replace("8", "B")
    if len(clean) != 52 or not re.fullmatch(r"[A-Z2-7]+", clean):
        return None
    return base64.b32decode(clean + "====")[:32]


def data_key_from_recovery(p, seed):
    if p["ephemeral"] is None:
        raise WrongSecret()
    private = X25519PrivateKey.from_private_bytes(seed)
    public = private.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    shared = private.exchange(X25519PublicKey.from_public_bytes(p["ephemeral"]))
    key = HKDF(algorithm=hashes.SHA256(), length=32,
               salt=p["ephemeral"] + public, info=RECOVERY_INFO).derive(shared)
    return unwrap(p["recovery_wrap"], key)


def data_key_from_password(p, password):
    key = hash_secret_raw(password.encode(), p["salt"],
                          time_cost=p["iterations"], memory_cost=p["memory"],
                          parallelism=p["parallelism"], hash_len=32,
                          type=Type.ID)
    return unwrap(p["password_wrap"], key)


def decrypt(data, secret):
    p = parse(data)
    data_key = None
    seed = recovery_seed(secret)
    if seed is not None:
        try:
            data_key = data_key_from_recovery(p, seed)
        except WrongSecret:
            pass
    if data_key is None:
        data_key = data_key_from_password(p, secret)
    body = data[len(p["header"]):]
    try:
        return AESGCM(data_key).decrypt(p["nonce"], body, p["header"])
    except InvalidTag:
        raise WrongSecret()


def main():
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    source = sys.argv[1]
    target = sys.argv[2] if len(sys.argv) == 3 else (
        source[:-4] if source.endswith(".enc") else source) + ".zip"
    data = open(source, "rb").read()
    secret = getpass.getpass("Backup password or recovery key: ")
    try:
        plain = decrypt(data, secret)
    except WrongSecret:
        print("Wrong password or recovery key (or the file is damaged).")
        return 1
    with open(target, "xb") as out:
        out.write(plain)
    print("Saved", target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
