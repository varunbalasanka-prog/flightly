import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/place_intel_service.dart';

/// "Ask about my flight": a Claude assistant that answers from live data,
/// by typing or by voice.
///
/// Spend is capped per user per day on the server; the running total is shown
/// here so it's never a surprise.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <AssistantTurn>[];
  final _speech = SpeechToText();
  final _tts = FlutterTts();

  bool _thinking = false;
  bool _listening = false;
  bool _speechAvailable = false;
  bool _speakReplies = true;
  double? _todayUsd;
  double? _capUsd;

  static const _suggestions = [
    'Where is my next flight right now?',
    "What's the weather at my destination?",
    'Any news near my destination today?',
    'How many planes are flying near London?',
  ];

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechAvailable = ok);
    } catch (_) {
      // No recogniser on this platform; typing still works.
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _thinking) return;
    _input.clear();
    setState(() {
      _turns.add(AssistantTurn(true, question));
      _thinking = true;
    });
    _scrollToEnd();

    final reply = await AssistantService.instance.ask(_turns);
    if (!mounted) return;
    setState(() {
      _thinking = false;
      _todayUsd = reply.todayUsd ?? _todayUsd;
      _capUsd = reply.capUsd ?? _capUsd;
      if (reply.text != null) {
        _turns.add(AssistantTurn(false, reply.text!));
      } else {
        // Keep the question out of history so a retry isn't a duplicate turn.
        _turns.removeLast();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reply.error ?? 'Something went wrong.')));
      }
    });
    _scrollToEnd();
    if (reply.text != null && _speakReplies) await _tts.speak(reply.text!);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    await _tts.stop();
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(listenMode: ListenMode.confirmation, partialResults: true),
      onResult: (result) {
        setState(() => _input.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _listening = false);
          _send(result.recognizedWords);
        }
      },
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight assistant'),
        actions: [
          IconButton(
            tooltip: _speakReplies ? 'Mute spoken replies' : 'Speak replies',
            icon: Icon(_speakReplies ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() => _speakReplies = !_speakReplies);
              if (!_speakReplies) _tts.stop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_todayUsd != null && _capUsd != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_todayUsd! / _capUsd!).clamp(0, 1),
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHigh,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Today \$${_todayUsd!.toStringAsFixed(2)} of \$${_capUsd!.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _turns.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Icon(Icons.flight_takeoff, size: 40, color: cs.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Ask about your flights, weather, traffic or news. Answers come from live data.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 15, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      for (final s in _suggestions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(onPressed: () => _send(s), child: Text(s)),
                        ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _turns.length + (_thinking ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _turns.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      final t = _turns[i];
                      return Align(
                        alignment: t.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: t.fromUser ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: SelectableText(t.text, style: const TextStyle(fontSize: 14, height: 1.35)),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  if (_speechAvailable)
                    IconButton.filledTonal(
                      tooltip: _listening ? 'Stop listening' : 'Speak',
                      icon: Icon(_listening ? Icons.stop : Icons.mic),
                      onPressed: _thinking ? null : _toggleListening,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_thinking,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: _listening ? 'Listening…' : 'Ask about a flight',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    icon: const Icon(Icons.send),
                    onPressed: _thinking ? null : () => _send(_input.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
