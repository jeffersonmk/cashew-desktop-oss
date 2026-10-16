// Cashew Desktop: password-encrypted backups, with an optional recovery key.
//
// An encrypted backup is the normal .zip backup (db.sqlite + attachments/)
// encrypted with AES-256-GCM under a random data key. That data key is then
// stored ("wrapped") in the file in up to two ways:
//
//   - with the password: key from Argon2id(password), slow on purpose so
//     guessing passwords is expensive;
//   - with the recovery key: an X25519 key pair. Only the public half is kept
//     by the app (in its settings), so backups can be made for the recovery
//     key without having it; the private half is the recovery key the user
//     writes down, and it is never stored.
//
// File layout (".enc", integers big endian):
//
//   "CASHEWENC"   magic, 9 bytes
//   1             format version
//   memory        Argon2id memory in KiB, uint32
//   iterations    Argon2id passes, uint32
//   parallelism   Argon2id lanes, 1 byte
//   salt          16 bytes
//   pw nonce      12 bytes      | data key encrypted with the
//   pw wrapped    32 + 16 bytes | password key (AES-256-GCM)
//   recovery      1 byte: 1 if the next block is present, else 0
//     ephemeral   32 bytes (X25519 public key)
//     rk nonce    12 bytes      | data key encrypted with
//     rk wrapped  32 + 16 bytes | HKDF(X25519 shared secret)
//   data nonce    12 bytes
//   ciphertext    the zip
//   tag           16 bytes
//
// The whole header is the associated data of the zip encryption, so changing
// any byte of the file makes decryption fail instead of returning wrong data.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:budget/functions.dart';
import 'package:budget/struct/desktopIntegration.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:cryptography/cryptography.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

const String encryptedBackupExtension = ".enc";
const List<int> _magic = [67, 65, 83, 72, 69, 87, 69, 78, 67]; // CASHEWENC
const int _formatVersion = 1;
const int _tagLength = 16;
const int _fixedStart = 9 + 1 + 4 + 4 + 1 + 16; // up to the salt
const int _wrapLength = 12 + 32 + 16; // nonce + wrapped key + tag
const int _recoveryBlockLength = 32 + _wrapLength;
const int minimumPasswordLength = 8;

// RFC 9106 "second recommended option": 64 MiB, 3 passes.
const int _argonMemoryKiB = 65536;
const int _argonIterations = 3;
const int _argonParallelism = 1;

final List<int> _recoveryInfo = utf8.encode("cashew-desktop backup recovery v1");

bool isEncryptedBackup(String path) =>
    path.toLowerCase().endsWith(encryptedBackupExtension);

bool hasEncryptedBackupHeader(Uint8List data) {
  if (data.length < _fixedStart + _wrapLength + 1 + 12 + _tagLength) {
    return false;
  }
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

Future<SecretKey> _passwordKey(String password, List<int> salt, int memory,
    int iterations, int parallelism) {
  return Argon2id(
    memory: memory,
    iterations: iterations,
    parallelism: parallelism,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
}

Future<SecretKey> _recoveryWrapKey(
    SecretKey shared, List<int> ephemeralPublic, List<int> recoveryPublic) {
  return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: shared,
    nonce: [...ephemeralPublic, ...recoveryPublic],
    info: _recoveryInfo,
  );
}

final AesGcm _aes = AesGcm.with256bits();

Future<Uint8List> _wrap(List<int> dataKey, SecretKey wrapKey) async {
  Uint8List nonce = _randomBytes(12);
  SecretBox box = await _aes.encrypt(dataKey, secretKey: wrapKey, nonce: nonce);
  return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
}

Future<List<int>?> _unwrap(Uint8List wrapped, SecretKey wrapKey) async {
  try {
    return await _aes.decrypt(
      SecretBox(Uint8List.sublistView(wrapped, 12, 44),
          nonce: Uint8List.sublistView(wrapped, 0, 12),
          mac: Mac(Uint8List.sublistView(wrapped, 44, 60))),
      secretKey: wrapKey,
    );
  } on SecretBoxAuthenticationError {
    return null;
  }
}

Future<Uint8List> _encrypt(
    Uint8List plain, String password, List<int>? recoveryPublic) async {
  Uint8List dataKey = _randomBytes(32);
  Uint8List salt = _randomBytes(16);
  BytesBuilder header = BytesBuilder();
  ByteData params = ByteData(9);
  params.setUint32(0, _argonMemoryKiB);
  params.setUint32(4, _argonIterations);
  params.setUint8(8, _argonParallelism);
  header
    ..add(_magic)
    ..addByte(_formatVersion)
    ..add(params.buffer.asUint8List())
    ..add(salt);
  SecretKey passwordKey = await _passwordKey(
      password, salt, _argonMemoryKiB, _argonIterations, _argonParallelism);
  header.add(await _wrap(dataKey, passwordKey));
  if (recoveryPublic != null && recoveryPublic.length == 32) {
    X25519 x25519 = X25519();
    SimpleKeyPair ephemeral = await x25519.newKeyPair();
    List<int> ephemeralPublic = (await ephemeral.extractPublicKey()).bytes;
    SecretKey shared = await x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(recoveryPublic, type: KeyPairType.x25519),
    );
    SecretKey wrapKey =
        await _recoveryWrapKey(shared, ephemeralPublic, recoveryPublic);
    header
      ..addByte(1)
      ..add(ephemeralPublic)
      ..add(await _wrap(dataKey, wrapKey));
  } else {
    header.addByte(0);
  }
  Uint8List dataNonce = _randomBytes(12);
  header.add(dataNonce);
  Uint8List headerBytes = header.takeBytes();
  SecretBox box = await _aes.encrypt(plain,
      secretKey: SecretKey(dataKey), nonce: dataNonce, aad: headerBytes);
  BytesBuilder out = BytesBuilder(copy: false)
    ..add(headerBytes)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return out.takeBytes();
}

