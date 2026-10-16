// Cashew Desktop: password-encrypted backups.
//
// An encrypted backup is the normal .zip backup (db.sqlite + attachments/)
// encrypted with AES-256-GCM. The key comes from the password through
// Argon2id, so guessing passwords is slow and expensive.
//
// File layout (".enc"):
//
//   "CASHEWENC"  magic, 9 bytes
//   1            format version, 1 byte
//   memory       Argon2id memory in KiB, uint32 big endian
//   iterations   Argon2id passes, uint32 big endian
//   parallelism  Argon2id lanes, 1 byte
//   salt         16 random bytes
//   nonce        12 random bytes
//   ciphertext   the zip
//   tag          16 bytes (GCM authentication)
//
// The header is authenticated too (used as associated data), so changing any
// byte of the file makes decryption fail instead of returning wrong data.
//
// The password is either kept in the system keyring (Secret Service:
// GNOME Keyring, KWallet...) so automatic backups keep working, or asked
// every time a backup is made or restored. Without the password a backup
// cannot be restored: there is no recovery.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:budget/struct/desktopIntegration.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:cryptography/cryptography.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

const String encryptedBackupExtension = ".enc";
const List<int> _magic = [67, 65, 83, 72, 69, 87, 69, 78, 67]; // CASHEWENC
const int _formatVersion = 1;
const int _headerLength = 9 + 1 + 4 + 4 + 1 + 16 + 12;
const int _tagLength = 16;
const int minimumPasswordLength = 8;

// RFC 9106 "second recommended option": 64 MiB, 3 passes.
const int _argonMemoryKiB = 65536;
const int _argonIterations = 3;
const int _argonParallelism = 1;

bool isEncryptedBackup(String path) =>
    path.toLowerCase().endsWith(encryptedBackupExtension);

bool hasEncryptedBackupHeader(Uint8List data) {
  if (data.length < _headerLength + _tagLength) return false;
  for (int i = 0; i < _magic.length; i++) {
    if (data[i] != _magic[i]) return false;
  }
  return true;
}

class WrongBackupPasswordException implements Exception {
  @override
  String toString() => "wrong-backup-password".tr();
}

