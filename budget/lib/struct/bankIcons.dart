// Cashew Desktop: bank / digital account icon for each account (wallet).
//
// The wallets table already has an "iconName" column that the original
// Cashew never used, so the choice is stored there and the database schema
// does not change (backups stay compatible with the original app, which just
// ignores the value). Two kinds of value:
//
//   bank:nubank                         a logo bundled in assets/banks/
//   cashew-attachment://<file name>     an image picked by the user, copied
//                                       into the attachments folder (so it
//                                       goes into .zip backups too)
//
// Anything else (null, empty, unknown) means "no icon" and the app shows the
// account exactly as before (the coloured dot).
//
// Logos: logos-bancos-br (https://github.com/rzmt/logos-bancos-br), taken
// from the Open Finance Brasil directory / the institutions' own sites. They
// are trademarks of their institutions, used only to identify them; see
// assets/banks/NOTICE.md.

import 'dart:io';

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/filePickerCompat.dart';
import 'package:budget/struct/localAttachments.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/colors.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

const String bankIconPrefix = "bank:";

class BankInfo {
  const BankInfo(this.id, this.name);
  final String id;
  final String name;
  String get assetPath => "assets/banks/" + id + ".png";
  String get iconName => bankIconPrefix + id;
}

// Most used banks and digital accounts in Brazil, in alphabetical order.
const List<BankInfo> bankList = [
  BankInfo("99pay", "99Pay"),
  BankInfo("agibank", "Agibank"),
  BankInfo("banco-do-brasil", "Banco do Brasil"),
  BankInfo("banco-do-nordeste", "Banco do Nordeste"),
  BankInfo("banco-original", "Banco Original"),
  BankInfo("banco-pan", "Banco Pan"),
  BankInfo("banrisul", "Banrisul"),
  BankInfo("bradesco", "Bradesco"),
  BankInfo("bs2", "BS2"),
  BankInfo("btg-pactual", "BTG Pactual"),
  BankInfo("c6-bank", "C6 Bank"),
  BankInfo("caixa", "Caixa"),
  BankInfo("cora", "Cora"),
  BankInfo("daycoval", "Daycoval"),
  BankInfo("genial", "Genial"),
  BankInfo("ifood-pago", "iFood Pago"),
  BankInfo("infinitepay", "InfinitePay"),
  BankInfo("inter", "Inter"),
  BankInfo("itau", "Itaú"),
  BankInfo("magalupay", "MagaluPay"),
  BankInfo("mercado-pago", "Mercado Pago"),
  BankInfo("neon", "Neon"),
  BankInfo("nubank", "Nubank"),
  BankInfo("pagbank", "PagBank"),
  BankInfo("picpay", "PicPay"),
  BankInfo("safra", "Safra"),
  BankInfo("santander", "Santander"),
  BankInfo("sicoob", "Sicoob"),
  BankInfo("sicredi", "Sicredi"),
  BankInfo("sofisa", "Sofisa"),
  BankInfo("stone", "Stone"),
  BankInfo("xp", "XP Investimentos"),
];

final Map<String, BankInfo> _banksById = {
  for (BankInfo bank in bankList) bank.id: bank
};

BankInfo? bankFromIconName(String? iconName) {
  if (iconName == null || !iconName.startsWith(bankIconPrefix)) return null;
  return _banksById[iconName.substring(bankIconPrefix.length)];
}

bool isCustomWalletIcon(String? iconName) =>
    iconName != null && attachmentFileNameFromLink(iconName) != null;

bool walletHasIcon(TransactionWallet? wallet) =>
    bankFromIconName(wallet?.iconName) != null ||
    (localAttachmentsSupported && isCustomWalletIcon(wallet?.iconName));

// Custom images are read synchronously from the attachments folder; its path
// is resolved once at startup (see loadWalletIconsDirectory) so the icons
// don't flicker while lists are built.
String? _attachmentsDirectoryPath;

Future<void> loadWalletIconsDirectory() async {
  if (!localAttachmentsSupported) return;
  try {
    _attachmentsDirectoryPath = (await getAttachmentsDirectory()).path;
  } catch (e) {
    print("Could not find the attachments folder: " + e.toString());
  }
}

File? _customIconFile(String iconName) {
  String? name = attachmentFileNameFromLink(iconName);
  String? directory = _attachmentsDirectoryPath;
  if (name == null || directory == null) return null;
  File file = File(p.join(directory, name));
  if (!p.isWithin(directory, file.path)) return null;
  return file;
}

// The account's icon on a white rounded square (logos are made for a light
// background; this keeps dark logos visible in the dark theme too).
// Returns an empty box of the same size when the account has no icon and
// [placeholder] is null.
class WalletIcon extends StatelessWidget {
  const WalletIcon({
    super.key,
    required this.iconName,
    this.size = 24,
    this.borderColor,
    this.placeholder,
  });
  final String? iconName;
  final double size;
  final Color? borderColor;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    Widget? image;
    BankInfo? bank = bankFromIconName(iconName);
    if (bank != null) {
      image = Image.asset(
        bank.assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => SizedBox.shrink(),
      );
    } else if (localAttachmentsSupported && isCustomWalletIcon(iconName)) {
      File? file = _customIconFile(iconName!);
      if (file != null)
        image = Image.file(
          file,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, __, ___) => Icon(
            Icons.broken_image_outlined,
            size: size * 0.7,
            color: Colors.black45,
          ),
        );
    }
    if (image == null) {
      return placeholder ?? SizedBox(width: size, height: size);
    }
    double radius = size * 0.28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor == null
            ? Border.all(color: Colors.black.withOpacity(0.08), width: 0.5)
            : Border.all(color: borderColor!, width: 2),
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(radius - (borderColor == null ? 0.5 : 2)),
        child: image,
      ),
    );
  }
}

