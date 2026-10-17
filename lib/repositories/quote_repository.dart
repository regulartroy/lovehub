import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/quote_model.dart';

/// Reads and adds the hub's custom quotes.
abstract class QuoteRepository {
  Stream<List<QuoteModel>> watch(String hubId);

  /// Saves one quote. A blank [author] is stored as [kDefaultQuoteAuthor].
  Future<void> add(String hubId, {required String text, String author = ''});

  /// Updates text and author of quote [id]. A blank [author] becomes
  /// [kDefaultQuoteAuthor]; a blank [text] is ignored.
  Future<void> update(
    String hubId,
    String id, {
    required String text,
    String author = '',
  });

  /// Deletes quote [id].
  Future<void> delete(String hubId, String id);

  /// Puts back a deleted quote with the same id, text, author and date
  /// (used by Undo).
  Future<void> restore(String hubId, QuoteModel quote);
}

class FirestoreQuoteRepository implements QuoteRepository {
  FirestoreQuoteRepository([FirebaseFirestore? db])
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _quotes(String hubId) =>
      _db.collection('hubs').doc(hubId).collection('quotes');

  @override
  Stream<List<QuoteModel>> watch(String hubId) {
    return _quotes(hubId).snapshots().map(
      (snap) => sortQuotesNewestFirst(
        snap.docs
            .map((d) => QuoteModel.fromMap(d.data(), id: d.id))
            .where((q) => q.text.isNotEmpty),
      ),
    );
  }

  @override
  Future<void> add(
    String hubId, {
    required String text,
    String author = '',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final name = author.trim();
    await _quotes(hubId).add({
      'text': trimmed,
      'author': name.isEmpty ? kDefaultQuoteAuthor : name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> update(
    String hubId,
    String id, {
    required String text,
    String author = '',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final name = author.trim();
    await _quotes(hubId).doc(id).update({
      'text': trimmed,
      'author': name.isEmpty ? kDefaultQuoteAuthor : name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> delete(String hubId, String id) =>
      _quotes(hubId).doc(id).delete();

  @override
  Future<void> restore(String hubId, QuoteModel quote) {
    final created = quote.createdAt;
    return _quotes(hubId).doc(quote.id).set({
      'text': quote.text,
      'author': quote.author,
      'createdAt': created == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(created),
    });
  }
}
