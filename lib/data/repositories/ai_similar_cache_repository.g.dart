// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_similar_cache_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiSimilarCacheRepository)
final aiSimilarCacheRepositoryProvider = AiSimilarCacheRepositoryProvider._();

final class AiSimilarCacheRepositoryProvider
    extends
        $FunctionalProvider<
          AiSimilarCacheRepository,
          AiSimilarCacheRepository,
          AiSimilarCacheRepository
        >
    with $Provider<AiSimilarCacheRepository> {
  AiSimilarCacheRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiSimilarCacheRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiSimilarCacheRepositoryHash();

  @$internal
  @override
  $ProviderElement<AiSimilarCacheRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiSimilarCacheRepository create(Ref ref) {
    return aiSimilarCacheRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiSimilarCacheRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiSimilarCacheRepository>(value),
    );
  }
}

String _$aiSimilarCacheRepositoryHash() =>
    r'b47ef2a75fede94fdd3967e1398bde0abec4c2e1';
