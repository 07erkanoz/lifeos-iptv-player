// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'watchlist_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(watchlistRepository)
final watchlistRepositoryProvider = WatchlistRepositoryProvider._();

final class WatchlistRepositoryProvider
    extends
        $FunctionalProvider<
          WatchlistRepository,
          WatchlistRepository,
          WatchlistRepository
        >
    with $Provider<WatchlistRepository> {
  WatchlistRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'watchlistRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$watchlistRepositoryHash();

  @$internal
  @override
  $ProviderElement<WatchlistRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WatchlistRepository create(Ref ref) {
    return watchlistRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WatchlistRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WatchlistRepository>(value),
    );
  }
}

String _$watchlistRepositoryHash() =>
    r'5001a35159516a579642ea6b959b1ff2fb08bf55';
