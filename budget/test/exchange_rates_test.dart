import 'dart:convert';

import 'package:budget/struct/currencyFunctions.dart';
import 'package:flutter_test/flutter_test.dart';

String table(Map<String, dynamic> usd, {String? date = "2026-10-22"}) {
  Map<String, dynamic> rates = {"usd": 1, ...usd};
  for (int i = 0; i < 120; i++) {
    rates.putIfAbsent("c$i", () => 1.0 + i);
  }
  return json.encode({if (date != null) "date": date, "usd": rates});
}

void main() {
  test('exchange rate sources: same author, HTTPS, jsDelivr first', () {
    expect(exchangeRateSources.length, 2);
    for (String source in exchangeRateSources) {
      expect(Uri.parse(source).scheme, 'https');
      expect(source, endsWith('/v1/currencies/usd.min.json'));
    }
    expect(Uri.parse(exchangeRateSources[0]).host, 'cdn.jsdelivr.net');
    expect(exchangeRateSources[0], contains('/@fawazahmed0/currency-api@'));
    expect(Uri.parse(exchangeRateSources[1]).host,
        'latest.currency-api.pages.dev');
  });

  test('parse: valid table', () {
    ExchangeRatesResult? r =
        parseExchangeRates(table({"brl": 5.02, "btc": 0.0000121}));
    expect(r, isNotNull);
    expect(r!.rates["brl"], 5.02);
    expect(r.rates["btc"], 0.0000121);
    expect(r.date, "2026-10-22");
  });

  test('parse: bad entries dropped, bad date ignored', () {
    ExchangeRatesResult? r = parseExchangeRates(table(
        {"bad": "5", "neg": -1, "zero": 0, "BRL": 5.0},
        date: "<script>"));
    expect(r, isNotNull);
    expect(r!.rates.containsKey("bad"), isFalse);
    expect(r.rates.containsKey("neg"), isFalse);
    expect(r.rates.containsKey("zero"), isFalse);
    expect(r.rates["brl"], 5.0);
    expect(r.date, isNull);
  });

  test('parse: rejects anything that is not a rate table', () {
    expect(parseExchangeRates("<html>Error</html>"), isNull);
    expect(parseExchangeRates("{}"), isNull);
    expect(parseExchangeRates(json.encode({"usd": "x"})), isNull);
    // too few currencies (truncated / wrong file)
    expect(
        parseExchangeRates(json.encode({
          "usd": {"usd": 1, "brl": 5}
        })),
        isNull);
    // not based on USD
    Map<String, dynamic> eur = json.decode(table({}));
    eur["usd"]["usd"] = 1.12;
    expect(parseExchangeRates(json.encode(eur)), isNull);
  });

  test('currencyHasExchangeRate', () {
    Map<String, dynamic> settings = {
      "cachedCurrencyExchange": {"usd": 1, "brl": 5.0},
      "customCurrencyAmounts": {"ton": 0.4},
    };
    bool has(String? k) =>
        currencyHasExchangeRate(k, appStateSettingsPassed: settings);
    expect(has("brl"), isTrue);
    expect(has("ton"), isTrue, reason: "custom rate");
    expect(has("wbtc"), isFalse);
    expect(has(null), isTrue);
    // Nothing downloaded yet: unknown, no warning.
    expect(
        currencyHasExchangeRate("wbtc",
            appStateSettingsPassed: {"cachedCurrencyExchange": {}}),
        isTrue);
  });
}
