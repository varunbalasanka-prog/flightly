import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

typedef CockpitSend = void Function(Map<String, dynamic> message);

/// Web: the Cesium page runs in an iframe and receives updates via postMessage.
class CockpitSurface extends StatefulWidget {
  final void Function(CockpitSend send) onReady;
  const CockpitSurface({super.key, required this.onReady});

  @override
  State<CockpitSurface> createState() => _CockpitSurfaceState();
}

class _CockpitSurfaceState extends State<CockpitSurface> {
  web.HTMLIFrameElement? _frame;

  void _send(Map<String, dynamic> message) {
    _frame?.contentWindow?.postMessage(jsonEncode(message).toJS, '*'.toJS);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (Object element) {
        final frame = element as web.HTMLIFrameElement;
        // Flutter web serves bundled assets under assets/assets/.
        frame.src = 'assets/assets/cockpit/cockpit.html';
        frame.style.border = 'none';
        frame.style.width = '100%';
        frame.style.height = '100%';
        frame.onload = ((web.Event _) => widget.onReady(_send)).toJS;
        _frame = frame;
      },
    );
  }
}
