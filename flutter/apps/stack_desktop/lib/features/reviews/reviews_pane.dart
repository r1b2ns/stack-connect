import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';
import '../shell/selection.dart';

/// Detail pane: Ratings & Reviews for the selected (account, app).
///
/// Lists reviews with the developer response when present. A per-review Reply
/// command opens a Fluent [ContentDialog]; submitting calls
/// `ReviewsController.reply`, which invalidates and re-fetches so the response
/// appears. Errors surface through an [InfoBar].
class ReviewsPane extends ConsumerWidget {
  const ReviewsPane({
    required this.accountId,
    required this.appId,
    super.key,
  });

  final String accountId;
  final String appId;

  ReviewsKey get _key => (accountId: accountId, appId: appId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reviewsControllerProvider(_key));
    final selection = ref.read(selectionControllerProvider.notifier);
    final l10n = AppLocalizations.of(context)!;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(l10n.ratingsAndReviews),
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () =>
              selection.openAppDetail(appId),
        ),
      ),
      content: reviews.when(
        loading: () => const Center(child: ProgressRing()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: InfoBar(
              title: Text(l10n.couldNotLoadReviews),
              content: Text(stackErrorMessage(error)),
              severity: InfoBarSeverity.error,
            ),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noReviewsYet))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ReviewCard(
                    review: items[index],
                    reviewsKey: _key,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.review, required this.reviewsKey});

  final CustomerReview review;
  final ReviewsKey reviewsKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typography = FluentTheme.of(context).typography;
    final l10n = AppLocalizations.of(context)!;
    final response = review.response;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StarRating(rating: review.rating),
          if (review.title != null && review.title!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.title!, style: typography.bodyStrong),
          ],
          if (review.body != null && review.body!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.body!),
          ],
          const SizedBox(height: 8),
          Text(_byline(review), style: typography.caption),
          if (response != null) ...[
            const SizedBox(height: 12),
            _DeveloperResponse(response: response),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Button(
              onPressed: () => _openReplyDialog(context, ref, response),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.reply),
                  const SizedBox(width: 6),
                  Text(response == null ? l10n.replyAction : l10n.editReplyAction),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _byline(CustomerReview review) {
    final parts = <String>[
      if (review.reviewerNickname != null &&
          review.reviewerNickname!.isNotEmpty)
        review.reviewerNickname!,
      if (review.territory != null && review.territory!.isNotEmpty)
        review.territory!,
      if (review.createdDate != null && review.createdDate!.isNotEmpty)
        review.createdDate!,
    ];
    return parts.join(' · ');
  }

  Future<void> _openReplyDialog(
    BuildContext context,
    WidgetRef ref,
    ReviewResponse? existing,
  ) async {
    final controller = TextEditingController(text: existing?.body ?? '');

    final body = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ReplyDialog(controller: controller),
    );

    if (body == null || !context.mounted) return;

    final l10n = AppLocalizations.of(context)!;
    try {
      await ref
          .read(reviewsControllerProvider(reviewsKey).notifier)
          .reply(reviewId: review.id, body: body);
      if (context.mounted) {
        await displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.replySubmitted),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        await displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.replyFailed),
            content: Text(stackErrorMessage(error)),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    }
  }
}

class _ReplyDialog extends StatelessWidget {
  const _ReplyDialog({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ContentDialog(
      title: Text(l10n.replyToReviewTitle),
      content: TextBox(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        placeholder: l10n.writeYourResponse,
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            Navigator.of(context).pop(text);
          },
          child: Text(l10n.submit),
        ),
      ],
    );
  }
}

class _DeveloperResponse extends StatelessWidget {
  const _DeveloperResponse({required this.response});

  final ReviewResponse response;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.dividerStrokeColorDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.developerResponse,
            style: theme.typography.caption
                ?.copyWith(color: theme.accentColor),
          ),
          const SizedBox(height: 4),
          Text(response.body ?? ''),
        ],
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    final clamped = rating.clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < clamped
              ? FluentIcons.favorite_star_fill
              : FluentIcons.favorite_star,
          size: 16,
          color: Colors.warningPrimaryColor,
        ),
      ),
    );
  }
}