class _Parsed {
  _Parsed(this.data);
  final Uint8List data;
  late int memory, iterations, parallelism;
  late Uint8List salt, passwordWrap, dataNonce, header;
  Uint8List? ephemeralPublic, recoveryWrap;
}

_Parsed _parse(Uint8List data) {
  if (!hasEncryptedBackupHeader(data)) {
    throw Exception("Not an encrypted Cashew Desktop backup");
  }
  if (data[9] != _formatVersion) {
    throw Exception("Unsupported encrypted backup version");
  }
  _Parsed parsed = _Parsed(data);
  ByteData view = ByteData.sublistView(data);
  parsed.memory = view.getUint32(10);
  parsed.iterations = view.getUint32(14);
  parsed.parallelism = view.getUint8(18);
  // Refuse absurd values from a damaged or crafted file (memory in KiB).
  if (parsed.memory < 8 || parsed.memory > 1048576 ||
      parsed.iterations < 1 || parsed.iterations > 64 ||
      parsed.parallelism < 1 || parsed.parallelism > 16) {
    throw Exception("Invalid encrypted backup header");
  }
  parsed.salt = Uint8List.sublistView(data, 19, 35);
  int offset = _fixedStart;
  parsed.passwordWrap =
      Uint8List.sublistView(data, offset, offset + _wrapLength);
  offset += _wrapLength;
  int hasRecovery = data[offset];
  offset += 1;
  if (hasRecovery == 1) {
    if (data.length < offset + _recoveryBlockLength + 12 + _tagLength) {
      throw Exception("Invalid encrypted backup header");
    }
    parsed.ephemeralPublic = Uint8List.sublistView(data, offset, offset + 32);
    parsed.recoveryWrap =
        Uint8List.sublistView(data, offset + 32, offset + _recoveryBlockLength);
    offset += _recoveryBlockLength;
  } else if (hasRecovery != 0) {
    throw Exception("Invalid encrypted backup header");
  }
  parsed.dataNonce = Uint8List.sublistView(data, offset, offset + 12);
  offset += 12;
  parsed.header = Uint8List.sublistView(data, 0, offset);
  return parsed;
}

