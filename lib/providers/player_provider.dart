import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/segment.dart';
import '../services/audio_player_service.dart';

class PlayerProvider extends ChangeNotifier {
  PlayerProvider({AudioPlayerService? audioPlayerService})
      : _audioPlayerService = audioPlayerService ?? AudioPlayerService() {
    _positionSubscription =
        _audioPlayerService.positionStream.listen(_onPositionTick);

    _stateSubscription = _audioPlayerService.stateStream.listen((state) {
      isPlaying = state.playing;
      notifyListeners();
    });
  }

  final AudioPlayerService _audioPlayerService;

  Map<String, bool> stemMuteState = {};
  Map<String, double> stemVolumeState = {};
  Duration currentPosition = Duration.zero;
  bool isPlaying = false;
  String? activeStemId;
  Segment? playbackSegment;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;

  static const String structureMasterStemId = 'structure_master';

  AudioPlayerService get audioPlayerService => _audioPlayerService;

  void registerStem(String stemId, {double volume = 1.0, bool muted = false}) {
    stemMuteState[stemId] = muted;
    stemVolumeState[stemId] = volume;
    notifyListeners();
  }

  void loadStem(String path, String stemId) {
    registerStem(stemId);
    _audioPlayerService.loadStem(path, stemId);
    _audioPlayerService.setStemVolume(stemId, stemVolumeState[stemId] ?? 1.0);
    _audioPlayerService.setStemMute(stemId, stemMuteState[stemId] ?? false);
  }

  Future<void> loadStemAsync(String path, String stemId) async {
    registerStem(stemId);
    await _audioPlayerService.loadStemAndWait(path, stemId);
    await _audioPlayerService.setStemVolumeAndWait(
      stemId,
      stemVolumeState[stemId] ?? 1.0,
    );
    await _audioPlayerService.setStemMuteAndWait(
      stemId,
      stemMuteState[stemId] ?? false,
    );
  }

  void toggleMute(String stemId) {
    final muted = !(stemMuteState[stemId] ?? false);
    stemMuteState[stemId] = muted;
    _audioPlayerService.setStemMute(stemId, muted);
    notifyListeners();
  }

  void setVolume(String stemId, double vol) {
    final volume = vol.clamp(0.0, 1.0);
    stemVolumeState[stemId] = volume;
    _audioPlayerService.setStemVolume(stemId, volume);
    notifyListeners();
  }

  Future<void> toggleStem(String stemId) async {
    if (!_audioPlayerService.hasStem(stemId)) {
      if (kDebugMode) {
        debugPrint('[PlayerProvider] toggleStem skipped — $stemId not loaded');
      }
      return;
    }

    if (activeStemId == stemId && isPlaying) {
      pause();
      return;
    }

    if (activeStemId == stemId && !isPlaying) {
      playbackSegment = null;
      await _audioPlayerService.playExclusive(stemId);
      isPlaying = true;
      notifyListeners();
      return;
    }

    await soloStem(stemId);
  }

  Future<void> soloStem(String stemId) async {
    if (!_audioPlayerService.hasStem(stemId)) {
      if (kDebugMode) {
        debugPrint('[PlayerProvider] soloStem skipped — $stemId not loaded');
      }
      return;
    }

    playbackSegment = null;
    activeStemId = stemId;

    for (final id in _audioPlayerService.loadedStemIds) {
      final shouldMute = id != stemId;
      stemMuteState[id] = shouldMute;
      await _audioPlayerService.setStemMuteAndWait(id, shouldMute);
    }

    stemMuteState[stemId] = false;
    await _audioPlayerService.setStemMuteAndWait(stemId, false);
    await _audioPlayerService.setStemVolumeAndWait(
      stemId,
      stemVolumeState[stemId] ?? 1.0,
    );

    await _audioPlayerService.playExclusive(stemId);
    isPlaying = true;
    notifyListeners();
  }

  bool isStemReady(String stemId) => _audioPlayerService.hasStem(stemId);

  void playAll() {
    playbackSegment = null;
    activeStemId = null;

    for (final id in stemMuteState.keys.toList()) {
      stemMuteState[id] = false;
      _audioPlayerService.setStemMute(id, false);
      _audioPlayerService.setStemVolume(id, stemVolumeState[id] ?? 1.0);
    }

    _audioPlayerService.syncAllStems();
    isPlaying = true;
    notifyListeners();
  }

  /// Play only [segment] — seeks to start and stops at end.
  void playStructureSegment(Segment segment) {
    playbackSegment = segment;
    activeStemId = null;

    for (final id in stemMuteState.keys.toList()) {
      stemMuteState[id] = false;
      _audioPlayerService.setStemMute(id, false);
      _audioPlayerService.setStemVolume(id, stemVolumeState[id] ?? 1.0);
    }

    final start = Duration(
      milliseconds: (segment.startSeconds * 1000).round(),
    );
    _audioPlayerService.seekTo(start);
    currentPosition = start;

    if (stemMuteState.containsKey(structureMasterStemId)) {
      _audioPlayerService.play(structureMasterStemId);
    } else {
      _audioPlayerService.syncAllStems();
    }

    isPlaying = true;
    notifyListeners();
  }

  void pause() {
    _audioPlayerService.pauseAll();
    isPlaying = false;
    notifyListeners();
  }

  void clearPlaybackSegment() {
    playbackSegment = null;
    notifyListeners();
  }

  void _onPositionTick(Duration position) {
    currentPosition = position;

    final segment = playbackSegment;
    if (segment != null && isPlaying) {
      final endMs = (segment.endSeconds * 1000).round();
      if (position.inMilliseconds >= endMs) {
        unawaited(_stopAtSegmentEnd(segment));
        return;
      }
    }

    notifyListeners();
  }

  Future<void> _stopAtSegmentEnd(Segment segment) async {
    final end = Duration(milliseconds: (segment.endSeconds * 1000).round());
    _audioPlayerService.pauseAll();
    _audioPlayerService.seekTo(end);
    currentPosition = end;
    isPlaying = false;
    notifyListeners();
  }

  void seek(Duration pos) {
    currentPosition = pos;
    _audioPlayerService.seekTo(pos);
    notifyListeners();
  }

  double playbackSpeed = 1.0;
  bool soloModeEnabled = false;

  void setPlaybackSpeed(double speed) {
    playbackSpeed = speed;
    _audioPlayerService.setSpeed(speed);
    notifyListeners();
  }

  void toggleSoloMode() {
    soloModeEnabled = !soloModeEnabled;
    if (!soloModeEnabled && activeStemId != null) {
      playAll();
    }
    notifyListeners();
  }

  void togglePlayPause({Segment? segment}) {
    if (isPlaying) {
      pause();
      return;
    }

    if (segment != null) {
      playStructureSegment(segment);
      return;
    }

    if (playbackSegment != null) {
      playStructureSegment(playbackSegment!);
      return;
    }

    playAll();
  }

  void reset() {
    unawaited(resetAsync());
  }

  Future<void> resetAsync() async {
    await _audioPlayerService.clearAllPlayers();
    activeStemId = null;
    playbackSegment = null;
    stemMuteState = {};
    stemVolumeState = {};
    currentPosition = Duration.zero;
    isPlaying = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    unawaited(_audioPlayerService.dispose());
    super.dispose();
  }
}
