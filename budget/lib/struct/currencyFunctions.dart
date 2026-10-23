import 'package:budget/struct/settings.dart';
import 'dart:convert';
import 'package:budget/database/tables.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic> currenciesJSON = {};

loadCurrencyJSON() async {
  currenciesJSON = await json.decode(
      await rootBundle.loadString('assets/static/generated/currencies.json'));
}

// Cashew Desktop: exchange rates come from fawazahmed0/exchange-api
// (https://github.com/fawazahmed0/exchange-api, CC0). The same files are
// published by the same author on jsDelivr (npm package) and on Cloudflare
// Pages; the author asks apps to fall back to the second when the first
// fails. Both are HTTPS and only JSON is read (never code), and a response is
// only accepted if it looks like a real rate table (see parseExchangeRates).
const List<String> exchangeRateSources = [
  "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json",
  "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json",
];

class ExchangeRatesResult {
  ExchangeRatesResult(this.rates, this.date);
  final Map<String, double> rates;
  final String? date; // "YYYY-MM-DD", the day the rates are from
}

// Returns null unless [body] is a plausible table of rates from 1 USD:
// {"date": "...", "usd": {"brl": 5.02, "btc": 0.000012, ...}}. Entries that
// are not positive finite numbers are dropped.
ExchangeRatesResult? parseExchangeRates(String body) {
  try {
    dynamic decoded = json.decode(body);
    if (decoded is! Map || decoded["usd"] is! Map) return null;
    Map<String, double> rates = {};
    (decoded["usd"] as Map).forEach((key, value) {
      if (key is String && value is num && value.isFinite && value > 0) {
        rates[key.toLowerCase()] = value.toDouble();
      }
    });
    double? usd = rates["usd"];
    if (rates.length < 100 || usd == null || (usd - 1).abs() > 0.000001) {
      return null;
    }
    dynamic date = decoded["date"];
    return ExchangeRatesResult(
        rates,
        date is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)
            ? date
            : null);
  } catch (e) {
    return null;
  }
}

Future<bool> getExchangeRates() async {
  print("Getting exchange rates for current wallets");
  ExchangeRatesResult? result;
  String? usedSource;
  for (String source in exchangeRateSources) {
    try {
      http.Response response =
          await http.get(Uri.parse(source)).timeout(Duration(seconds: 20));
      if (response.statusCode == 200) {
        result = parseExchangeRates(response.body);
        if (result != null) {
          usedSource = source;
          break;
        }
      }
      print("Exchange rates: invalid response from " + source);
    } catch (e) {
      print("Error getting currency rates from " + source + ": " + e.toString());
    }
  }
  if (result == null) return false;
  bool firstTime =
      (appStateSettings["cachedCurrencyExchange"] ?? {}).keys.length <= 0;
  updateSettings("cachedCurrencyExchangeDate", result.date,
      updateGlobalState: false);
  updateSettings(
      "cachedCurrencyExchangeFetched", DateTime.now().toIso8601String(),
      updateGlobalState: false);
  updateSettings("cachedCurrencyExchangeSource", Uri.parse(usedSource!).host,
      updateGlobalState: false);
  updateSettings(
    "cachedCurrencyExchange",
    result.rates,
    updateGlobalState: firstTime,
  );
  return true;
}

// False when the app has rates but none for [currencyKey], so amounts in it
// would be converted as if 1 unit were 1 USD. A custom rate set by the user
// counts as a rate. Before the first download nothing is known: true.
bool currencyHasExchangeRate(String? currencyKey,
    {Map<String, dynamic>? appStateSettingsPassed}) {
  Map<String, dynamic> settings = appStateSettingsPassed ?? appStateSettings;
  if (currencyKey == null || currencyKey == "") return true;
  if (settings["customCurrencyAmounts"]?[currencyKey] != null) return true;
  Map? cached = settings["cachedCurrencyExchange"];
  if (cached == null || cached.isEmpty) return true;
  return cached[currencyKey] != null;
}

