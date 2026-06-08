// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'content_embeddings_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(contentEmbeddingsRepository)
final contentEmbeddingsRepositoryProvider =
    ContentEmbeddingsRepositoryProvider._();

final class ContentEmbeddingsRepositoryProvider
    extends
        $FunctionalProvider<
          ContentEmbeddingsRepository,
          ContentEmbeddingsRepository,
          ContentEmbeddingsRepository
        >
    with $Provider<ContentEmbeddingsRepository> {
  ContentEmbeddingsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contentEmbeddingsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contentEmbeddingsRepositoryHash();

  @$internal
  @override
  $ProviderElement<ContentEmbeddingsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ContentEmbeddingsRepository create(Ref ref) {
    return contentEmbeddingsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContentEmbeddingsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContentEmbeddingsRepository>(value),
    );
  }
}

String _$contentEmbeddingsRepositoryHash() =>
    r'188d2d1f0a946b1bfcd92f8f087e17ae07c8097f';
