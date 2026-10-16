import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:budget/struct/backupEncryption.dart';
import 'package:budget/struct/fullBackup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final db = Uint8List.fromList(List.generate(50000, (i) => i % 251));

  test('round trip with attachments', () async {
    final dir = await Directory.systemTemp.createTemp('enc');
    final att = File('${dir.path}/recibo.pdf')..writeAsBytesSync([1, 2, 3, 4]);
    final zip = buildZipBackupBytes(db, [att]);
    final enc = await encryptBackupBytes(zip, 'senha-forte-123');
    expect(hasEncryptedBackupHeader(enc), true);
    expect(String.fromCharCodes(enc.sublist(0, 9)), 'CASHEWENC');
    // plaintext must not appear in the file
    expect(String.fromCharCodes(enc).contains('db.sqlite'), false);
    final dec = await decryptBackupBytes(enc, 'senha-forte-123');
    expect(dec, zip);
    final contents = await readZipBackupBytes(dec, restoreAttachments: false);
    expect(contents.databaseBytes, db);
    await dir.delete(recursive: true);
  });

  test('two backups with the same password differ (random salt/nonce)', () async {
    final a = await encryptBackupBytes(db, 'senha-forte-123');
    final b = await encryptBackupBytes(db, 'senha-forte-123');
    expect(a, isNot(equals(b)));
  });

  test('wrong password', () async {
    final enc = await encryptBackupBytes(db, 'senha-forte-123');
    expect(() => decryptBackupBytes(enc, 'senha-errada-123'),
        throwsA(isA<WrongBackupPasswordException>()));
  });

  test('tampered ciphertext / header fail', () async {
    final enc = await encryptBackupBytes(db, 'senha-forte-123');
    final t1 = Uint8List.fromList(enc)..[100] ^= 1;
    expect(() => decryptBackupBytes(t1, 'senha-forte-123'),
        throwsA(isA<WrongBackupPasswordException>()));
    final t2 = Uint8List.fromList(enc)..[20] ^= 1; // salt (header)
    expect(() => decryptBackupBytes(t2, 'senha-forte-123'),
        throwsA(isA<WrongBackupPasswordException>()));
    final t3 = Uint8List.fromList(enc)..[enc.length - 1] ^= 1; // tag
    expect(() => decryptBackupBytes(t3, 'senha-forte-123'),
        throwsA(isA<WrongBackupPasswordException>()));
  });

  test('crafted header with huge memory is refused', () async {
    final enc = await encryptBackupBytes(db, 'senha-forte-123');
    final t = Uint8List.fromList(enc);
    ByteData.sublistView(t).setUint32(10, 0xFFFFFFFF);
    expect(() => decryptBackupBytes(t, 'senha-forte-123'), throwsA(anything));
  });

  test('not an encrypted file', () async {
    expect(hasEncryptedBackupHeader(db), false);
    expect(() => decryptBackupBytes(db, 'x'), throwsA(anything));
    expect(isEncryptedBackup('cashew-backup-1.enc'), true);
    expect(isEncryptedBackup('cashew-backup-1.zip'), false);
  });

  group('recovery key', () {
    test('format: 52 base32 chars in groups of 4, parse round trip', () async {
      final k = await generateRecoveryKey();
      expect(RegExp(r'^([A-Z2-7]{4}-){12}[A-Z2-7]{4}$').hasMatch(k.text), true);
      final seed = parseRecoveryKey(k.text)!;
      expect(formatRecoveryKey(seed), k.text);
      // tolerant: lower case, spaces instead of dashes
      expect(parseRecoveryKey(k.text.toLowerCase().replaceAll('-', ' ')), seed);
      expect(parseRecoveryKey('ABCD-EFGH'), null);
    });

    test('backup opens with password AND with the recovery key', () async {
      final k = await generateRecoveryKey();
      final pub = base64.decode(k.publicKeyBase64);
      final enc = await encryptBackupBytes(db, 'senha-forte-123',
          recoveryPublicKey: pub);
      expect(backupHasRecoveryKey(enc), true);
      expect(await decryptBackupBytes(enc, 'senha-forte-123'), db);
      expect(await decryptBackupWithRecoveryKey(enc, parseRecoveryKey(k.text)!), db);
      // typed in the restore dialog, sloppy formatting
      expect(await decryptBackupWithPasswordOrRecoveryKey(
          enc, k.text.toLowerCase().replaceAll('-', ' ')), db);
      expect(await decryptBackupWithPasswordOrRecoveryKey(enc, 'senha-forte-123'), db);
    });

    test('another recovery key does not open it', () async {
      final k = await generateRecoveryKey();
      final other = await generateRecoveryKey();
      final enc = await encryptBackupBytes(db, 'senha-forte-123',
          recoveryPublicKey: base64.decode(k.publicKeyBase64));
      expect(() => decryptBackupWithRecoveryKey(enc, parseRecoveryKey(other.text)!),
          throwsA(isA<WrongBackupPasswordException>()));
    });

    test('backup without recovery block: recovery key refused, password ok', () async {
      final k = await generateRecoveryKey();
      final enc = await encryptBackupBytes(db, 'senha-forte-123');
      expect(backupHasRecoveryKey(enc), false);
      expect(() => decryptBackupWithRecoveryKey(enc, parseRecoveryKey(k.text)!),
          throwsA(isA<WrongBackupPasswordException>()));
    });

    test('tampering with the recovery block is detected', () async {
      final k = await generateRecoveryKey();
      final enc = await encryptBackupBytes(db, 'senha-forte-123',
          recoveryPublicKey: base64.decode(k.publicKeyBase64));
      final t = Uint8List.fromList(enc)..[35 + 60 + 1 + 5] ^= 1; // ephemeral key
      expect(() => decryptBackupWithRecoveryKey(t, parseRecoveryKey(k.text)!),
          throwsA(isA<WrongBackupPasswordException>()));
      // and the password path also refuses the modified file
      expect(() => decryptBackupBytes(t, 'senha-forte-123'),
          throwsA(isA<WrongBackupPasswordException>()));
    });
  });
}
