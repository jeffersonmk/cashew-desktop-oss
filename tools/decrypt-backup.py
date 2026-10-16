#!/usr/bin/env python3
"""Decrypt a Cashew Desktop encrypted backup (.enc) without the app.

Usage:
    uv run --with argon2-cffi --with cryptography decrypt-backup.py BACKUP.enc [OUT.zip]
    (or: pip install argon2-cffi cryptography; python3 decrypt-backup.py ...)

The password is asked in the terminal (not shown). The result is the normal
backup .zip: db.sqlite + attachments/. Format: see
budget/lib/struct/backupEncryption.dart.
"""
import getpass
import struct
import sys

from argon2.low_level import Type, hash_secret_raw
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAGIC = b"CASHEWENC"
HEADER = 47


def decrypt(data: bytes, password: str) -> bytes:
    if len(data) < HEADER + 16 or data[:9] != MAGIC:
        raise ValueError("not a Cashew Desktop encrypted backup")
    if data[9] != 1:
        raise ValueError("unsupported format version %d" % data[9])
    memory, iterations = struct.unpack(">II", data[10:18])
    parallelism = data[18]
    salt, nonce = data[19:35], data[35:47]
    key = hash_secret_raw(password.encode(), salt, time_cost=iterations,
                          memory_cost=memory, parallelism=parallelism,
                          hash_len=32, type=Type.ID)
    return AESGCM(key).decrypt(nonce, data[HEADER:], data[:HEADER])


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    source = sys.argv[1]
    target = sys.argv[2] if len(sys.argv) == 3 else (
        source[:-4] if source.endswith(".enc") else source) + ".zip"
    data = open(source, "rb").read()
    password = getpass.getpass("Backup password: ")
    try:
        plain = decrypt(data, password)
    except InvalidTag:
        print("Wrong password (or the file is damaged).")
        return 1
    with open(target, "xb") as out:
        out.write(plain)
    print("Saved", target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
