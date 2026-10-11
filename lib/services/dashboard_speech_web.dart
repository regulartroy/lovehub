import 'dart:async';
import 'dart:js_interop';

import 'dashboard_voice.dart';

@JS('lovehubSpeech')
external LovehubSpeechBridge? get _lovehubSpeech;

extension type LovehubSpeechBridge._(JSObject _) implements JSObject {
  external bool supported();
  external JSPromise<JSObject> listen();
  external void cancel();
  external void stop();
}

extension type _SpeechPayload._(JSObject _) implements JSObject {
  external String outcome;
  external String transcript;
  external String message;
}

DashboardSpeechRecognizer createPlatformSpeechRecognizer() {
  return WebDashboardSpeechRecognizer();
}

class WebDashboardSpeechRecognizer implements DashboardSpeechRecognizer {
  int _ticket = 0;

  LovehubSpeechBridge? get _bridge {
    try {
      return _lovehubSpeech;
    } catch (_) {
      return null;
    }
  }

  @override
  bool get isSupported {
    final bridge = _bridge;
    if (bridge == null) return false;
    try {
      return bridge.supported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DashboardSpeechCapture> listen({
    Duration maxDuration = kDashboardListenLimit,
  }) async {
    final bridge = _bridge;
    if (bridge == null || !isSupported) {
      return const DashboardSpeechCapture(
        outcome: DashboardSpeechOutcome.unavailable,
        message: DashboardVoiceState.speechUnavailableNotice,
      );
    }

    final ticket = ++_ticket;
    try {
      final pending = _listen(bridge);
      DashboardSpeechCapture payload;
      try {
        payload = await pending.timeout(maxDuration);
      } on TimeoutException {
        // Stop (not abort) so the browser still hands back what it heard.
        try {
          bridge.stop();
        } catch (_) {}
        payload = await pending.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            try {
              bridge.cancel();
            } catch (_) {}
            return const DashboardSpeechCapture(
              outcome: DashboardSpeechOutcome.empty,
            );
          },
        );
      }
      if (ticket != _ticket) {
        return const DashboardSpeechCapture(
          outcome: DashboardSpeechOutcome.empty,
          message: 'cancelled',
        );
      }
      return payload;
    } catch (_) {
      return const DashboardSpeechCapture(
        outcome: DashboardSpeechOutcome.unavailable,
        message: DashboardVoiceState.speechUnavailableNotice,
      );
    }
  }

  Future<DashboardSpeechCapture> _listen(LovehubSpeechBridge bridge) async {
    final raw = _SpeechPayload._(await bridge.listen().toDart);
    switch (raw.outcome) {
      case 'transcript':
        return DashboardSpeechCapture(
          outcome: DashboardSpeechOutcome.transcript,
          transcript: raw.transcript,
          message: raw.message,
        );
      case 'denied':
        return DashboardSpeechCapture(
          outcome: DashboardSpeechOutcome.denied,
          message: raw.message,
        );
      case 'empty':
        return DashboardSpeechCapture(
          outcome: DashboardSpeechOutcome.empty,
          message: raw.message,
        );
      case 'unavailable':
        return const DashboardSpeechCapture(
          outcome: DashboardSpeechOutcome.unavailable,
          message: DashboardVoiceState.speechUnavailableNotice,
        );
      default:
        return DashboardSpeechCapture(
          outcome: DashboardSpeechOutcome.error,
          message: raw.message,
        );
    }
  }

  @override
  void cancel() {
    _ticket++;
    try {
      _bridge?.cancel();
    } catch (_) {}
  }
}