Future<Uint8List> _decryptData(_Parsed parsed, List<int> dataKey) async {
  Uint8List data = parsed.data;
  try {
    List<int> plain = await _aes.decrypt(
      SecretBox(
          Uint8List.sublistView(
              data, parsed.header.length, data.length - _tagLength),
          nonce: parsed.dataNonce,
          mac: Mac(Uint8List.sublistView(data, data.length - _tagLength))),
      secretKey: SecretKey(dataKey),
      aad: parsed.header,
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    throw WrongBackupPasswordException();
  }
}

Future<Uint8List> _decryptWithPassword(Uint8List data, String password) async {
  _Parsed parsed = _parse(data);
  SecretKey key = await _passwordKey(password, parsed.salt, parsed.memory,
      parsed.iterations, parsed.parallelism);
  List<int>? dataKey = await _unwrap(parsed.passwordWrap, key);
  if (dataKey == null) throw WrongBackupPasswordException();
  return _decryptData(parsed, dataKey);
}

Future<Uint8List> _decryptWithRecoveryKey(
    Uint8List data, List<int> recoverySeed) async {
  _Parsed parsed = _parse(data);
  if (parsed.ephemeralPublic == null) throw WrongBackupPasswordException();
  X25519 x25519 = X25519();
  SimpleKeyPair recovery = await x25519.newKeyPairFromSeed(recoverySeed);
  List<int> recoveryPublic = (await recovery.extractPublicKey()).bytes;
  SecretKey shared = await x25519.sharedSecretKey(
    keyPair: recovery,
    remotePublicKey:
        SimplePublicKey(parsed.ephemeralPublic!, type: KeyPairType.x25519),
  );
  SecretKey wrapKey =
      await _recoveryWrapKey(shared, parsed.ephemeralPublic!, recoveryPublic);
  List<int>? dataKey = await _unwrap(parsed.recoveryWrap!, wrapKey);
  if (dataKey == null) throw WrongBackupPasswordException();
  return _decryptData(parsed, dataKey);
}

// Whether the backup can also be opened with a recovery key.
bool backupHasRecoveryKey(Uint8List data) {
  try {
    return _parse(data).ephemeralPublic != null;
  } catch (e) {
    return false;
  }
}

// --- Recovery key text --------------------------------------------------------
// 32 random bytes in base32 (A-Z, 2-7), in groups of 4: easy to write down.

const String _base32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

String _toBase32(List<int> bytes) {
  StringBuffer out = StringBuffer();
  int buffer = 0, bits = 0;
  for (int byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_base32[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_base32[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

List<int>? _fromBase32(String text) {
  List<int> out = [];
  int buffer = 0, bits = 0;
  for (int i = 0; i < text.length; i++) {
    int value = _base32.indexOf(text[i]);
    if (value < 0) return null;
    buffer = ((buffer << 5) | value) & 0xFFFF;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xFF);
      bits -= 8;
    }
  }
  return out;
}

String formatRecoveryKey(List<int> seed) {
  String text = _toBase32(seed);
  List<String> groups = [];
  for (int i = 0; i < text.length; i += 4) {
    groups.add(text.substring(i, min(i + 4, text.length)));
  }
  return groups.join("-");
}

// The 32-byte key from what the user typed (spaces, dashes and case are
// ignored; 0/1/8 typed by mistake are read as O/I/B), or null.
List<int>? parseRecoveryKey(String text) {
  String clean = text
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), "")
      .replaceAll("0", "O")
      .replaceAll("1", "I")
      .replaceAll("8", "B");
  if (clean.length != 52) return null;
  List<int>? bytes = _fromBase32(clean);
  if (bytes == null || bytes.length != 32) return null;
  return bytes;
}

class NewRecoveryKey {
  NewRecoveryKey(this.text, this.publicKeyBase64);
  final String text;
  final String publicKeyBase64;
}

Future<NewRecoveryKey> generateRecoveryKey() async {
  Uint8List seed = _randomBytes(32);
  SimpleKeyPair pair = await X25519().newKeyPairFromSeed(seed);
  List<int> public = (await pair.extractPublicKey()).bytes;
  return NewRecoveryKey(formatRecoveryKey(seed), base64.encode(public));
}

List<int>? get savedRecoveryPublicKey {
  String value = (appStateSettings["backupRecoveryPublicKey"] ?? "").toString();
  if (value == "") return null;
  try {
    List<int> bytes = base64.decode(value);
    return bytes.length == 32 ? bytes : null;
  } catch (e) {
    return null;
  }
}

// --- Entry points (background isolate, so the window keeps responding) ------

Future<T> _inIsolate<T>(Future<T> Function() work) async {
  try {
    return await Isolate.run(work);
  } on RemoteError catch (e) {
    if (e.toString().contains("wrong-backup-password") ||
        e.toString().contains("WrongBackupPassword")) {
      throw WrongBackupPasswordException();
    }
    rethrow;
  }
}

Future<Uint8List> encryptBackupBytes(Uint8List plain, String password,
        {List<int>? recoveryPublicKey}) =>
    _inIsolate(() => _encrypt(plain, password, recoveryPublicKey));

Future<Uint8List> decryptBackupBytes(Uint8List data, String password) =>
    _inIsolate(() => _decryptWithPassword(data, password));

Future<Uint8List> decryptBackupWithRecoveryKey(
        Uint8List data, List<int> recoverySeed) =>
    _inIsolate(() => _decryptWithRecoveryKey(data, recoverySeed));

// Typed text: a recovery key if it looks like one, otherwise a password.
Future<Uint8List> decryptBackupWithPasswordOrRecoveryKey(
    Uint8List data, String typed) async {
  List<int>? seed = parseRecoveryKey(typed);
  if (seed != null) {
    try {
      return await decryptBackupWithRecoveryKey(data, seed);
    } on WrongBackupPasswordException {
      // Could still be a (very unusual) password: try it below.
    }
  }
  return decryptBackupBytes(data, typed);
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
  String? fieldLabel,
  Future<String?> Function(String password)? validate,
}) {
  return openPopupCustom<String>(
    context,
    title: title,
    child: _BackupPasswordForm(
      description: description,
      confirm: confirm,
      fieldLabel: fieldLabel,
      validate: validate,
    ),
  );
}

