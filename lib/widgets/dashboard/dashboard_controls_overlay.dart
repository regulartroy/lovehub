import 'package:flutter/material.dart';

import 'dashboard_theme.dart';

/// Play / pause pill that fades in when the wall tablet is tapped.
///
/// The mic sits in the same pill so it shares this fade.
class DashboardControlsOverlay extends StatelessWidget {
  const DashboardControlsOverlay({
    super.key,
    required this.visible,
    required this.isPlaying,
    required this.isListening,
    required this.onExit,
    required this.onTogglePlay,
    required this.onOptions,
    required this.onMic,
  });

  final bool visible;
  final bool isPlaying;
  final bool isListening;
  final VoidCallback onExit;
  final VoidCallback onTogglePlay;
  final VoidCallback onOptions;
  final VoidCallback onMic;

  static const opacityKey = ValueKey('dashboard-controls-opacity');
  static const pillKey = ValueKey('dashboard-controls-overlay');
  static const playKey = ValueKey('dashboard-controls-play');
  static const micKey = ValueKey('dashboard-controls-mic');
  static const listeningKey = ValueKey('dashboard-controls-listening');

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      key: opacityKey,
      duration: const Duration(milliseconds: 280),
      opacity: visible ? 1.0 : 0.0,
      child: !visible
          ? const SizedBox.shrink()
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  key: pillKey,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: DashboardTheme.fade(Colors.black, 0.82),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Exit dashboard',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white54,
                          size: 26,
                        ),
                        onPressed: onExit,
                      ),
                      IconButton(
                        key: playKey,
                        tooltip: isPlaying ? 'Pause' : 'Play',
                        icon: Icon(
                          isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                        onPressed: onTogglePlay,
                      ),
                      IconButton(
                        key: micKey,
                        tooltip: isListening
                            ? 'Listening. Tap to stop'
                            : "Ask what's on",
                        icon: Icon(
                          isListening
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: isListening
                              ? DashboardTheme.accent
                              : Colors.white,
                          size: 34,
                        ),
                        onPressed: onMic,
                      ),
                      if (isListening)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Text(
                            'Listening',
                            key: listeningKey,
                            style: TextStyle(
                              color: DashboardTheme.accent,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Options',
                        icon: const Icon(
                          Icons.settings_rounded,
                          color: Colors.white54,
                          size: 26,
                        ),
                        onPressed: onOptions,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
