// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plot_ai_cache_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(plotAiCacheRepository)
final plotAiCacheRepositoryProvider = PlotAiCacheRepositoryProvider._();

final class PlotAiCacheRepositoryProvider
    extends
        $FunctionalProvider<
          PlotAiCacheRepository,
          PlotAiCacheRepository,
          PlotAiCacheRepository
        >
    with $Provider<PlotAiCacheRepository> {
  PlotAiCacheRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'plotAiCacheRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$plotAiCacheRepositoryHash();

  @$internal
  @override
  $ProviderElement<PlotAiCacheRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlotAiCacheRepository create(Ref ref) {
    return plotAiCacheRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlotAiCacheRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlotAiCacheRepository>(value),
    );
  }
}

String _$plotAiCacheRepositoryHash() =>
    r'3d729b98f69ada8fb971d187a14c3f9336743c78';