const List<String> _imageExtensions = [
  "png",
  "jpg",
  "jpeg",
  "webp",
  "gif",
  "bmp",
];

bool isSupportedIconImage(String path) => _imageExtensions
    .contains(p.extension(path).replaceFirst(".", "").toLowerCase());

// Lets the user pick an image and copies it to the attachments folder.
Future<String?> pickCustomWalletIcon() async {
  try {
    FilePickerResult? result = await pickFilesCompat(
      dialogTitle: "choose-image".tr(),
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: _imageExtensions,
    );
    String? path = result?.files.single.path;
    if (path == null) return null;
    File source = File(path);
    if (!await source.exists()) return null;
    if (!isSupportedIconImage(path)) {
      openSnackbar(SnackbarMessage(
        title: "image-not-supported".tr(),
        description: _imageExtensions.join(", "),
        icon: Icons.warning_rounded,
      ));
      return null;
    }
    String link = await copyFileToAttachments(source);
    if (_attachmentsDirectoryPath == null) await loadWalletIconsDirectory();
    return link;
  } catch (e) {
    print("Wallet icon error: " + e.toString());
    openSnackbar(SnackbarMessage(
      title: "attachment-error".tr(),
      description: e.toString(),
      icon: Icons.warning_rounded,
    ));
    return null;
  }
}

// Result of the picker: null = cancelled, "" = remove the icon.
Future<String?> selectWalletIconPopup(BuildContext context,
    {String? currentIconName}) async {
  return await openBottomSheet(
    context,
    PopupFramework(
      title: "bank-or-account".tr(),
      subtitle: "bank-or-account-description".tr(),
      child: _WalletIconPicker(currentIconName: currentIconName),
    ),
  );
}

class _WalletIconPicker extends StatefulWidget {
  const _WalletIconPicker({this.currentIconName});
  final String? currentIconName;

  @override
  State<_WalletIconPicker> createState() => _WalletIconPickerState();
}

class _WalletIconPickerState extends State<_WalletIconPicker> {
  String search = "";

  String _normalize(String text) {
    const Map<String, String> accents = {
      "á": "a", "à": "a", "â": "a", "ã": "a", "é": "e", "ê": "e", //
      "í": "i", "ó": "o", "ô": "o", "õ": "o", "ú": "u", "ç": "c",
    };
    String out = text.toLowerCase();
    accents.forEach((key, value) => out = out.replaceAll(key, value));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    List<BankInfo> banks = bankList
        .where((bank) => _normalize(bank.name).contains(_normalize(search)))
        .toList();
    bool hasCustom = isCustomWalletIcon(widget.currentIconName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 12),
          child: TextField(
            autofocus: false,
            decoration: InputDecoration(
              hintText: "search-bank".tr(),
              prefixIcon: Icon(appStateSettings["outlinedIcons"]
                  ? Icons.search_outlined
                  : Icons.search_rounded),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) => setState(() => search = value),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            if (search == "")
              _PickerTile(
                label: "no-icon".tr(),
                selected: !walletHasIconName(widget.currentIconName),
                icon: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: getColor(context, "black").withOpacity(0.3)),
                  ),
                  child: Icon(Icons.block_rounded,
                      color: getColor(context, "black").withOpacity(0.5)),
                ),
                onTap: () => popRoute(context, ""),
              ),
            if (search == "" && localAttachmentsSupported)
              _PickerTile(
                label: "custom-image".tr(),
                selected: hasCustom,
                icon: hasCustom
                    ? WalletIcon(iconName: widget.currentIconName, size: 44)
                    : Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color:
                                  getColor(context, "black").withOpacity(0.3)),
                        ),
                        child: Icon(Icons.add_photo_alternate_outlined,
                            color: getColor(context, "black").withOpacity(0.6)),
                      ),
                onTap: () async {
                  String? link = await pickCustomWalletIcon();
                  if (link != null) popRoute(context, link);
                },
              ),
            for (BankInfo bank in banks)
              _PickerTile(
                label: bank.name,
                selected: widget.currentIconName == bank.iconName,
                icon: WalletIcon(iconName: bank.iconName, size: 44),
                onTap: () => popRoute(context, bank.iconName),
              ),
          ],
        ),
        if (banks.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.all(15),
            child: TextFont(
              text: "no-search-results".tr(),
              textAlign: TextAlign.center,
            ),
          ),
        SizedBox(height: 10),
      ],
    );
  }
}

bool walletHasIconName(String? iconName) =>
    bankFromIconName(iconName) != null || isCustomWalletIcon(iconName);

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      borderRadius: 14,
      color: selected
          ? Theme.of(context).colorScheme.secondaryContainer
          : Colors.transparent,
      child: SizedBox(
        width: 92,
        child: Padding(
          padding:
              const EdgeInsetsDirectional.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              icon,
              SizedBox(height: 6),
              TextFont(
                text: label,
                fontSize: 12.5,
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
