/// Client-side checks for a recipe link.
///
/// The Cloud Function does the same checks again and also refuses hostnames
/// that resolve to a private or internal address. This file stays free of
/// `dart:io` so Flutter web can run it.
library;

class RecipeUrlException implements Exception {
  RecipeUrlException(this.message);
  final String message;

  @override
  String toString() => message;
}

const _blockedMessage = "That link can't be fetched.";
const _pasteMessage = 'Paste a full http or https recipe link.';

const _blockedHosts = {
  'localhost',
  'localhost.localdomain',
  'metadata',
  'metadata.google.internal',
  'metadata.google.com',
};

const _blockedSuffixes = [
  '.local',
  '.localhost',
  '.internal',
  '.localdomain',
  '.home.arpa',
  '.intranet',
  '.lan',
  '.corp',
  '.localnet',
  '.cluster.local',
  '.svc',
];

/// Returns a canonical http(s) URL, or throws [RecipeUrlException].
String validateRecipeImportUrl(String input) {
  final raw = input.trim();
  if (raw.isEmpty || raw.length > 2000) {
    throw RecipeUrlException(_pasteMessage);
  }
  if (raw.contains('\\') || RegExp(r'[\u0000-\u0020]').hasMatch(raw)) {
    throw RecipeUrlException(_pasteMessage);
  }

  final withScheme = raw.contains('://') ? raw : 'https://$raw';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw RecipeUrlException(_pasteMessage);
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw RecipeUrlException(_pasteMessage);
  }
  if (uri.userInfo.isNotEmpty) {
    throw RecipeUrlException(_blockedMessage);
  }
  if (uri.hasPort && uri.port != 80 && uri.port != 443) {
    throw RecipeUrlException(_blockedMessage);
  }

  final host = _stripDot(uri.host.toLowerCase());
  if (host.isEmpty ||
      _isBlockedHostname(host) ||
      _isObfuscatedHost(host) ||
      _isBlockedAddress(host)) {
    throw RecipeUrlException(_blockedMessage);
  }

  return uri.removeFragment().toString();
}

String recipeSourceLabel(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  final host = uri.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}

String _stripDot(String host) =>
    host.endsWith('.') ? host.substring(0, host.length - 1) : host;

bool _isBlockedHostname(String host) {
  if (_blockedHosts.contains(host)) return true;
  for (final suffix in _blockedSuffixes) {
    if (host.endsWith(suffix)) return true;
  }
  final looksLikeIp = _isIpv4(host) || host.contains(':');
  if (!looksLikeIp && !host.contains('.')) return true;
  return false;
}

bool _isObfuscatedHost(String host) {
  if (RegExp(r'^\d+$').hasMatch(host)) return true;
  if (host.startsWith('0x')) return true;
  final parts = host.split('.');
  if (parts.length >= 2 &&
      parts.length <= 4 &&
      parts.every((part) => RegExp(r'^\d+$').hasMatch(part))) {
    if (parts.length != 4) return true;
    if (parts.any((part) => part.length > 1 && part.startsWith('0'))) {
      return true;
    }
  }
  return false;
}

bool _isBlockedAddress(String host) {
  if (_isIpv4(host)) return _isPrivateV4(host);
  if (host.contains(':')) return _isPrivateV6(host);
  return false;
}

bool _isIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    if (!RegExp(r'^\d{1,3}$').hasMatch(part)) return false;
    final value = int.tryParse(part);
    if (value == null || value > 255) return false;
  }
  return true;
}

int? _ipv4ToInt(String ip) {
  if (!_isIpv4(ip)) return null;
  var value = 0;
  for (final part in ip.split('.')) {
    value = (value << 8) + int.parse(part);
  }
  return value;
}

bool _inCidrV4(String ip, String base, int bits) {
  final address = _ipv4ToInt(ip);
  final network = _ipv4ToInt(base);
  if (address == null || network == null) return false;
  final mask = bits == 0 ? 0 : (0xffffffff << (32 - bits)) & 0xffffffff;
  return (address & mask) == (network & mask);
}

