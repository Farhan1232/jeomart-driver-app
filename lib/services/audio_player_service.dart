import 'dart:async';
import 'dart:developer';

import 'package:audioplayers/audioplayers.dart';
import 'package:driver/utils/app_image_cache.dart';
import 'package:driver/utils/preferences.dart';
import 'package:flutter/foundation.dart';

class AudioPlayerService {
  static late AudioPlayer _audioPlayer;
  static bool _created = false;

  /// Creates the player once. This is also called every time the app goes to
  /// the background, and it used to replace the player each time: a ringtone
  /// playing at that moment was left looping in the old player, every later
  /// stop went to the new one, and only closing the app silenced it.
  static Future<void> initAudio() async {
    if (_created) return;
    _created = true;
    _audioPlayer = AudioPlayer(playerId: "playerId");
  }

  /// The ride-request ringtone, once a copy of it is on this phone.
  ///
  /// It used to be streamed from its URL every time a request arrived. The
  /// player has to open a connection and buffer the file before the first note
  /// plays, and Firebase Storage serves it with `max-age=0`, so nothing kept a
  /// copy - on mobile data the request sheet was on screen well before the
  /// driver heard it. It is fetched once now, when the settings arrive, and
  /// played from the file. Same sound, same loop, same volume.
  static String? _ringtoneUrl;
  static String? _ringtonePath;

  /// Keeps a copy of [url] on the device, ahead of the first request.
  ///
  /// Cheap to call again: a URL that already has a copy returns at once. A
  /// failed download only means the ringtone is streamed, as it always was.
  static Future<void> prepareRingtone(String url, {Future<String> Function(String url)? download}) async {
    if (url.isEmpty) return;
    if (url == _ringtoneUrl && _ringtonePath != null) return;
    try {
      final String path = await (download ?? _download)(url);
      _ringtoneUrl = url;
      _ringtonePath = path;
    } catch (e) {
      log('ringtone copy failed, it will be streamed :: $e');
    }
  }

  static Future<String> _download(String url) async => (await AppImageCache.manager.getSingleFile(url)).path;

  /// Where the ringtone for [url] is played from: the copy on the device when
  /// there is one, otherwise the URL itself.
  static Source ringtoneSource(String url) {
    final String? path = _ringtonePath;
    if (path != null && url == _ringtoneUrl) return DeviceFileSource(path);
    return UrlSource(url);
  }

  @visibleForTesting
  static void forgetRingtone() {
    _ringtoneUrl = null;
    _ringtonePath = null;
  }

  /// Whether the ringtone should be sounding, as of the latest call.
  ///
  /// Starting the ringtone takes a moment (the source has to be loaded), and
  /// the player still reports `stopped` while it does. A stop asked for in
  /// that moment - the driver tapping Accept, Reject or Cancel - used to be
  /// skipped because of that, and the ringtone then started anyway and kept
  /// looping. The latest call now always wins.
  static bool _wantRinging = false;

  static Future<void> playSound(bool isPlay) async {
    try {
      if (isPlay) {
        _wantRinging = true;
        if (_audioPlayer.state != PlayerState.playing) {
          final String url = Preferences.getString(Preferences.orderRingtone);
          await _audioPlayer.setSource(ringtoneSource(url));
          if (!_wantRinging) return;
          await _audioPlayer.setReleaseMode(ReleaseMode.loop);
          if (!_wantRinging) return;
          await _audioPlayer.resume();
          // Stopped while it was starting: make sure it is silent.
          if (!_wantRinging) await _audioPlayer.stop();
          // A request that arrived before the copy was made is streamed; the
          // next one plays from the device.
          unawaited(prepareRingtone(url));
        }
      } else {
        _wantRinging = false;
        await _audioPlayer.stop();
      }
    } catch (e) {
      print("Error in playSound: $e");
    }
  }
}
