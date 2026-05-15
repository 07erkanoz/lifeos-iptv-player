import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/data/services/subtitle_track_matcher.dart';

TrackCandidate _t(String id, {String? language, String? title}) =>
    (id: id, language: language, title: title);

void main() {
  group('findBestSubtitleTrack — empty inputs', () {
    test('no remembered preference → no match', () {
      final tracks = [_t('1', language: 'eng', title: 'English')];
      expect(
        findBestSubtitleTrack(tracks: tracks),
        isNull,
      );
    });

    test('empty string inputs counted as no preference', () {
      final tracks = [_t('1', language: 'eng')];
      expect(
        findBestSubtitleTrack(
          tracks: tracks,
          wantLanguage: '',
          wantTitle: '   ',
        ),
        isNull,
      );
    });

    test('no real tracks (only auto / no) → no match', () {
      final tracks = [_t('auto'), _t('no')];
      expect(
        findBestSubtitleTrack(tracks: tracks, wantLanguage: 'eng'),
        isNull,
      );
    });
  });

  group('findBestSubtitleTrack — exact language match', () {
    test('case-insensitive language hit beats anything else', () {
      final tracks = [
        _t('1', language: 'fra', title: 'French'),
        _t('2', language: 'TR', title: 'Türkçe'),
        _t('3', language: 'eng', title: 'English'),
      ];
      final match = findBestSubtitleTrack(
        tracks: tracks,
        wantLanguage: 'tr',
      );
      expect(match?.id, '2');
    });

    test('whitespace in stored preference is trimmed', () {
      final tracks = [_t('1', language: 'eng')];
      final match = findBestSubtitleTrack(
        tracks: tracks,
        wantLanguage: '  eng  ',
      );
      expect(match?.id, '1');
    });
  });

  group('findBestSubtitleTrack — title fallback', () {
    test(
      'when only title was remembered, finds a track with matching title',
      () {
        final tracks = [
          _t('1', language: 'eng', title: 'English (forced)'),
          _t('2', language: null, title: 'Türkçe Altyazı'),
          _t('3', language: 'fra', title: 'French'),
        ];
        final match = findBestSubtitleTrack(
          tracks: tracks,
          wantTitle: 'Türkçe Altyazı',
        );
        expect(match?.id, '2');
      },
    );

    test('partial title match works in either direction', () {
      final tracks = [
        _t('1', language: 'eng', title: 'English (forced)'),
        _t('2', language: 'eng', title: 'English (SDH)'),
      ];
      // User remembered "English (forced)" from a previous episode;
      // new episode only has "English (SDH)" — exact match fails but
      // substring fallback should at least pick an English track.
      final match = findBestSubtitleTrack(
        tracks: tracks,
        wantTitle: 'English',
      );
      // We expect _some_ English track via substring; either is acceptable
      // and we just verify a real subtitle is picked, not null.
      expect(match, isNotNull);
      expect(['1', '2'], contains(match!.id));
    });
  });

  group('findBestSubtitleTrack — cross-field fallback', () {
    test(
      'old track stored its label in title but new track has it as language',
      () {
        // Episode 1: subtitle exposed as title="Turkish" (no language).
        // Saved → wantTitle = "Turkish".
        // Episode 2: same subtitle exposed as language="turkish",
        // no title.
        final tracks = [
          _t('1', language: 'eng'),
          _t('2', language: 'turkish'),
        ];
        final match = findBestSubtitleTrack(
          tracks: tracks,
          wantTitle: 'Turkish',
        );
        expect(match?.id, '2');
      },
    );

    test(
      'old track stored its label in language but new track has it as title',
      () {
        final tracks = [
          _t('1', title: 'English'),
          _t('2', title: 'Türkçe'),
        ];
        final match = findBestSubtitleTrack(
          tracks: tracks,
          wantLanguage: 'Türkçe',
        );
        expect(match?.id, '2');
      },
    );
  });

  group('findBestSubtitleTrack — language prefix variants', () {
    test('"tr" remembered, "tur" available → match', () {
      final tracks = [
        _t('1', language: 'eng'),
        _t('2', language: 'tur'),
      ];
      final match = findBestSubtitleTrack(
        tracks: tracks,
        wantLanguage: 'tr',
      );
      expect(match?.id, '2');
    });

    test('"tur" remembered, "tr" available → match', () {
      final tracks = [
        _t('1', language: 'tr'),
        _t('2', language: 'eng'),
      ];
      final match = findBestSubtitleTrack(
        tracks: tracks,
        wantLanguage: 'tur',
      );
      expect(match?.id, '1');
    });
  });

  group('findBestSubtitleTrack — synthetic tracks ignored', () {
    test('"no" and "auto" never match even with empty real tracks', () {
      final tracks = [
        _t('no', language: 'no'),
        _t('auto', language: 'auto'),
      ];
      expect(
        findBestSubtitleTrack(tracks: tracks, wantLanguage: 'no'),
        isNull,
      );
    });

    test('synthetic tracks coexisting with real tracks → real track wins', () {
      final tracks = [
        _t('no'),
        _t('auto'),
        _t('1', language: 'tr'),
      ];
      final match = findBestSubtitleTrack(
        tracks: tracks,
        wantLanguage: 'tr',
      );
      expect(match?.id, '1');
    });
  });

  group('findBestSubtitleTrack — no plausible match', () {
    test('completely unrelated language → null (caller leaves default)', () {
      final tracks = [
        _t('1', language: 'eng'),
        _t('2', language: 'fra'),
      ];
      final match = findBestSubtitleTrack(
        tracks: tracks,
        wantLanguage: 'jpn',
        wantTitle: '日本語',
      );
      expect(match, isNull);
    });
  });
}
