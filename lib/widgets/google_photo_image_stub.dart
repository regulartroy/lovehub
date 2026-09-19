import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/member_profile.dart';

/// Non-web loader: [Image.network] with Google URL retries.
///
/// On web this file is not used — see `google_photo_image_web.dart`.
class GooglePhotoImage extends StatefulWidget {
  const GooglePhotoImage({
    super.key,
    required this.photoURL,
    required this.fallback,
    this.size = 128,
  });

  final String photoURL;
  final Widget fallback;
  final int size;

  @override
  State<GooglePhotoImage> createState() => _GooglePhotoImageState();
}

class _GooglePhotoImageState extends State<GooglePhotoImage> {
  late List<String> _candidates;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _candidates = googlePhotoUrlCandidates(widget.photoURL, size: widget.size);
  }

  @override
  void didUpdateWidget(covariant GooglePhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoURL != widget.photoURL ||
        oldWidget.size != widget.size) {
      _candidates = googlePhotoUrlCandidates(
        widget.photoURL,
        size: widget.size,
      );
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= _candidates.length) return widget.fallback;
    final url = _candidates[_index];
    return Image.network(
      url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      headers: kIsWeb ? null : const {'Accept': 'image/*'},
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('GooglePhotoImage failed $_index $url: $error');
        final next = _index + 1;
        if (next >= _candidates.length) return widget.fallback;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _index < next) setState(() => _index = next);
        });
        return const SizedBox.expand();
      },
    );
  }
}
