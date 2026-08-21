enum PlaybackState { idle, preparing, playing, paused, ended, failed }

abstract interface class PlaybackGateway {
  Stream<PlaybackState> get state;
  Future<void> open(Uri authorizedMediaUri);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
}
