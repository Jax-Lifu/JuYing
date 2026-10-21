import 'android_audio_output_test.dart' as audio;
import 'android_dex_playback_test.dart' as dex;
import 'tvbox_live_playback_test.dart' as live;
import 'web_media_resolver_test.dart' as web;

/// Packages Android acceptance in one APK so all paths use the same native host.
void main() {
  dex.main();
  audio.main();
  web.main();
  live.main();
}
