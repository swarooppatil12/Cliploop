import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlayerService {
  AudioPlayerService();

  final Map<String, AudioPlayer> _players = {};
  final Map<String, double> _volumes = {};
  final Map<String, bool> _muted = {};
  String? _primaryStemId;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<PlayerState> get stateStream => _stateController.stream;

  void loadStem(String path, String stemId) {
    unawaited(_loadStem(path, stemId));
  }

  Future<void> loadStemAndWait(String path, String stemId) {
    return _loadStem(path, stemId);
  }

  Future<void> _loadStem(String path, String stemId) async {
    if (kDebugMode) {
      debugPrint('[AudioPlayer] loadStem id=$stemId path=$path');
    }

    try {
      final player = _players.putIfAbsent(stemId, AudioPlayer.new);
      await player.setFilePath(path);

      _volumes[stemId] = 1.0;
      _muted[stemId] = false;
      await player.setVolume(1.0);

      _primaryStemId = stemId;
      _bindPrimaryStreams(stemId);

      if (kDebugMode) {
        final duration = player.duration;
        debugPrint(
          '[AudioPlayer] loadStem ready id=$stemId duration=${duration?.inMilliseconds}ms',
        );
      }
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[AudioPlayer] loadStem FAILED id=$stemId: $error');
        debugPrint('$stack');
      }
      rethrow;
    }
  }

  void playPause(String stemId) {
    unawaited(_playPause(stemId));
  }

  Future<void> _playPause(String stemId) async {
    final player = _players[stemId];
    if (player == null) {
      return;
    }

    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
    _bindPrimaryStreams(stemId);
  }

  void seekTo(Duration position) {
    unawaited(_seekTo(position));
  }

  Future<void> _seekTo(Duration position) async {
    await Future.wait(
      _players.values.map((player) => player.seek(position)),
    );
    _positionController.add(position);
  }

  void setStemMute(String stemId, bool muted) {
    unawaited(_setStemMute(stemId, muted));
  }

  Future<void> setStemMuteAndWait(String stemId, bool muted) {
    return _setStemMute(stemId, muted);
  }

  Future<void> _setStemMute(String stemId, bool muted) async {
    _muted[stemId] = muted;
    final player = _players[stemId];
    if (player == null) {
      return;
    }
    await player.setVolume(muted ? 0 : (_volumes[stemId] ?? 1.0));
  }

  void setStemVolume(String stemId, double volume) {
    unawaited(_setStemVolume(stemId, volume));
  }

  Future<void> setStemVolumeAndWait(String stemId, double volume) {
    return _setStemVolume(stemId, volume);
  }

  Future<void> _setStemVolume(String stemId, double volume) async {
    final clampedVolume = volume.clamp(0.0, 1.0);
    _volumes[stemId] = clampedVolume;
    final player = _players[stemId];
    if (player == null || (_muted[stemId] ?? false)) {
      return;
    }
    await player.setVolume(clampedVolume);
  }

  void syncAllStems() {
    unawaited(_syncAllStems());
  }

  Future<void> play(String stemId) {
    return _playExclusive(stemId);
  }

  Future<void> playExclusive(String stemId) {
    return _playExclusive(stemId);
  }

  Future<void> pauseAll() {
    return _pauseAll();
  }

  Future<void> _playExclusive(String stemId) async {
    if (kDebugMode) {
      debugPrint('[AudioPlayer] playExclusive id=$stemId loaded=${_players.keys.toList()}');
    }

    for (final entry in _players.entries) {
      if (entry.key == stemId) {
        continue;
      }
      await entry.value.pause();
      await entry.value.setVolume(0);
      _muted[entry.key] = true;
    }

    final player = _players[stemId];
    if (player == null) {
      if (kDebugMode) {
        debugPrint('[AudioPlayer] playExclusive failed — stem not loaded: $stemId');
      }
      return;
    }

    _muted[stemId] = false;
    final volume = _volumes[stemId] ?? 1.0;
    await player.setVolume(volume);
    await player.play();
    _bindPrimaryStreams(stemId);
  }

  bool hasStem(String stemId) => _players.containsKey(stemId);

  List<String> get loadedStemIds => _players.keys.toList(growable: false);

  /// Stops and disposes every loaded stem — required before switching sources.
  Future<void> clearAllPlayers() async {
    if (kDebugMode) {
      debugPrint('[AudioPlayer] clearAllPlayers (was: ${_players.keys.toList()})');
    }

    await _positionSubscription?.cancel();
    await _stateSubscription?.cancel();
    _positionSubscription = null;
    _stateSubscription = null;

    await pauseAll();
    await Future.wait(_players.values.map((player) => player.dispose()));
    _players.clear();
    _volumes.clear();
    _muted.clear();
    _primaryStemId = null;
  }

  Future<void> _pauseAll() async {
    await Future.wait(
      _players.values.where((player) => player.playing).map((player) => player.pause()),
    );
  }

  void setSpeed(double speed) {
    unawaited(_setSpeed(speed));
  }

  Future<void> _setSpeed(double speed) async {
    final clamped = speed.clamp(0.5, 2.0);
    await Future.wait(_players.values.map((player) => player.setSpeed(clamped)));
  }

  Future<void> _syncAllStems() async {
    if (_players.isEmpty) {
      return;
    }

    final anchorPlayer = _players[_primaryStemId] ?? _players.values.first;
    final position = anchorPlayer.position;

    await Future.wait(_players.values.map((player) => player.seek(position)));
    await Future.wait(_players.values.map((player) => player.play()));
    _positionController.add(position);
  }

  Future<void> dispose() async {
    await _positionSubscription?.cancel();
    await _stateSubscription?.cancel();
    await Future.wait(_players.values.map((player) => player.dispose()));
    _players.clear();
    await _positionController.close();
    await _stateController.close();
  }

  void _bindPrimaryStreams(String stemId) {
    _primaryStemId = stemId;
    final player = _players[stemId];
    if (player == null) {
      return;
    }

    _positionSubscription?.cancel();
    _stateSubscription?.cancel();

    _positionSubscription = player.positionStream.listen(_positionController.add);
    _stateSubscription = player.playerStateStream.listen(_stateController.add);
  }
}
