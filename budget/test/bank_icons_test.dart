import 'dart:io';

import 'package:budget/struct/bankIcons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every bank in the list has a logo and every logo is listed', () {
    Set<String> files = Directory('assets/banks')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((name) => name.endsWith('.png'))
        .toSet();
    Set<String> listed = bankList.map((b) => b.id + '.png').toSet();
    expect(listed.length, bankList.length, reason: 'duplicate ids');
    expect(files, listed);
  });

  test('bank list is sorted by name', () {
    List<String> names = bankList.map((b) => b.name.toLowerCase()).toList();
    expect(names, [...names]..sort());
  });

  test('iconName parsing', () {
    expect(bankFromIconName('bank:nubank')?.name, 'Nubank');
    expect(bankFromIconName('bank:itau')?.assetPath, 'assets/banks/itau.png');
    expect(bankFromIconName('bank:unknown'), isNull);
    expect(bankFromIconName('nubank'), isNull);
    expect(bankFromIconName(null), isNull);
    expect(bankFromIconName(''), isNull);
    // Values the original Cashew could have stored stay "no icon".
    expect(walletHasIconName('charts.png'), isFalse);
  });

  test('custom image links are validated', () {
    expect(isCustomWalletIcon('cashew-attachment://logo.png'), isTrue);
    expect(isCustomWalletIcon('cashew-attachment://../db.sqlite'), isFalse);
    expect(isCustomWalletIcon('cashew-attachment:///etc/passwd'), isFalse);
    expect(isCustomWalletIcon('cashew-attachment://.hidden.png'), isFalse);
    expect(isCustomWalletIcon('bank:nubank'), isFalse);
    expect(isSupportedIconImage('/a/b/Logo.PNG'), isTrue);
    expect(isSupportedIconImage('/a/b/logo.svg'), isFalse);
  });
}