bool _isPrivateV4(String ip) {
  const ranges = <(String, int)>[
    ('0.0.0.0', 8),
    ('10.0.0.0', 8),
    ('100.64.0.0', 10),
    ('127.0.0.0', 8),
    ('169.254.0.0', 16),
    ('172.16.0.0', 12),
    ('192.0.0.0', 24),
    ('192.0.2.0', 24),
    ('192.168.0.0', 16),
    ('198.18.0.0', 15),
    ('198.51.100.0', 24),
    ('203.0.113.0', 24),
    ('224.0.0.0', 4),
    ('240.0.0.0', 4),
  ];
  for (final (base, bits) in ranges) {
    if (_inCidrV4(ip, base, bits)) return true;
  }
  return false;
}

bool _isPrivateV6(String ip) {
  final expanded = _expandIpv6(ip.toLowerCase());
  if (expanded == null) return true;
  if (expanded == '0000:0000:0000:0000:0000:0000:0000:0000') return true;
  if (expanded == '0000:0000:0000:0000:0000:0000:0000:0001') return true;
  final first = int.parse(expanded.substring(0, 4), radix: 16);
  if ((first & 0xfe00) == 0xfc00) return true;
  if ((first & 0xffc0) == 0xfe80) return true;
  if ((first & 0xff00) == 0xff00) return true;
  if (expanded.startsWith('2001:0db8:')) return true;
  if (expanded.startsWith('0064:ff9b:0000:0000:0000:0000:')) return true;
  if (expanded.startsWith('0000:0000:0000:0000:0000:ffff:')) {
    return _isPrivateV4(_tailV4(expanded));
  }
  if (expanded.startsWith('2002:')) {
    return _isPrivateV4(_sixToFour(expanded));
  }
  return false;
}

String _tailV4(String expanded) {
  final parts = expanded.split(':');
  final high = int.parse(parts[6], radix: 16);
  final low = int.parse(parts[7], radix: 16);
  final value = (high << 16) + low;
  return '${(value >> 24) & 255}.${(value >> 16) & 255}.${(value >> 8) & 255}.${value & 255}';
}

String _sixToFour(String expanded) {
  final parts = expanded.split(':');
  final high = int.parse(parts[1], radix: 16);
  final low = int.parse(parts[2], radix: 16);
  return '${(high >> 8) & 255}.${high & 255}.${(low >> 8) & 255}.${low & 255}';
}

String? _expandIpv6(String ip) {
  if (ip.contains('%')) return null;
  var text = ip;
  final dotted = RegExp(r'^(.*:)(\d+\.\d+\.\d+\.\d+)$').firstMatch(text);
  if (dotted != null) {
    final value = _ipv4ToInt(dotted.group(2)!);
    if (value == null) return null;
    final high = ((value >> 16) & 0xffff).toRadixString(16);
    final low = (value & 0xffff).toRadixString(16);
    text = '${dotted.group(1)}$high:$low';
  }
  List<String> parts;
  if (text.contains('::')) {
    if ('::'.allMatches(text).length > 1) return null;
    final halves = text.split('::');
    final head = halves[0].isEmpty ? <String>[] : halves[0].split(':');
    final tail = halves[1].isEmpty ? <String>[] : halves[1].split(':');
    final missing = 8 - head.length - tail.length;
    if (missing < 0) return null;
    parts = [...head, ...List.filled(missing, '0'), ...tail];
  } else {
    parts = text.split(':');
  }
  if (parts.length != 8) return null;
  final expanded = <String>[];
  for (final part in parts) {
    if (!RegExp(r'^[0-9a-f]{1,4}$').hasMatch(part)) return null;
    expanded.add(part.padLeft(4, '0'));
  }
  return expanded.join(':');
}
