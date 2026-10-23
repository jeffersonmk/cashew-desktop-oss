import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/pages/aboutPage.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/noResults.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/selectAmount.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:budget/main.dart';
import 'package:provider/provider.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';

class ExchangeRates extends StatefulWidget {
  const ExchangeRates({super.key});

  @override
  State<ExchangeRates> createState() => _ExchangeRatesState();
}

class _ExchangeRatesState extends State<ExchangeRates> {
  String searchCurrenciesText = "";

  Future addCustomCurrency(String customKey) async {
    List<dynamic> customCurrencies = appStateSettings["customCurrencies"];
    customCurrencies.add(customKey);
    await updateSettings(
      "customCurrencies",
      customCurrencies,
      updateGlobalState: false,
    );
    setState(() {});
  }

  Future<DeletePopupAction?> deleteCustomCurrency(String customKey) async {
    DeletePopupAction? action = await openDeletePopup(
      context,
      title: "delete-currency-question".tr(),
      subtitle: customKey,
    );
    if (action == DeletePopupAction.Delete) {
      List<dynamic> customCurrencies = appStateSettings["customCurrencies"];
      customCurrencies.remove(customKey);
      await updateSettings(
        "customCurrencies",
        customCurrencies,
        updateGlobalState: false,
      );
      Map<dynamic, dynamic> customCurrencyAmountsMap =
          appStateSettings["customCurrencyAmounts"];
      customCurrencyAmountsMap.remove(customKey);
      updateSettings("customCurrencyAmounts", customCurrencyAmountsMap,
          updateGlobalState: false);
      setState(() {});
    }
    return action;
  }

