// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'content_enrichment_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(contentEnrichmentRepository)
final contentEnrichmentRepositoryProvider =
    ContentEnrichmentRepositoryProvider._();

final class ContentEnrichmentRepositoryProvider
    extends
        $FunctionalProvider<
          ContentEnrichmentRepository,
          ContentEnrichmentRepository,
          ContentEnrichmentRepository
        >
    with $Provider<ContentEnrichmentRepository> {
  ContentEnrichmentRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contentEnrichmentRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contentEnrichmentRepositoryHash();

  @$internal
  @override
  $ProviderElement<ContentEnrichmentRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ContentEnrichmentRepository create(Ref ref) {
    return contentEnrichmentRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContentEnrichmentRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContentEnrichmentRepository>(value),
    );
  }
}

String _$contentEnrichmentRepositoryHash() =>
    r'544905548258a0ef02c865a110dd64c39852766c';