Uint8List _randomBytes(int length) {
  Random random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

Future<SecretKey> _deriveKey(String password, List<int> salt, int memory,
    int iterations, int parallelism) {
  return Argon2id(
    memory: memory,
    iterations: iterations,
    parallelism: parallelism,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
}

Future<Uint8List> _encrypt(Uint8List plain, String password) async {
  Uint8List salt = _randomBytes(16);
  Uint8List nonce = _randomBytes(12);
  ByteData header = ByteData(_headerLength);
  for (int i = 0; i < _magic.length; i++) header.setUint8(i, _magic[i]);
  header.setUint8(9, _formatVersion);
  header.setUint32(10, _argonMemoryKiB);
  header.setUint32(14, _argonIterations);
  header.setUint8(18, _argonParallelism);
  Uint8List headerBytes = header.buffer.asUint8List();
  headerBytes.setRange(19, 35, salt);
  headerBytes.setRange(35, 47, nonce);

  SecretKey key = await _deriveKey(
      password, salt, _argonMemoryKiB, _argonIterations, _argonParallelism);
  SecretBox box = await AesGcm.with256bits().encrypt(
    plain,
    secretKey: key,
    nonce: nonce,
    aad: headerBytes,
  );
  BytesBuilder out = BytesBuilder(copy: false)
    ..add(headerBytes)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return out.takeBytes();
}

Future<Uint8List> _decrypt(Uint8List data, String password) async {
  if (!hasEncryptedBackupHeader(data)) {
    throw Exception("Not an encrypted Cashew Desktop backup");
  }
  ByteData header = ByteData.sublistView(data, 0, _headerLength);
  if (header.getUint8(9) != _formatVersion) {
    throw Exception("Unsupported encrypted backup version");
  }
  int memory = header.getUint32(10);
  int iterations = header.getUint32(14);
  int parallelism = header.getUint8(18);
  // Refuse absurd values from a damaged or crafted file (memory in KiB).
  if (memory < 8 || memory > 1048576 || iterations < 1 ||
      iterations > 64 || parallelism < 1 || parallelism > 16) {
    throw Exception("Invalid encrypted backup header");
  }
  Uint8List headerBytes = Uint8List.sublistView(data, 0, _headerLength);
  Uint8List salt = Uint8List.sublistView(data, 19, 35);
  Uint8List nonce = Uint8List.sublistView(data, 35, 47);
  Uint8List cipherText =
      Uint8List.sublistView(data, _headerLength, data.length - _tagLength);
  Uint8List tag = Uint8List.sublistView(data, data.length - _tagLength);
  SecretKey key =
      await _deriveKey(password, salt, memory, iterations, parallelism);
  try {
    List<int> plain = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
      secretKey: key,
      aad: headerBytes,
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    throw WrongBackupPasswordException();
  }
}

// Both run in a background isolate so the window keeps responding.
Future<Uint8List> encryptBackupBytes(Uint8List plain, String password) =>
    Isolate.run(() => _encrypt(plain, password));

Future<Uint8List> decryptBackupBytes(Uint8List data, String password) async {
  try {
    return await Isolate.run(() => _decrypt(data, password));
  } on RemoteError catch (e) {
    if (e.toString().contains("wrong-backup-password") ||
        e.toString().contains("WrongBackupPassword")) {
      throw WrongBackupPasswordException();
    }
    rethrow;
  }
}

// --- Settings --------------------------------------------------------------

bool get backupEncryptionEnabled => appStateSettings["encryptBackups"] == true;

// "keyring" (saved in the system keyring) or "ask" (typed every time).
bool get backupPasswordInKeyring =>
    appStateSettings["backupPasswordMode"] != "ask";

// --- System keyring ---------------------------------------------------------

Future<bool> keyringAvailable() async {
  if (!Platform.isLinux) return false;
  try {
    return await desktopChannel.invokeMethod<bool>("secretAvailable") == true;
  } catch (e) {
    return false;
  }
}

Future<bool> keyringStorePassword(String password) async {
  try {
    return await desktopChannel.invokeMethod<bool>("secretStore", password) ==
        true;
  } catch (e) {
    print("Keyring store failed: " + e.toString());
    return false;
  }
}

Future<String?> keyringLookupPassword() async {
  try {
    return await desktopChannel.invokeMethod<String>("secretLookup");
  } catch (e) {
    print("Keyring lookup failed: " + e.toString());
    return null;
  }
}

Future<void> keyringClearPassword() async {
  try {
    await desktopChannel.invokeMethod("secretClear");
  } catch (e) {
    print("Keyring clear failed: " + e.toString());
  }
}

// --- Password dialog --------------------------------------------------------

// Asks for a password. With [confirm] it is typed twice (new password).
// [validate] can check it before the dialog closes (e.g. try to decrypt) and
// return an error message to show.
Future<String?> askBackupPassword(
  BuildContext context, {
  required String title,
  String? description,
  bool confirm = false,
  Future<String?> Function(String password)? validate,
}) {
  return openPopupCustom<String>(
    context,
    title: title,
    child: _BackupPasswordForm(
      description: description,
      confirm: confirm,
      validate: validate,
    ),
  );
}

class _BackupPasswordForm extends StatefulWidget {
  const _BackupPasswordForm(
      {this.description, required this.confirm, this.validate});
  final String? description;
  final bool confirm;
  final Future<String?> Function(String password)? validate;

  @override
  State<_BackupPasswordForm> createState() => _BackupPasswordFormState();
}

class _BackupPasswordFormState extends State<_BackupPasswordForm> {
  String password = "";
  String repeated = "";
  String? error;
  bool busy = false;

  Future<void> submit() async {
    if (busy) return;
    if (widget.confirm && password.length < minimumPasswordLength) {
      setState(() => error = "backup-password-too-short"
          .tr(namedArgs: {"count": minimumPasswordLength.toString()}));
      return;
    }
    if (widget.confirm && password != repeated) {
      setState(() => error = "backup-passwords-do-not-match".tr());
      return;
    }
    if (password == "") return;
    if (widget.validate != null) {
      setState(() {
        busy = true;
        error = null;
      });
      String? message = await widget.validate!(password);
      if (!mounted) return;
      if (message != null) {
        setState(() {
          busy = false;
          error = message;
        });
        return;
      }
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.description != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 15),
            child: TextFont(
              text: widget.description!,
              fontSize: 15,
              maxLines: 10,
              textAlign: TextAlign.center,
            ),
          ),
        TextInput(
          labelText: "backup-password".tr(),
          obscureText: true,
          autoFocus: true,
          padding: EdgeInsetsDirectional.zero,
          onChanged: (value) => password = value,
          onSubmitted: (_) => submit(),
        ),
        if (widget.confirm) ...[
          SizedBox(height: 10),
          TextInput(
            labelText: "repeat-backup-password".tr(),
            obscureText: true,
            padding: EdgeInsetsDirectional.zero,
            onChanged: (value) => repeated = value,
            onSubmitted: (_) => submit(),
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 10),
            child: TextFont(
              text: error!,
              fontSize: 14,
              maxLines: 5,
              textAlign: TextAlign.center,
              textColor: Theme.of(context).colorScheme.error,
            ),
          ),
        SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: Button(
                label: "cancel".tr(),
                color: Theme.of(context).colorScheme.secondaryContainer,
                textColor: Theme.of(context).colorScheme.onSecondaryContainer,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Button(
                label: busy ? "..." : "ok".tr(),
                onTap: submit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- High level --------------------------------------------------------------

// Password to encrypt a new backup, or null if there is none (cancelled, or
// an automatic backup in "ask every time" mode).
Future<String?> passwordForNewBackup(BuildContext? context) async {
  if (backupPasswordInKeyring) {
    String? saved = await keyringLookupPassword();
    if (saved != null && saved != "") return saved;
  }
  if (context == null) return null;
  return await askBackupPassword(
    context,
    title: "backup-password".tr(),
    description: "encrypted-backup-ask-description".tr(),
  );
}

// Decrypts an encrypted backup file: tries the saved password first, then
// asks until it is right or the user cancels (null).
Future<Uint8List?> decryptBackupFileInteractive(
    BuildContext context, File file) async {
  Uint8List data = await file.readAsBytes();
  if (!hasEncryptedBackupHeader(data)) {
    throw Exception("Not an encrypted Cashew Desktop backup");
  }
  String? saved = await keyringLookupPassword();
  if (saved != null && saved != "") {
    try {
      return await decryptBackupBytes(data, saved);
    } on WrongBackupPasswordException {
      // Made with another password: ask.
    }
  }
  Uint8List? result;
  String? password = await askBackupPassword(
    context,
    title: "encrypted-backup".tr(),
    description: "encrypted-backup-restore-description".tr(),
    validate: (password) async {
      try {
        result = await decryptBackupBytes(data, password);
        return null;
      } on WrongBackupPasswordException {
        return "wrong-backup-password".tr();
      } catch (e) {
        return e.toString();
      }
    },
  );
  if (password == null) return null;
  return result;
}
