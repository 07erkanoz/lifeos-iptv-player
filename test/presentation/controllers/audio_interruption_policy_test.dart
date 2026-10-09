import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/controllers/audio_interruption_policy.dart';

void main() {
  test('system permission resumes only the same previously playing source', () {
    final policy = AudioInterruptionPolicy();
    policy.begin(playing: true, source: 1, foreground: true);
    expect(policy.end(shouldResume: true, source: 1, foreground: true), true);
    policy.begin(playing: false, source: 1, foreground: true);
    expect(policy.end(shouldResume: true, source: 1, foreground: true), false);
    policy.begin(playing: true, source: 1, foreground: true);
    expect(policy.end(shouldResume: true, source: 2, foreground: true), false);
  });
  test('backgrounding, user pause and headphone unplug revoke auto resume', () {
    final policy = AudioInterruptionPolicy();
    for (var i = 0; i < 3; i++) {
      policy.begin(playing: true, source: 1, foreground: true);
      policy.revokeResume();
      expect(
        policy.end(shouldResume: true, source: 1, foreground: true),
        false,
      );
    }
    policy.begin(playing: true, source: 1, foreground: true);
    expect(policy.end(shouldResume: false, source: 1, foreground: true), false);
  });
  test('duplicate interruption starts do not forget the original state', () {
    final policy = AudioInterruptionPolicy();
    policy.begin(playing: true, source: 1, foreground: true);
    policy.begin(playing: false, source: 1, foreground: true);
    expect(policy.end(shouldResume: true, source: 1, foreground: true), true);
    expect(policy.end(shouldResume: true, source: 1, foreground: true), false);
  });
}