  @override
  Widget build(BuildContext context) {
    Map<dynamic, dynamic> currencyExchange = {};
    List<dynamic> customCurrencies = appStateSettings["customCurrencies"];
    for (String key in customCurrencies) {
      currencyExchange[key] = null;
    }
    // Cashew Desktop: currencies of your accounts that have no rate are
    // listed first, so they can be given a custom rate.
    Map<dynamic, dynamic> missingRates = {};
    for (TransactionWallet wallet in Provider.of<AllWallets>(context).list) {
      String? currency = wallet.currency;
      if (currency != null &&
          !customCurrencies.contains(currency) &&
          appStateSettings["cachedCurrencyExchange"]?[currency] == null &&
          (appStateSettings["cachedCurrencyExchange"] ?? {}).isNotEmpty)
        missingRates[currency] = null;
    }
    currencyExchange = {...missingRates, ...currencyExchange};
    currencyExchange.addAll(appStateSettings["cachedCurrencyExchange"]);
    if (currencyExchange.keys.length <= 0) {
      for (String key in currenciesJSON.keys) {
        currencyExchange[key] = 1;
      }
    }

    // else {
    //   for (String key in [...customCurrencies, ...currencyExchange.keys]) {
    //     if (currenciesJSON.keys.contains(key) == false) {
    //       currencyExchange.remove(key);
    //     }
    //   }
    // }
    Map<dynamic, dynamic> currencyExchangeFiltered = {};
    if (searchCurrenciesText == "") {
      currencyExchangeFiltered = currencyExchange;
    } else {
      for (String key in currencyExchange.keys) {
        String? currencyCountry = currenciesJSON[key]?["CountryName"];
        String? currencyName = currenciesJSON[key]?["Currency"];
        if ((searchCurrenciesText.trim() == "" ||
            key.toLowerCase().contains(searchCurrenciesText.toLowerCase()) ||
            (currencyCountry != null &&
                currencyCountry
                    .toLowerCase()
                    .contains(searchCurrenciesText.toLowerCase())) ||
            (currencyName != null &&
                currencyName
                    .toLowerCase()
                    .contains(searchCurrenciesText.toLowerCase())))) {
          currencyExchangeFiltered[key] = currencyExchange[key];
        }
      }
    }

    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      title: "exchange-rates".tr(),
      actions: [
        IconButton(
          padding: EdgeInsetsDirectional.all(15),
          tooltip: "info".tr(),
          onPressed: () {
            openPopup(
              context,
              title: "exchange-rate-notice".tr(),
              description: "exchange-rate-notice-description".tr() +
                  "\n\n" +
                  "select-an-entry-to-set-custom-exchange-rate".tr(),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.info_outlined
                  : Icons.info_outline_rounded,
              onCancel: () {
                popRoute(context);
              },
              onCancelLabel: "ok".tr(),
            );
          },
          icon: Icon(
            appStateSettings["outlinedIcons"]
                ? Icons.info_outlined
                : Icons.info_outline_rounded,
          ),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: AboutInfoBox(
            title: "exchange-rates-api".tr(),
            link: "https://github.com/fawazahmed0/exchange-api",
          ),
        ),
        if (exchangeRatesDateText(context) != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 17, vertical: 4),
              child: TextFont(
                text: exchangeRatesDateText(context)!,
                maxLines: 3,
                fontSize: 13,
                textColor: getColor(context, "textLight"),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(top: 5),
            child: Row(
              children: [
                SizedBox(width: 15),
                Expanded(
                  child: TextInput(
                    labelText: "search-currencies-placeholder".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.search_outlined
                        : Icons.search_rounded,
                    onChanged: (value) {
                      setState(() {
                        searchCurrenciesText = value;
                      });
                    },
                    autoFocus: false,
                    padding: EdgeInsetsDirectional.zero,
                  ),
                ),
                SizedBox(width: 10),
                ButtonIcon(
                  onTap: () {
                    openBottomSheet(
                      context,
                      popupWithKeyboard: true,
                      PopupFramework(
                        title: "add-currency".tr(),
                        child: SelectText(
                          buttonLabel: "add-currency".tr(),
                          icon: appStateSettings["outlinedIcons"]
                              ? Icons.account_balance_wallet_outlined
                              : Icons.account_balance_wallet_rounded,
                          setSelectedText: (_) {},
                          nextWithInput: (text) async {
                            addCustomCurrency(text);
                          },
                          selectedText: "",
                          placeholder: "currency".tr(),
                          autoFocus: true,
                        ),
                      ),
                    );
                  },
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.add_outlined
                      : Icons.add_rounded,
                ),
                SizedBox(width: 15),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsetsDirectional.only(top: 5),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 17),
              child: TextFont(
                text: "select-an-entry-to-set-custom-exchange-rate".tr(),
                maxLines: 2,
                fontSize: 13,
                textColor: getColor(context, "textLight"),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsetsDirectional.only(top: 7),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 17, vertical: 5),
              child: TextFont(
                text: "1 " +
                    Provider.of<AllWallets>(context)
                        .indexedByPk[appStateSettings["selectedWalletPk"]]!
                        .currency
                        .toString()
                        .allCaps,
                maxLines: 2,
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        currencyExchangeFiltered.keys.length == 0
            ? SliverToBoxAdapter(
                child: NoResults(message: "no-currencies-found".tr()),
              )
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    String key = currencyExchangeFiltered.keys
                        .toList()[index]
                        .toString();
                    bool isCustomCurrency = customCurrencies.contains(key);
                    bool isUnsetCustomCurrency = isCustomCurrency &&
                        appStateSettings["customCurrencyAmounts"]?[key] == null;
                    String calculatedExchangeRateString = isUnsetCustomCurrency
                        ? "1"
                        : (1 /
                                ((amountRatioToPrimaryCurrency(
                                    Provider.of<AllWallets>(context), key))))
                            .toStringAsFixed(14);
                    return ScaledAnimatedSwitcher(
                      keyToWatch: (appStateSettings["customCurrencyAmounts"]
                              ?[key])
                          .toString(),
                      key: ValueKey(key),
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                            bottom: isCustomCurrency ? 5 : 0),
                        child: Tappable(
                          onTap: () async {
                            await openBottomSheet(
                              context,
                              SetCustomCurrency(currencyKey: key),
                            );
                            setState(() {});
                          },
                          color: isCustomCurrency ||
                                  appStateSettings["customCurrencyAmounts"]
                                          ?[key] ==
                                      null
                              ? Colors.transparent
                              : Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                          child: Padding(
                            padding:
                                EdgeInsetsDirectional.symmetric(horizontal: 8),
                            child: OutlinedContainer(
                              enabled: isCustomCurrency,
                              filled: appStateSettings["customCurrencyAmounts"]
                                      ?[key] !=
                                  null,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.symmetric(
                                    horizontal: 7),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextFont(
                                        text: "",
                                        maxLines: 3,
                                        richTextSpan: [
                                          TextSpan(
                                            text: (isUnsetCustomCurrency
                                                    ? " " + "1 USD"
                                                    : "") +
                                                " = " +
                                                calculatedExchangeRateString,
                                            style: TextStyle(
                                              color: getColor(context, "black"),
                                              fontFamily:
                                                  appStateSettings["font"],
                                              fontFamilyFallback: ['Inter'],
                                              fontSize: 16,
                                            ),
                                          ),
                                          TextSpan(
                                            text: " " + key.allCaps,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontFamily:
                                                  appStateSettings["font"],
                                              fontFamilyFallback: ['Inter'],
                                              color: getColor(context, "black"),
                                              fontSize: 16,
                                            ),
                                          ),
                                          if (!isCustomCurrency &&
                                              !currencyHasExchangeRate(key))
                                            TextSpan(
                                              text: "  " +
                                                  "no-exchange-rate".tr(),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontFamily:
                                                    appStateSettings["font"],
                                                fontFamilyFallback: ['Inter'],
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                                fontSize: 13,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (isCustomCurrency)
                                      IconButton(
                                        padding: EdgeInsetsDirectional.all(15),
                                        tooltip: "delete-currency".tr(),
                                        onPressed: () {
                                          deleteCustomCurrency(key);
                                        },
                                        icon: Icon(
                                          appStateSettings["outlinedIcons"]
                                              ? Icons.delete_outlined
                                              : Icons.delete_rounded,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: currencyExchangeFiltered.keys.length,
                ),
              ),
      ],
    );
  }
}

class SetCustomCurrency extends StatefulWidget {
  const SetCustomCurrency({required this.currencyKey, super.key});
  final String currencyKey;

  @override
  State<SetCustomCurrency> createState() => _SetCustomCurrencyState();
}

class _SetCustomCurrencyState extends State<SetCustomCurrency> {
  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: "set-currency".tr(),
      // subtitle: "1 " +
      //     Provider.of<AllWallets>(context)
      //         .indexedByPk[appStateSettings["selectedWalletPk"]]!
      //         .currency
      //         .toString()
      //         .allCaps +
      //     " = ",
      subtitle: "1 USD = ",
      child: SelectAmountValue(
        allowZero: true,
        setSelectedAmount: (amount, amountString) {
          Map<dynamic, dynamic> customCurrencyAmountsMap =
              appStateSettings["customCurrencyAmounts"];
          if (amount == 0 || amountString == "") {
            customCurrencyAmountsMap.remove(widget.currencyKey);
          } else {
            // This will convert the primary currency to the custom currency
            // Issue: the selected currency may change, causing the custom currency to change
            // That is why we only allow the user to set the exchange rate of USD! since it is our reference
            // E.g. primary currency CAD, set custom currency of EUR to 5, then USD->CAD exchange rate changes when it's
            // pulled (the CAD exchange rate entry), the exchange rate for EUR will change, since it references USD!
            // double currentExchangeRate = getCurrencyExchangeRate(
            //     Provider.of<AllWallets>(context, listen: false)
            //         .indexedByPk[appStateSettings["selectedWalletPk"]]!
            //         .currency);
            // customCurrencyAmountsMap[widget.currencyKey] =
            //     currentExchangeRate * amount;
            customCurrencyAmountsMap[widget.currencyKey] = amount;
          }
          updateSettings("customCurrencyAmounts", customCurrencyAmountsMap,
              updateGlobalState: false);
        },
        // Convert amount passed into selected primary currency, read above why disabled
        // amountPassed: appStateSettings["customCurrencyAmounts"]
        //             ?[widget.currencyKey] ==
        //         null
        //     ? ""
        //     : removeTrailingZeroes((1 /
        //             getCurrencyExchangeRate(
        //                 (Provider.of<AllWallets>(context, listen: false)
        //                     .indexedByPk[appStateSettings["selectedWalletPk"]]!
        //                     .currency)) *
        //             (appStateSettings["customCurrencyAmounts"]
        //                     ?[widget.currencyKey] ??
        //                 1))
        //         .toString()),
        amountPassed: appStateSettings["customCurrencyAmounts"]
                    ?[widget.currencyKey] ==
                null
            ? ""
            : removeTrailingZeroes(appStateSettings["customCurrencyAmounts"]
                        ?[widget.currencyKey]
                    .toString() ??
                "0"),
        suffix: " " + widget.currencyKey.allCaps,
        nextLabel: "set-amount".tr(),
        next: () {
          popRoute(context);
        },
      ),
    );
  }
}

String? originalExchangeRatesBeforeOpenString;
void checkIfExchangeRateChangeBefore() {
  originalExchangeRatesBeforeOpenString =
      appStateSettings["customCurrencyAmounts"].toString();
}

bool checkIfExchangeRateChangeAfter() {
  // print(originalExchangeRatesBeforeOpenString);
  // print(appStateSettings["customCurrencyAmounts"].toString());
  if (originalExchangeRatesBeforeOpenString != null &&
      originalExchangeRatesBeforeOpenString !=
          appStateSettings["customCurrencyAmounts"].toString()) {
    print("There was a change to the custom currencies!");
    // Reset global state because currencies need to be reloaded
    appStateKey.currentState?.refreshAppState();
    originalExchangeRatesBeforeOpenString = null;
    return true;
  } else {
    return false;
  }
}


// Cashew Desktop: shown where a currency without an exchange rate is used.
// Amounts in it are converted as 1 = 1 USD until a custom rate is set.
class MissingExchangeRateWarning extends StatelessWidget {
  const MissingExchangeRateWarning(
      {required this.currencyKey, this.onRateSet, super.key});
  final String currencyKey;
  final VoidCallback? onRateSet;

  @override
  Widget build(BuildContext context) {
    if (currencyHasExchangeRate(currencyKey)) return SizedBox.shrink();
    return Tappable(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: 15,
      onTap: () async {
        await openBottomSheet(
          context,
          SetCustomCurrency(currencyKey: currencyKey),
        );
        onRateSet?.call();
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 15, vertical: 12),
        child: Row(
          children: [
            Icon(
              appStateSettings["outlinedIcons"]
                  ? Icons.warning_amber_outlined
                  : Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            SizedBox(width: 12),
            Expanded(
              child: TextFont(
                text: "no-exchange-rate-description"
                    .tr(namedArgs: {"currency": currencyKey.toUpperCase()}),
                maxLines: 5,
                fontSize: 14,
                textColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// "Rates from Oct 22, 2026 · updated 2 hours ago (cdn.jsdelivr.net)"
String? exchangeRatesDateText(BuildContext context) {
  String? date = appStateSettings["cachedCurrencyExchangeDate"];
  String? fetched = appStateSettings["cachedCurrencyExchangeFetched"];
  String? source = appStateSettings["cachedCurrencyExchangeSource"];
  DateTime? dateParsed = date == null ? null : DateTime.tryParse(date);
  DateTime? fetchedParsed = fetched == null ? null : DateTime.tryParse(fetched);
  if (dateParsed == null && fetchedParsed == null) return null;
  List<String> parts = [];
  if (dateParsed != null)
    parts.add("exchange-rates-from".tr(namedArgs: {
      "date": DateFormat.yMMMMd(context.locale.toString()).format(dateParsed)
    }));
  if (fetchedParsed != null)
    parts.add("exchange-rates-updated"
        .tr(namedArgs: {"time": getTimeAgo(fetchedParsed).toLowerCase()}));
  return parts.join(" · ") + (source == null ? "" : "\n" + source);
}
