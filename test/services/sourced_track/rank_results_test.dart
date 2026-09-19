import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

void main() {
  SpotubeFullTrackObject createTrack({
    String id = 'track_1',
    String name = 'Blinding Lights',
    List<String> artists = const ['The Weeknd'],
    int durationMs = 200000,
  }) {
    return SpotubeTrackObject.full(
      id: id,
      name: name,
      externalUri: 'https://open.spotify.com/track/$id',
      artists: artists
          .map(
            (a) => SpotubeSimpleArtistObject(
              id: a,
              name: a,
              externalUri: 'https://open.spotify.com/artist/$a',
            ),
          )
          .toList(),
      album: SpotubeSimpleAlbumObject(
        id: 'album_1',
        name: 'After Hours',
        externalUri: 'https://open.spotify.com/album/1',
        artists: [],
        albumType: SpotubeAlbumType.album,
      ),
      durationMs: durationMs,
      isrc: 'USUM71920803',
      explicit: false,
    ) as SpotubeFullTrackObject;
  }

  SpotubeAudioSourceMatchObject createCandidate({
    required String id,
    required String title,
    List<String> artists = const ['The Weeknd'],
    Duration duration = const Duration(seconds: 200),
    String uri = 'https://youtube.com/watch?v=mock',
  }) {
    return SpotubeAudioSourceMatchObject(
      id: id,
      title: title,
      artists: artists,
      duration: duration,
      externalUri: uri,
    );
  }

  group('SourcedTrack.rankResults', () {
    test('exact title match ranks above non-exact candidates', () {
      final track = createTrack(name: 'Blinding Lights', artists: ['The Weeknd'], durationMs: 200000);

      final exactMatch = createCandidate(
        id: 'exact',
        title: 'Blinding Lights',
        artists: ['The Weeknd'],
        duration: const Duration(seconds: 200),
      );
      final weakerMatch = createCandidate(
        id: 'weaker',
        title: 'Blinding Lights (Live at the Super Bowl)',
        artists: ['The Weeknd'],
        duration: const Duration(seconds: 200),
      );

      final ranked = SourcedTrack.rankResults([weakerMatch, exactMatch], track);

      expect(ranked.first.id, equals('exact'));
      expect(ranked.last.id, equals('weaker'));
    });

    test('artist match contributes positively to ranking', () {
      final track = createTrack(name: 'Starboy', artists: ['The Weeknd'], durationMs: 230000);

      // Both have same title and duration outside 5s delta, but one matches the artist.
      final withArtist = createCandidate(
        id: 'with_artist',
        title: 'Starboy Remix',
        artists: ['The Weeknd'],
        duration: const Duration(seconds: 250),
      );
      final withoutArtist = createCandidate(
        id: 'without_artist',
        title: 'Starboy Remix',
        artists: ['Random Uploader'],
        duration: const Duration(seconds: 250),
      );

      final ranked = SourcedTrack.rankResults([withoutArtist, withArtist], track);

      expect(ranked.first.id, equals('with_artist'));
      expect(ranked.last.id, equals('without_artist'));
    });

    test('duration closeness within 5 seconds contributes positively to ranking', () {
      final track = createTrack(name: 'Shape of You', artists: ['Ed Sheeran'], durationMs: 233000);

      // Both have identical fuzzy title similarity and artist, but one is within 5s of 233s.
      final closeDuration = createCandidate(
        id: 'close_duration',
        title: 'Shape of You Acoustic',
        artists: ['Ed Sheeran'],
        duration: const Duration(seconds: 235), // delta: 2s (<= 5s)
      );
      final farDuration = createCandidate(
        id: 'far_duration',
        title: 'Shape of You Acoustic',
        artists: ['Ed Sheeran'],
        duration: const Duration(seconds: 260), // delta: 27s (> 5s)
      );

      final ranked = SourcedTrack.rankResults([farDuration, closeDuration], track);

      expect(ranked.first.id, equals('close_duration'));
      expect(ranked.last.id, equals('far_duration'));
    });

    test('official music title regex match contributes positively to ranking', () {
      final track = createTrack(name: 'Levitating', artists: ['Dua Lipa'], durationMs: 203000);

      // Both have equal length/fuzzy similarity and equal duration (> 5s delta), but one matches official regex.
      final officialCandidate = createCandidate(
        id: 'official',
        title: 'Levitating (Official Audio)',
        artists: ['Dua Lipa'],
        duration: const Duration(seconds: 230),
      );
      final nonOfficialCandidate = createCandidate(
        id: 'non_official',
        title: 'Levitating (Extended Audio)',
        artists: ['Dua Lipa'],
        duration: const Duration(seconds: 230),
      );

      final ranked = SourcedTrack.rankResults([nonOfficialCandidate, officialCandidate], track);

      expect(ranked.first.id, equals('official'));
      expect(ranked.last.id, equals('non_official'));
    });

    test('fuzzy title similarity distinguishes candidates with varying title closeness', () {
      final track = createTrack(name: 'Bohemian Rhapsody', artists: ['Queen'], durationMs: 354000);

      final highSimilarity = createCandidate(
        id: 'high_sim',
        title: 'Bohemian Rhapsody 2011 Remaster',
        artists: ['Queen'],
        duration: const Duration(seconds: 400),
      );
      final lowSimilarity = createCandidate(
        id: 'low_sim',
        title: 'Bohemian Dance Remix 2024 Version',
        artists: ['Queen'],
        duration: const Duration(seconds: 400),
      );

      final ranked = SourcedTrack.rankResults([lowSimilarity, highSimilarity], track);

      expect(ranked.first.id, equals('high_sim'));
      expect(ranked.last.id, equals('low_sim'));
    });

    test('comprehensive scenario sorts candidates by overall match strength and places best match at index 0', () {
      final track = createTrack(
        name: 'Someone Like You',
        artists: ['Adele'],
        durationMs: 285000,
      );

      final candidate1Perfect = createCandidate(
        id: 'cand_1_perfect',
        title: 'Someone Like You',
        artists: ['Adele'],
        duration: const Duration(seconds: 285),
      );
      final candidate2High = createCandidate(
        id: 'cand_2_high',
        title: 'Someone Like You',
        artists: ['Adele'],
        duration: const Duration(seconds: 330),
      );
      final candidate3Medium = createCandidate(
        id: 'cand_3_medium',
        title: 'Someone Like You (Live from Royal Albert Hall)',
        artists: ['Adele'],
        duration: const Duration(seconds: 285),
      );
      final candidate4Low = createCandidate(
        id: 'cand_4_low',
        title: 'Someone Like You (Acoustic Cover)',
        artists: ['Independent Singer'],
        duration: const Duration(seconds: 285),
      );
      final candidate5Irrelevant = createCandidate(
        id: 'cand_5_irrelevant',
        title: 'Rolling in the Deep',
        artists: ['Other Artist'],
        duration: const Duration(seconds: 228),
      );

      // Scramble input order
      final scrambled = [
        candidate5Irrelevant,
        candidate3Medium,
        candidate1Perfect,
        candidate4Low,
        candidate2High,
      ];

      final ranked = SourcedTrack.rankResults(scrambled, track);

      expect(ranked.length, equals(5));
      expect(ranked[0].id, equals('cand_1_perfect'));
      expect(ranked[1].id, equals('cand_2_high'));
      expect(ranked[2].id, equals('cand_3_medium'));
      expect(ranked[3].id, equals('cand_4_low'));
      expect(ranked[4].id, equals('cand_5_irrelevant'));
    });
  });
}
