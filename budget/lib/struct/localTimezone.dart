// Cashew Desktop OSS: find the system timezone on every platform.
//
// flutter_timezone only ships Android/iOS/macOS/web implementations, so on
// Linux and Windows we fall back to reading it ourselves.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

const String _fallbackTimezone = "UTC";

Future<tz.Location> getLocalTimezoneLocation() async {
  for (String? name in await _candidateNames()) {
    if (name == null || name.trim() == "") continue;
    try {
      return tz.getLocation(name.trim());
    } catch (_) {}
  }
  return tz.getLocation(_fallbackTimezone);
}

Future<List<String?>> _candidateNames() async {
  List<String?> names = [];
  if (!kIsWeb && Platform.isLinux) {
    names.add(Platform.environment["TZ"]);
    names.add(_linuxTimezoneFromEtcTimezone());
    names.add(_linuxTimezoneFromLocaltimeLink());
    return names;
  }
  try {
    names.add(await FlutterTimezone.getLocalTimezone());
  } catch (e) {
    print("Could not read timezone from plugin: " + e.toString());
  }
  return names;
}

String? _linuxTimezoneFromEtcTimezone() {
  try {
    File file = File("/etc/timezone");
    if (file.existsSync()) return file.readAsStringSync().trim();
  } catch (_) {}
  return null;
}

String? _linuxTimezoneFromLocaltimeLink() {
  try {
    // /etc/localtime -> /usr/share/zoneinfo/America/Sao_Paulo
    String target = File("/etc/localtime").resolveSymbolicLinksSync();
    const String marker = "zoneinfo/";
    int index = target.indexOf(marker);
    if (index != -1) return target.substring(index + marker.length);
  } catch (_) {}
  return null;
}
