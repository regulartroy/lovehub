import 'dashboard_speech_unsupported.dart'
    if (dart.library.html) 'dashboard_speech_web.dart'
    as speech_impl;
import 'dashboard_voice.dart';

export 'dashboard_voice.dart';

DashboardSpeechRecognizer createDashboardSpeechRecognizer() {
  return speech_impl.createPlatformSpeechRecognizer();
}
