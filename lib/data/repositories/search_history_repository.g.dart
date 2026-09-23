// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_history_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(searchHistoryRepository)
final searchHistoryRepositoryProvider = SearchHistoryRepositoryProvider._();

final class SearchHistoryRepositoryProvider
    extends
        $FunctionalProvider<
          SearchHistoryRepository,
          SearchHistoryRepository,
          SearchHistoryRepository
        >
    with $Provider<SearchHistoryRepository> {
  SearchHistoryRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchHistoryRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchHistoryRepositoryHash();

  @$internal
  @override
  $ProviderElement<SearchHistoryRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SearchHistoryRepository create(Ref ref) {
    return searchHistoryRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SearchHistoryRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SearchHistoryRepository>(value),
    );
  }
}

String _$searchHistoryRepositoryHash() =>
    r'29ff5a8d72593e8f915967c9583402691c8e2273';

/// Live recent queries — search screen chip row watches this so a
/// new entry appears the moment it's recorded.

@ProviderFor(recentSearches)
final recentSearchesProvider = RecentSearchesProvider._();

/// Live recent queries — search screen chip row watches this so a
/// new entry appears the moment it's recorded.

final class RecentSearchesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          FutureOr<List<String>>
        >
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  /// Live recent queries — search screen chip row watches this so a
  /// new entry appears the moment it's recorded.
  RecentSearchesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentSearchesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentSearchesHash();

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    return recentSearches(ref);
  }
}

String _$recentSearchesHash() => r'b3347380ea790827b40029b280f2651f0830d954';

@ProviderFor(trendingSearches)
final trendingSearchesProvider = TrendingSearchesProvider._();

final class TrendingSearchesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          FutureOr<List<String>>
        >
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  TrendingSearchesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trendingSearchesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trendingSearchesHash();

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    return trendingSearches(ref);
  }
}

String _$trendingSearchesHash() => r'9d6b32eb9f02cb7b3d9a21d891af90086992761b';
