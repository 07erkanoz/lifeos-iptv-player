import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// A request from outside the app (LifeOS Ada, the desktop): play one item.
///
///     lifeos-tv --oynat live:12345     a live channel
///     lifeos-tv --oynat movie:678      a film
///     lifeos-tv --oynat series:91      a series (its page)
///
/// On Linux one copy of the app runs: a second start hands its request to the
/// running one over a local socket (`$XDG_RUNTIME_DIR/lifeos-tv.sock`) and
/// ends, and the running window comes to the front. Nothing else is accepted
/// on the socket than one such line from this user.
class PlayRequest {
  final String type; // live | movie | series
  final int streamId;
  const PlayRequest(this.type, this.streamId);

  static PlayRequest? parse(String text) {
    final parts = text.trim().split(':');
    if (parts.length != 2) return null;
    final type = parts[0];
    final id = int.tryParse(parts[1]);
    if (id == null || !const {'live', 'movie', 'series'}.contains(type)) {
      return null;
    }
    return PlayRequest(type, id);
  }

  static PlayRequest? fromArgs(List<String> args) {
    final at = args.indexOf('--oynat');
    if (at < 0 || at + 1 >= args.length) return null;
    return parse(args[at + 1]);
  }
}

class DesktopBridge {
  DesktopBridge._();

  /// The newest request; the app plays it once an account is ready.
  static final ValueNotifier<PlayRequest?> requests = ValueNotifier(null);

  static String? get _path {
    final dir = Platform.environment['XDG_RUNTIME_DIR'];
    return dir == null || dir.isEmpty ? null : '$dir/lifeos-tv.sock';
  }

  /// Another copy already runs: the request (or just "come forward") goes to
  /// it and true is returned (this copy then ends). Linux only.
  static Future<bool> handOver(List<String> args) async {
    final path = _path;
    if (!Platform.isLinux || path == null) return false;
    try {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 400),
      );
      final request = PlayRequest.fromArgs(args);
      socket.write(request == null
          ? 'goster\n'
          : 'oynat ${request.type}:${request.streamId}\n');
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {
      return false; // none runs (or a stale socket): this copy is the one
    }
  }

  /// This copy is the one: requests from later starts arrive here.
  static Future<void> listen() async {
    final path = _path;
    if (!Platform.isLinux || path == null) return;
    try {
      final stale = File(path);
      if (await stale.exists()) await stale.delete();
      final server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      server.listen((client) {
        client
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .take(1)
            .listen((line) async {
          if (line.startsWith('oynat ')) {
            final request = PlayRequest.parse(line.substring(6));
            if (request != null) requests.value = request;
          }
          try {
            await windowManager.show();
            await windowManager.focus();
          } catch (_) {}
        }, onDone: client.destroy, onError: (_) => client.destroy());
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[DesktopBridge] listen failed: $e');
    }
  }
}
