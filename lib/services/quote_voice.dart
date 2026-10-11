import 'dashboard_voice.dart';

/// How long a dictated quote may run before the mic stops and keeps what it
/// heard. The dashboard's day questions stay on the shorter default.
const Duration kQuoteListenLimit = Duration(seconds: 30);

/// How long a spoken name may run.
const Duration kQuoteNameListenLimit = Duration(seconds: 10);

const String quoteVoiceUnsupportedNote =
    'Voice isn’t available in this browser. Type it instead — Chrome '
    'supports speaking.';
const String quoteMicBlockedNote =
    'Microphone blocked. Type it instead, or allow the mic in Chrome.';
const String quoteDidntCatchNote =
    'Didn’t catch that. Tap the mic to try again, or type it.';
const String quoteVoiceErrorNote =
    'Speech didn’t work just now. Tap the mic to try again, or type it.';

/// Notice for a capture that produced no usable text. Null for a transcript.
String? quoteVoiceNoticeFor(DashboardSpeechCapture capture) {
  switch (capture.outcome) {
    case DashboardSpeechOutcome.transcript:
      return capture.transcript.trim().isEmpty ? quoteDidntCatchNote : null;
    case DashboardSpeechOutcome.unavailable:
      return quoteVoiceUnsupportedNote;
    case DashboardSpeechOutcome.denied:
      return quoteMicBlockedNote;
    case DashboardSpeechOutcome.empty:
      return quoteDidntCatchNote;
    case DashboardSpeechOutcome.error:
      return quoteVoiceErrorNote;
  }
}

/// Tidies dictated quote text: trims, collapses spaces, drops wrapping quote
/// marks and capitalises a lower-case first letter.
String cleanSpokenQuote(String raw) {
  var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  const open = '"“”‘’\'';
  while (text.length >= 2 &&
      open.contains(text[0]) &&
      open.contains(text[text.length - 1])) {
    text = text.substring(1, text.length - 1).trim();
  }
  if (text.isEmpty) return '';
  return text[0].toUpperCase() + text.substring(1);
}

final RegExp _spokenNameLead = RegExp(
  r"^(?:it was|it is|it's|that was|that is|that's|this was|said by|was said by|"
  r'the quote is from|the author is|author is|written by|from|by|my|our)(?:\s+|$)',
  caseSensitive: false,
);

/// Tidies a spoken or typed name: removes lead-ins like “it was”, trailing
/// punctuation, and capitalises each word when it was all lower-case.
String cleanSpokenAuthor(String raw) {
  var name = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  var previous = '';
  while (previous != name) {
    previous = name;
    name = name.replaceFirst(_spokenNameLead, '').trim();
  }
  name = name.replaceAll(RegExp(r'[.!?,;:]+$'), '').trim();
  if (name.isEmpty) return '';
  if (name == name.toLowerCase()) {
    name = name
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
  return name;
}
