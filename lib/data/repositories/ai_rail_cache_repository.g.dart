// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_rail_cache_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiRailCacheRepository)
final aiRailCacheRepositoryProvider = AiRailCacheRepositoryProvider._();

final class AiRailCacheRepositoryProvider
    extends
        $FunctionalProvider<
          AiRailCacheRepository,
          AiRailCacheRepository,
          AiRailCacheRepository
        >
    with $Provider<AiRailCacheRepository> {
  AiRailCacheRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiRailCacheRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiRailCacheRepositoryHash();

  @$internal
  @override
  $ProviderElement<AiRailCacheRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiRailCacheRepository create(Ref ref) {
    return aiRailCacheRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiRailCacheRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiRailCacheRepository>(value),
    );
  }
}

String _$aiRailCacheRepositoryHash() =>
    r'13e7cb489f1cf1a683aca750b0b32ef1ce757391';
