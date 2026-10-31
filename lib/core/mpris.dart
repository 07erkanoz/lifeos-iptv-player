import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

/// The player shown to the desktop over MPRIS (Linux): what plays (its title
/// and picture), whether it plays, and play / pause / seek from outside —
/// LifeOS Ada's media, the media keys, KDE's media controls. Nothing runs when
/// no player is open; on other platforms this does nothing.
class Mpris {
  Mpris._();
  static final Mpris instance = Mpris._();

  static const _name = 'org.mpris.MediaPlayer2.lifeostv';
  static const _root = 'org.mpris.MediaPlayer2';
  static const _player = 'org.mpris.MediaPlayer2.Player';

  DBusClient? _client;
  _MprisObject? _object;
  Future<void>? _starting;

  /// A player opened: it is announced.
  Future<void> attach({
    required String title,
    String? artUrl,
    required bool live,
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function() stop,
    required Future<void> Function(Duration to) seek,
    required Duration Function() position,
    required Duration Function() duration,
  }) async {
    if (!Platform.isLinux) return;
    await (_starting ??= _start());
    final object = _object;
    if (object == null) return;
    object
      ..title = title
      ..artUrl = artUrl ?? ''
      ..live = live
      ..onPlay = play
      ..onPause = pause
      ..onStop = stop
      ..onSeek = seek
      ..position = position
      ..duration = duration
      ..status = 'Playing'
      ..attached = true;
    unawaited(object.announce());
  }

  /// Playing or paused now.
  void playing(bool playing) {
    final object = _object;
    if (object == null || !object.attached) return;
    final status = playing ? 'Playing' : 'Paused';
    if (status == object.status) return;
    object.status = status;
    unawaited(object.announce());
  }

  /// The player closed: nothing plays any more.
  void detach() {
    final object = _object;
    if (object == null || !object.attached) return;
    object
      ..attached = false
      ..status = 'Stopped'
      ..title = ''
      ..artUrl = '';
    unawaited(object.announce());
  }

  Future<void> _start() async {
    try {
      final client = DBusClient.session();
      final object = _MprisObject();
      await client.registerObject(object);
      await client.requestName(_name, flags: {DBusRequestNameFlag.doNotQueue});
      _client = client;
      _object = object;
    } catch (_) {
      _client = null; // no session bus (a TV box, a test): no MPRIS
    }
  }
}

class _MprisObject extends DBusObject {
  _MprisObject() : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  bool attached = false;
  String title = '';
  String artUrl = '';
  bool live = false;
  String status = 'Stopped';
  Future<void> Function()? onPlay, onPause, onStop;
  Future<void> Function(Duration)? onSeek;
  Duration Function() position = () => Duration.zero;
  Duration Function() duration = () => Duration.zero;

  DBusValue get _metadata {
    final values = <DBusValue, DBusValue>{
      const DBusString('mpris:trackid'):
          DBusVariant(DBusObjectPath('/tr/lifeos/tv/item')),
    };
    if (title.isNotEmpty) {
      values[const DBusString('xesam:title')] = DBusVariant(DBusString(title));
      values[const DBusString('xesam:artist')] =
          DBusVariant(DBusArray.string([live ? 'Canlı yayın' : 'LifeOS TV']));
    }
    if (artUrl.isNotEmpty) {
      values[const DBusString('mpris:artUrl')] = DBusVariant(DBusString(artUrl));
    }
    final length = duration();
    if (!live && length > Duration.zero) {
      values[const DBusString('mpris:length')] =
          DBusVariant(DBusInt64(length.inMicroseconds));
    }
    return DBusDict(DBusSignature('s'), DBusSignature('v'), values);
  }

  Map<String, DBusValue> _rootProperties() => {
        'CanQuit': const DBusBoolean(false),
        'CanRaise': const DBusBoolean(false),
        'HasTrackList': const DBusBoolean(false),
        'Identity': const DBusString('LifeOS TV'),
        'DesktopEntry': const DBusString('com.lifeostv.lifeostv'),
        'SupportedUriSchemes': DBusArray.string(const []),
        'SupportedMimeTypes': DBusArray.string(const []),
      };

