import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';

/// Ratings & Reviews for a single (account, app).
///
/// Lists each review (star rating, title, body, reviewer, territory, date) and,
/// when present, the developer's response. A per-review Reply action opens a
/// Material dialog whose submit calls `ReviewsController.reply`; on success the
/// controller invalidates itself and the list re-fetches to show the response.
class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({
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
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ratingsAndReviews),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('/accounts/$accountId/apps/$appId'),
        ),
      ),
      body: reviews.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              stackErrorMessage(error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noReviewsYet))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _ReviewCard(
                  review: items[index],
                  reviewsKey: _key,
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final response = review.response;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StarRating(rating: review.rating),
            if (review.title != null && review.title!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(review.title!, style: theme.textTheme.titleMedium),
            ],
            if (review.body != null && review.body!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(review.body!),
            ],
            const SizedBox(height: 8),
            Text(
              _byline(review),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (response != null) ...[
              const SizedBox(height: 12),
              _DeveloperResponse(response: response),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.reply),
                label: Text(
                  response == null ? l10n.replyAction : l10n.editReplyAction,
                ),
                onPressed: () => _openReplyDialog(context, ref, response),
              ),
            ),
          ],
        ),
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
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final body = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ReplyDialog(controller: controller),
    );

    if (body == null) return;

    try {
      await ref
          .read(reviewsControllerProvider(reviewsKey).notifier)
          .reply(reviewId: review.id, body: body);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.replySubmittedToast)),
        );
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(stackErrorMessage(error))));
    }
  }
}

class _ReplyDialog extends StatelessWidget {
  const _ReplyDialog({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.replyToReviewTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          hintText: l10n.writeYourResponse,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.developerResponse,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.primary),
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
          i < clamped ? Icons.star : Icons.star_border,
          size: 18,
          color: Colors.amber,
        ),
      ),
    );
  }
}
