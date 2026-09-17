import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef CockpitSend = void Function(Map<String, dynamic> message);

/// Android / iOS: the Cesium page runs in a native web view. Desktop builds
/// have no web view plugin, so they get an explanation instead.
class CockpitSurface extends StatefulWidget {
  final void Function(CockpitSend send) onReady;
  const CockpitSurface({super.key, required this.onReady});

  @override
  State<CockpitSurface> createState() => _CockpitSurfaceState();
}

class _CockpitSurfaceState extends State<CockpitSurface> {
  WebViewController? _controller;

  bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (!_supported) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) => widget.onReady(_send)))
      ..loadFlutterAsset('assets/cockpit/cockpit.html');
  }

  void _send(Map<String, dynamic> message) {
    // Double-encode: the inner JSON is passed to the page as a string literal.
    _controller?.runJavaScript('window.skypulseUpdate(${jsonEncode(jsonEncode(message))})');
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: Text('Cockpit view runs on Android, iOS and the web app.'));
    }
    return WebViewWidget(controller: controller);
  }
}
