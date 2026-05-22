// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_feedback_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiFeedbackRepository)
final aiFeedbackRepositoryProvider = AiFeedbackRepositoryProvider._();

final class AiFeedbackRepositoryProvider
    extends
        $FunctionalProvider<
          AiFeedbackRepository,
          AiFeedbackRepository,
          AiFeedbackRepository
        >
    with $Provider<AiFeedbackRepository> {
  AiFeedbackRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiFeedbackRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiFeedbackRepositoryHash();

  @$internal
  @override
  $ProviderElement<AiFeedbackRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiFeedbackRepository create(Ref ref) {
    return aiFeedbackRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiFeedbackRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiFeedbackRepository>(value),
    );
  }
}

String _$aiFeedbackRepositoryHash() =>
    r'1a9c28076794deac527266c138f3e38ea91e4ff7';

/// Live-watched set of disliked stream IDs. AI rail providers
/// `ref.watch` this to filter candidates without a per-call query.

@ProviderFor(dislikedStreamIds)
final dislikedStreamIdsProvider = DislikedStreamIdsProvider._();

/// Live-watched set of disliked stream IDs. AI rail providers
/// `ref.watch` this to filter candidates without a per-call query.

final class DislikedStreamIdsProvider
    extends
        $FunctionalProvider<AsyncValue<Set<int>>, Set<int>, Stream<Set<int>>>
    with $FutureModifier<Set<int>>, $StreamProvider<Set<int>> {
  /// Live-watched set of disliked stream IDs. AI rail providers
  /// `ref.watch` this to filter candidates without a per-call query.
  DislikedStreamIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dislikedStreamIdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dislikedStreamIdsHash();

  @$internal
  @override
  $StreamProviderElement<Set<int>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Set<int>> create(Ref ref) {
    return dislikedStreamIds(ref);
  }
}

String _$dislikedStreamIdsHash() => r'aa9283928c9e9020044fcfc38d459f5728e73652';