  Map<String, DBusValue> _playerProperties() => {
        'PlaybackStatus': DBusString(status),
        'Metadata': _metadata,
        'Position': DBusInt64(attached ? position().inMicroseconds : 0),
        'Rate': const DBusDouble(1),
        'MinimumRate': const DBusDouble(1),
        'MaximumRate': const DBusDouble(1),
        'Volume': const DBusDouble(1),
        'CanGoNext': const DBusBoolean(false),
        'CanGoPrevious': const DBusBoolean(false),
        'CanPlay': DBusBoolean(attached),
        'CanPause': DBusBoolean(attached),
        'CanSeek': DBusBoolean(attached && !live),
        'CanControl': const DBusBoolean(true),
      };

  Future<void> announce() async {
    try {
      await emitPropertiesChanged(Mpris._player, changedProperties: {
        'PlaybackStatus': DBusString(status),
        'Metadata': _metadata,
        'CanPlay': DBusBoolean(attached),
        'CanPause': DBusBoolean(attached),
        'CanSeek': DBusBoolean(attached && !live),
      });
    } catch (_) {}
  }

  // What the object offers, for tools that ask first (qdbus, KDE's media controls).
  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectProperty p(String name, String signature,
            [DBusPropertyAccess access = DBusPropertyAccess.read]) =>
        DBusIntrospectProperty(name, DBusSignature(signature), access: access);
    DBusIntrospectMethod m(String name, [List<DBusIntrospectArgument> args = const []]) =>
        DBusIntrospectMethod(name, args: args);
    return [
      DBusIntrospectInterface(Mpris._root, methods: [m('Raise'), m('Quit')], properties: [
        p('CanQuit', 'b'), p('CanRaise', 'b'), p('HasTrackList', 'b'), p('Identity', 's'),
        p('DesktopEntry', 's'), p('SupportedUriSchemes', 'as'), p('SupportedMimeTypes', 'as'),
      ]),
      DBusIntrospectInterface(Mpris._player, methods: [
        m('Play'), m('Pause'), m('PlayPause'), m('Stop'), m('Next'), m('Previous'),
        m('Seek', [DBusIntrospectArgument(DBusSignature('x'), DBusArgumentDirection.in_, name: 'Offset')]),
        m('SetPosition', [
          DBusIntrospectArgument(DBusSignature('o'), DBusArgumentDirection.in_, name: 'TrackId'),
          DBusIntrospectArgument(DBusSignature('x'), DBusArgumentDirection.in_, name: 'Position'),
        ]),
      ], properties: [
        p('PlaybackStatus', 's'), p('Metadata', 'a{sv}'), p('Position', 'x'), p('Rate', 'd'),
        p('MinimumRate', 'd'), p('MaximumRate', 'd'), p('Volume', 'd'), p('CanGoNext', 'b'),
        p('CanGoPrevious', 'b'), p('CanPlay', 'b'), p('CanPause', 'b'), p('CanSeek', 'b'), p('CanControl', 'b'),
      ], signals: [
        DBusIntrospectSignal('Seeked', args: [DBusIntrospectArgument(DBusSignature('x'), DBusArgumentDirection.out, name: 'Position')]),
      ]),
    ];
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final values = interface == Mpris._root
        ? _rootProperties()
        : interface == Mpris._player
            ? _playerProperties()
            : null;
    final value = values?[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface == Mpris._root) return DBusGetAllPropertiesResponse(_rootProperties());
    if (interface == Mpris._player) return DBusGetAllPropertiesResponse(_playerProperties());
    return DBusGetAllPropertiesResponse(const {});
  }

  @override
  Future<DBusMethodResponse> setProperty(String interface, String name, DBusValue value) async =>
      DBusMethodErrorResponse.propertyReadOnly();

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == Mpris._root) {
      return DBusMethodSuccessResponse(); // Raise, Quit: not offered
    }
    if (methodCall.interface != Mpris._player) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (!attached) return DBusMethodSuccessResponse();
    switch (methodCall.name) {
      case 'Play':
        await onPlay?.call();
      case 'Pause':
        await onPause?.call();
      case 'PlayPause':
        await (status == 'Playing' ? onPause : onPlay)?.call();
      case 'Stop':
        await onStop?.call();
      case 'Seek':
        if (!live && methodCall.values.isNotEmpty) {
          final offset = (methodCall.values.first as DBusInt64).value;
          await onSeek?.call(position() + Duration(microseconds: offset));
        }
      case 'SetPosition':
        if (!live && methodCall.values.length > 1) {
          await onSeek?.call(Duration(microseconds: (methodCall.values[1] as DBusInt64).value));
        }
      default:
        break; // Next, Previous, OpenUri: not offered
    }
    return DBusMethodSuccessResponse();
  }
}
