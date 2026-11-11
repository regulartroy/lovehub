import 'package:cloud_functions/cloud_functions.dart';

/// Region and name of the callable that runs Gemini on Vertex AI.
const smartSortRegion = 'europe-west2';
const smartSortFunction = 'smartSortShopping';

/// Hard limits that must match functions/smart_sort.js.
const smartSortMaxItems = 80;
const smartSortMaxTextLen = 200;

class SmartSortException implements Exception {
  SmartSortException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Calls [smartSortShopping] and returns `id -> sortIndex`.
///
/// Only items with a usable id and text are sent, up to [smartSortMaxItems].
/// The local aisle fallback fills in anything omitted.
Future<Map<String, int>> callSmartSortShopping({
  required String hubId,
  required List<(String id, String text)> items,
  Future<dynamic> Function(Map<String, dynamic> payload)? call,
}) async {
  if (hubId.trim().isEmpty) {
    throw SmartSortException('Missing hub.');
  }
  final payloadItems = <Map<String, String>>[];
  for (final (id, text) in items) {
    final trimmedId = id.trim();
    final trimmedText = text.trim();
    if (trimmedId.isEmpty || trimmedText.isEmpty) continue;
    if (trimmedText.length > smartSortMaxTextLen) continue;
    payloadItems.add({'id': trimmedId, 'text': trimmedText});
    if (payloadItems.length >= smartSortMaxItems) break;
  }
  if (payloadItems.isEmpty) {
    throw SmartSortException('Missing shopping items.');
  }
  final payload = {'hubId': hubId.trim(), 'items': payloadItems};
  final allowed = payloadItems.map((row) => row['id']!).toSet();
  final data = await (call ?? _firebaseCall)(payload);
  final indexes = sortIndexesFromCallable(data, allowed);
  if (indexes.isEmpty) {
    throw SmartSortException("Couldn't sort the shopping list.");
  }
  return indexes;
}

Future<dynamic> _firebaseCall(Map<String, dynamic> payload) async {
  final functions = FirebaseFunctions.instanceFor(region: smartSortRegion);
  final callable = functions.httpsCallable(
    smartSortFunction,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
  );
  try {
    final result = await callable.call<dynamic>(payload);
    return result.data;
  } on FirebaseFunctionsException catch (error) {
    throw SmartSortException(
      messageForSmartSortCode(error.code, error.message),
    );
  }
}

/// Parses `{sortIndexes: {id: n}}` or `[{id, sortIndex}]` from the function.
Map<String, int> sortIndexesFromCallable(dynamic data, Set<String> allowedIds) {
  final out = <String, int>{};
  if (data is Map && data['sortIndexes'] is Map) {
    (data['sortIndexes'] as Map).forEach((key, value) {
      if (key is String && allowedIds.contains(key) && value is num) {
        final index = value.toInt();
        if (index >= 1 && index <= 999) out[key] = index;
      }
    });
    return out;
  }
  final rows = data is Map && data['sortIndexes'] is List
      ? data['sortIndexes'] as List
      : data is List
      ? data
      : const [];
  for (final row in rows) {
    if (row is Map && row['id'] is String && row['sortIndex'] is num) {
      final id = row['id'] as String;
      if (!allowedIds.contains(id)) continue;
      final index = (row['sortIndex'] as num).toInt();
      if (index >= 1 && index <= 999) out[id] = index;
    }
  }
  return out;
}

String messageForSmartSortCode(String code, String? message) {
  switch (code) {
    case 'unauthenticated':
      return 'Sign in to sort the shopping list.';
    case 'permission-denied':
      return 'You need to be a member of this hub to sort the shopping list.';
    case 'invalid-argument':
      return (message != null && message.trim().isNotEmpty)
          ? message.trim()
          : "That list couldn't be sent for sorting.";
    case 'resource-exhausted':
      return 'Too many sorts. Wait a minute and try again.';
    case 'unavailable':
    case 'deadline-exceeded':
    case 'internal':
      return "Couldn't sort the shopping list.";
    case 'not-found':
      return "Smart Sort isn't available yet. It needs the smartSortShopping function to be deployed.";
    default:
      return "Couldn't sort the shopping list.";
  }
}
