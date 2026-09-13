import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/playbutton_view/playbutton_card.dart';
import 'package:spotube/components/playbutton_view/playbutton_tile.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/services/audio_player/audio_player.dart';

class TrackCard extends HookConsumerWidget {
  final SpotubeTrackObject track;
  final bool _isTile;

  const TrackCard(
    this.track, {
    super.key,
  }) : _isTile = false;

  const TrackCard.tile(
    this.track, {
    super.key,
  }) : _isTile = true;

  @override
  Widget build(BuildContext context, ref) {
    final playlist = ref.watch(audioPlayerProvider);
    final playing =
        useStream(audioPlayer.playingStream).data ?? audioPlayer.isPlaying;
    final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
    final historyNotifier = ref.read(playbackHistoryActionsProvider);
    final isFetchingActiveTrack = ref.watch(queryingTrackInfoProvider);

    final isTrackPlaying = playlist.activeTrack?.id == track.id;
    final isLoading = isTrackPlaying && isFetchingActiveTrack;

    final imageUrl = useMemoized(
      () => track.album.images.from200PxTo300PxOrSmallestImage(
        ImagePlaceholder.albumArt,
      ),
      [track.album.images],
    );

    final onTap = useCallback(() {
      context.navigateTo(TrackRoute(trackId: track.id));
    }, [context, track.id]);

    final onPlaybuttonPressed = useCallback(() async {
      if (isTrackPlaying) {
        return playing ? audioPlayer.pause() : audioPlayer.resume();
      }

      await playlistNotifier.load([track], autoPlay: true);
      historyNotifier.addTrack(track);
    }, [isTrackPlaying, playing, playlistNotifier, track, historyNotifier]);

    final onAddToQueuePressed = useCallback(() {
      playlistNotifier.addTracks([track]);
      historyNotifier.addTrack(track);
      if (context.mounted) {
        showToast(
          context: context,
          builder: (context, overlay) {
            return SurfaceCard(
              child: Basic(
                content: Text(
                  context.l10n.added_to_queue(1),
                ),
                trailing: Button.outline(
                  child: Text(context.l10n.undo),
                  onPressed: () {
                    playlistNotifier.removeTracks([track.id]);
                  },
                ),
              ),
            );
          },
        );
      }
    }, [playlistNotifier, track, historyNotifier, context]);

    final description = track.artists.asString();

    if (_isTile) {
      return PlaybuttonTile(
        imageUrl: imageUrl,
        isPlaying: isTrackPlaying && playing,
        isLoading: isLoading,
        title: track.name,
        description: description,
        onTap: onTap,
        onPlaybuttonPressed: onPlaybuttonPressed,
        onAddToQueuePressed: onAddToQueuePressed,
      );
    }

    return PlaybuttonCard(
      imageUrl: imageUrl,
      isPlaying: isTrackPlaying && playing,
      isLoading: isLoading,
      title: track.name,
      description: description,
      onTap: onTap,
      onPlaybuttonPressed: onPlaybuttonPressed,
      onAddToQueuePressed: onAddToQueuePressed,
    );
  }
}
