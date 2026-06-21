import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gateway/core_gateway.dart';
import 'package:stack_core_rust/stack_core_rust.dart';
import 'connected_provider.dart';

/// The (account, app) key a [ReviewsController] is scoped to.
typedef ReviewsKey = ({String accountId, String appId});

/// Customer reviews for a single (account, app), newest first.
///
/// Loads through the connected provider's Reviews handle. Replying upserts the
/// developer response and then invalidates this provider so the freshly-added
/// response is re-fetched and shown.
class ReviewsController
    extends FamilyAsyncNotifier<List<CustomerReview>, ReviewsKey> {
  @override
  Future<List<CustomerReview>> build(ReviewsKey key) async {
    final gateway = ref.read(coreGatewayProvider);
    final provider =
        await ref.read(connectedProviderProvider(key.accountId).future);

    final reviews = gateway.reviews(provider);
    if (reviews == null) {
      // The provider does not expose reviews for this account.
      return const <CustomerReview>[];
    }
    return gateway.fetchCustomerReviews(reviews, key.appId);
  }

  /// Upserts the developer response for [reviewId], then invalidates this
  /// provider so the new response shows on the next read.
  ///
  /// Returns the resulting [ReviewResponse].
  Future<ReviewResponse> reply({
    required String reviewId,
    required String body,
  }) async {
    final gateway = ref.read(coreGatewayProvider);
    final provider =
        await ref.read(connectedProviderProvider(arg.accountId).future);
    final reviews = gateway.reviews(provider);
    if (reviews == null) {
      throw StateError(
        'Account "${arg.accountId}" does not expose reviews; cannot reply.',
      );
    }

    final response = await gateway.replyToReview(
      reviews,
      reviewId: reviewId,
      body: body,
    );

    // Re-fetch so the new response is reflected.
    ref.invalidateSelf();
    return response;
  }
}

/// The reviews controller the UI slice consumes, keyed by (accountId, appId).
final reviewsControllerProvider = AsyncNotifierProvider.family<ReviewsController,
    List<CustomerReview>, ReviewsKey>(ReviewsController.new);