double amountRatioToPrimaryCurrencyGivenPk(
  AllWallets allWallets,
  String walletPk, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (allWallets.indexedByPk[walletPk] == null) return 1;
  return amountRatioToPrimaryCurrency(
    allWallets,
    allWallets.indexedByPk[walletPk]?.currency,
    appStateSettingsPassed: appStateSettingsPassed,
  );
}

double amountRatioToPrimaryCurrency(
  AllWallets allWallets,
  String? walletCurrency, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (walletCurrency == null) {
    return 1;
  }
  if (allWallets
          .indexedByPk[
              (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]]
          ?.currency ==
      walletCurrency) {
    return 1;
  }
  if (allWallets.indexedByPk[
          (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]] ==
      null) {
    return 1;
  }

  double exchangeRateFromUSDToTarget = getCurrencyExchangeRate(
    allWallets
        .indexedByPk[
            (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]]
        ?.currency,
    appStateSettingsPassed: appStateSettingsPassed,
  );
  double exchangeRateFromCurrentToUSD = 1 /
      getCurrencyExchangeRate(
        walletCurrency,
        appStateSettingsPassed: appStateSettingsPassed,
      );
  return exchangeRateFromUSDToTarget * exchangeRateFromCurrentToUSD;
}

double? amountRatioFromToCurrency(
    String walletCurrencyBefore, String walletCurrencyAfter) {
  double exchangeRateFromUSDToTarget =
      getCurrencyExchangeRate(walletCurrencyAfter);
  double exchangeRateFromCurrentToUSD =
      1 / getCurrencyExchangeRate(walletCurrencyBefore);
  return exchangeRateFromUSDToTarget * exchangeRateFromCurrentToUSD;
}

// assume selected wallets currency
String getCurrencyString(AllWallets allWallets, {String? currencyKey}) {
  String? selectedWalletCurrency =
      allWallets.indexedByPk[appStateSettings["selectedWalletPk"]]?.currency;
  return currencyKey != null
      ? (currenciesJSON[currencyKey]?["Symbol"] ?? "")
      : selectedWalletCurrency == null
          ? ""
          : (currenciesJSON[selectedWalletCurrency]?["Symbol"] ?? "");
}

double getCurrencyExchangeRate(
  String? currencyKey, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (currencyKey == null || currencyKey == "") return 1;
  if ((appStateSettingsPassed ?? appStateSettings)["customCurrencyAmounts"]
          ?[currencyKey] !=
      null) {
    return (appStateSettingsPassed ?? appStateSettings)["customCurrencyAmounts"]
            [currencyKey]
        .toDouble();
  } else if ((appStateSettingsPassed ??
          appStateSettings)["cachedCurrencyExchange"]?[currencyKey] !=
      null) {
    return (appStateSettingsPassed ??
            appStateSettings)["cachedCurrencyExchange"][currencyKey]
        .toDouble();
  } else {
    return 1;
  }
}

double budgetAmountToPrimaryCurrency(AllWallets allWallets, Budget budget) {
  return budget.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, budget.walletFk));
}

double objectiveAmountToPrimaryCurrency(
    AllWallets allWallets, Objective objective) {
  return objective.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, objective.walletFk));
}

double categoryBudgetLimitToPrimaryCurrency(
    AllWallets allWallets, CategoryBudgetLimit limit) {
  return limit.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, limit.walletFk));
}

// Positive (input)
double getAmountRatioWalletTransferTo(AllWallets allWallets, String walletToPk,
    {String? enteredAmountWalletPk}) {
  return amountRatioFromToCurrency(
        allWallets
            .indexedByPk[
                enteredAmountWalletPk ?? appStateSettings["selectedWalletPk"]]!
            .currency!,
        allWallets.indexedByPk[walletToPk]!.currency!,
      ) ??
      1;
}

// Negative (output)
double getAmountRatioWalletTransferFrom(
    AllWallets allWallets, String walletFromPk,
    {String? enteredAmountWalletPk}) {
  return -1 *
      (amountRatioFromToCurrency(
            allWallets
                .indexedByPk[enteredAmountWalletPk ??
                    appStateSettings["selectedWalletPk"]]!
                .currency!,
            allWallets.indexedByPk[walletFromPk]!.currency!,
          ) ??
          1);
}
