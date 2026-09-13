import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:spotube/components/horizontal_playbutton_card_view/horizontal_playbutton_card_view.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/recommendations/recommendations.dart';

class HomeRecommendedSection extends HookConsumerWidget {
  const HomeRecommendedSection({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final recommendedTracks = ref.watch(recommendedTracksProvider);
    final tracks = recommendedTracks.asData?.value ?? [];

    if (recommendedTracks.asData?.value.isEmpty == true ||
        recommendedTracks.hasError) {
      return const SizedBox.shrink();
    }

    return Skeletonizer(
      enabled: recommendedTracks.isLoading,
      child: HorizontalPlaybuttonCardView<SpotubeTrackObject>(
        title: const Text("Recommended for You"),
        items: tracks,
        hasNextPage: false,
        isLoadingNextPage: false,
        onFetchMore: () {},
      ),
    );
  }
}
