import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Shown when a quote is saved without a name, and for older documents that
/// have no `author` field.
const String kDefaultQuoteAuthor = 'Us';

/// A user-added quote stored at `hubs/{hubId}/quotes/{id}`.
///
/// There are no built-in quotes: the dashboard only ever shows these.
class QuoteModel {
  const QuoteModel({
    required this.id,
    required this.text,
    required this.author,
    this.createdAt,
  });

  final String id;
  final String text;
  final String author;
  final DateTime? createdAt;

  factory QuoteModel.fromMap(Map<String, dynamic> data, {required String id}) {
    final rawAuthor = (data['author'] as String?)?.trim() ?? '';
    final created = data['createdAt'];
    return QuoteModel(
      id: id,
      text: ((data['text'] as String?) ?? '').trim(),
      author: rawAuthor.isEmpty ? kDefaultQuoteAuthor : rawAuthor,
      createdAt: created is Timestamp
          ? created.toDate()
          : (created is DateTime ? created : null),
    );
  }
}

/// Newest first; quotes without a timestamp (older data) go last.
List<QuoteModel> sortQuotesNewestFirst(Iterable<QuoteModel> quotes) {
  final list = quotes.toList();
  list.sort((a, b) {
    final x = a.createdAt;
    final y = b.createdAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  return list;
}

/// The quote the dashboard should show next, or null when the hub has added
/// none (the quote slide is then hidden; there is no built-in fallback).
QuoteModel? pickDashboardQuote(List<QuoteModel> custom, Random random) {
  final usable = custom.where((q) => q.text.trim().isNotEmpty).toList();
  if (usable.isEmpty) return null;
  return usable[random.nextInt(usable.length)];
}