class _BackupPasswordForm extends StatefulWidget {
  const _BackupPasswordForm(
      {this.description, required this.confirm, this.fieldLabel, this.validate});
  final String? description;
  final String? fieldLabel;
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
  final FocusNode firstField = FocusNode();
  final FocusNode repeatField = FocusNode();

  @override
  void dispose() {
    firstField.dispose();
    repeatField.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    await _check();
    // Enter takes the focus away from the field: give it back after an error
    // so the user can fix the text right away.
    if (mounted && error != null) {
      (widget.confirm && password.length >= minimumPasswordLength
              ? repeatField
              : firstField)
          .requestFocus();
    }
  }

  Future<void> _check() async {
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.tab): () =>
            (firstField.hasFocus ? repeatField : firstField).requestFocus(),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
            (repeatField.hasFocus ? firstField : repeatField).requestFocus(),
      },
      child: _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
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
          labelText: widget.fieldLabel ?? "backup-password".tr(),
          obscureText: true,
          autoFocus: true,
          focusNode: firstField,
          padding: EdgeInsetsDirectional.zero,
          onChanged: (value) => password = value,
          // With a second field, Enter moves to it.
          onSubmitted: (_) =>
              widget.confirm ? repeatField.requestFocus() : submit(),
        ),
        if (widget.confirm) ...[
          SizedBox(height: 10),
          TextInput(
            labelText: "repeat-backup-password".tr(),
            obscureText: true,
            focusNode: repeatField,
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
    // Typed twice: a typo here would make a backup nobody can open.
    confirm: true,
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
    description: backupHasRecoveryKey(data)
        ? "encrypted-backup-restore-recovery-description".tr()
        : "encrypted-backup-restore-description".tr(),
    fieldLabel: backupHasRecoveryKey(data)
        ? "password-or-recovery-key".tr()
        : null,
    validate: (password) async {
      try {
        result = await decryptBackupWithPasswordOrRecoveryKey(data, password);
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

// --- Recovery key dialog ------------------------------------------------------

// Creates a new recovery key, shows it once and, after the user confirms it
// was written down, keeps its public half so new backups include it.
// Returns false if cancelled (the previous key, if any, stays).
Future<bool> createAndShowRecoveryKey(BuildContext context) async {
  NewRecoveryKey key = await generateRecoveryKey();
  dynamic saved = await openPopup(
    context,
    icon: appStateSettings["outlinedIcons"]
        ? Icons.key_outlined
        : Icons.key_rounded,
    title: "recovery-key".tr(),
    description: "recovery-key-description".tr(),
    beforeDescriptionWidget: Padding(
      padding: const EdgeInsetsDirectional.only(top: 8, bottom: 5),
      // Material: plain text outside one gets Flutter's red "error" style.
      child: Material(
        type: MaterialType.transparency,
        child: SelectableText(
          key.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: "monospace",
            fontSize: 17,
            fontWeight: FontWeight.bold,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    ),
    onExtraLabel: "copy-recovery-key".tr(),
    onExtra: () => copyToClipboard(key.text),
    onCancelLabel: "cancel".tr(),
    onCancel: () => popRoute(context),
    onSubmitLabel: "recovery-key-written-down".tr(),
    onSubmit: () => popRoute(context, true),
    barrierDismissible: false,
  );
  if (saved != true) return false;
  await updateSettings("backupRecoveryPublicKey", key.publicKeyBase64,
      updateGlobalState: false);
  return true;
}
