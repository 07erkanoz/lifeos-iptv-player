import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Thin facade over `speech_to_text` + `flutter_tts` for the
/// AI chat surface.
///
/// Platform contract:
///   * Mobile (Android + iOS) → both STT and TTS available, the
///     widgets render a mic button + speaker toggle.
///   * Desktop / TV → `available` returns false everywhere; the
///     widgets hide their controls. The service still constructs
///     cleanly so callers can `ref.read` it without platform checks.
///
/// Lifecycle: a single keep-alive instance per process. STT and TTS
/// plugins are heavy to initialise (they go through MethodChannel
/// into the OS speech subsystem) so we lazy-init on first call and
/// keep the engines warm afterwards.
class VoiceChatService {
  final stt.SpeechToText _stt;
  final FlutterTts _tts;

  bool _initialised = false;
  bool _sttAvailable = false;

  VoiceChatService(this._stt, this._tts);

  /// True when the platform supports voice chat AND the underlying
  /// engine reported itself ready. Widgets check this once on mount
  /// and bail when false.
  bool get isSupported => PlatformHelper.isMobile && _sttAvailable;

  /// Idempotent lazy init. Wraps platform-channel exceptions so a
  /// missing native plugin (e.g. desktop build) just returns false
  /// instead of crashing the chat screen.
  Future<bool> ensureInitialised() async {
    if (_initialised) return _sttAvailable;
    if (!PlatformHelper.isMobile) {
      _initialised = true;
      return false;
    }
    try {
      _sttAvailable = await _stt.initialize(
        onError: (e) => debugPrint('[voice] stt error: ${e.errorMsg}'),
        onStatus: (s) => debugPrint('[voice] stt status: $s'),
      );
      // Configure TTS defaults — language gets re-applied per call.
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
    } catch (e) {
      debugPrint('[voice] init failed: $e');
      _sttAvailable = false;
    }
    _initialised = true;
    return _sttAvailable;
  }

  /// Begin dictation. `localeId` is a BCP-47 tag (e.g. `tr_TR`,
  /// `en_US`); pass null to use the device default. The
  /// [onPartial] callback fires for every interim recognition
  /// result, [onFinal] fires once with the committed transcript
  /// when the user stops talking (or [stop] is called).
  ///
  /// Returns true if listening actually started, false when the
  /// plugin refused (no permission, no engine, etc.). Callers
  /// should surface a snackbar on false.
  Future<bool> startListening({
    String? localeId,
    required void Function(String partial) onPartial,
    required void Function(String finalText) onFinal,
  }) async {
    if (!await ensureInitialised()) return false;
    try {
      await _stt.listen(
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          // 'dictation' lets users speak longer phrases without
          // the recogniser cutting off after a short pause.
          listenMode: stt.ListenMode.dictation,
          // 60-second hard cap so a forgotten-on mic doesn't drain
          // battery indefinitely. Most chat prompts fit in 10-15s.
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 3),
          localeId: localeId,
        ),
        onResult: (r) {
          if (r.finalResult) {
            onFinal(r.recognizedWords);
          } else {
            onPartial(r.recognizedWords);
          }
        },
      );
      return _stt.isListening;
    } catch (e) {
      debugPrint('[voice] startListening failed: $e');
      return false;
    }
  }

  Future<void> stopListening() async {
    if (_stt.isListening) {
      await _stt.stop();
    }
  }

  /// Speak [text] aloud in [localeId] (BCP-47). Best-effort — if
  /// the TTS engine refuses (missing voice data, etc.) we swallow
  /// the error so the chat UX keeps working.
  Future<void> speak(String text, {String? localeId}) async {
    if (!await ensureInitialised()) return;
    if (text.trim().isEmpty) return;
    try {
      if (localeId != null) {
        // flutter_tts uses `xx-XX` not `xx_XX`. Normalise.
        await _tts.setLanguage(localeId.replaceAll('_', '-'));
      }
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[voice] speak failed: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Process-wide singleton. Constructed lazily so the
/// speech-to-text + flutter-tts MethodChannel handshakes happen
/// only when the user actually opens the AI chat. keepAlive so the
/// (warm) engines aren't torn down between sheet open/close cycles.
final voiceChatServiceProvider = Provider<VoiceChatService>((ref) {
  return VoiceChatService(stt.SpeechToText(), FlutterTts());
});
