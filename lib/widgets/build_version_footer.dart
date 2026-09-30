import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_build.dart';
import 'web_update_host.dart';

/// Deploy time from a `<sha>-<yyyyMMddTHHmmssZ>` build id, in local time.
/// Null when the id does not carry a timestamp.
DateTime? buildIdDeployedAt(String buildId) {
  final match = RegExp(
    r'-(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$',
  ).firstMatch(buildId.trim());
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  return DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  ).toLocal();
}

/// Small grey version block for the bottom of the Settings drawer.
///
/// Shows the build id compiled into this app and, on web, the latest id
/// stamped in `appMeta/web` with whether they match. When they differ it
/// offers the same "Installing update" flow as the chip.
class BuildVersionFooter extends StatelessWidget {
  const BuildVersionFooter({super.key, this.localBuildId = kWebBuildId});

  /// Used when there is no [WebUpdateScope] above (native, tests).
  final String localBuildId;

  static const _grey = TextStyle(
    color: Colors.grey,
    fontSize: 11,
    letterSpacing: 0.4,
    height: 1.4,
  );

  @override
  Widget build(BuildContext context) {
    final scope = WebUpdateScope.maybeOf(context);
    final local = (scope?.localBuildId ?? localBuildId).trim();
    final remote = scope?.remoteBuildId;

    final lines = <Widget>[
      SelectableText(
        local.isEmpty ? 'Build: dev (no BUILD_ID)' : 'Build: $local',
        key: const ValueKey('build-version-local'),
        textAlign: TextAlign.center,
        style: _grey,
      ),
    ];
    final deployed = buildIdDeployedAt(local);
    if (deployed != null) {
      lines.add(
        Text(
          'Deployed ${DateFormat('d MMM y, HH:mm').format(deployed)}',
          textAlign: TextAlign.center,
          style: _grey,
        ),
      );
    }

    if (scope != null && scope.enabled) {
      if (remote == null) {
        lines.add(const Text('Latest: checking…', style: _grey));
      } else if (remote == local) {
        lines.add(
          const Row(
            key: ValueKey('build-version-status'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 13, color: Colors.green),
              SizedBox(width: 4),
              Flexible(
                child: Text('Up to date with the latest release', style: _grey),
              ),
            ],
          ),
        );
      } else {
        lines.add(
          SelectableText(
            'Latest: $remote',
            key: const ValueKey('build-version-remote'),
            textAlign: TextAlign.center,
            style: _grey,
          ),
        );
        lines.add(
          Text(
            local.isEmpty ? 'Dev build (not a release)' : 'Update available',
            key: const ValueKey('build-version-status'),
            style: _grey.copyWith(
              color: const Color(0xFFE91E63),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        final install = scope.onInstall;
        if (install != null) {
          lines.add(
            TextButton.icon(
              key: const ValueKey('build-version-install'),
              onPressed: install,
              icon: const Icon(Icons.system_update_alt_rounded, size: 16),
              label: const Text('Install update'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE91E63),
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: lines),
    );
  }
}
