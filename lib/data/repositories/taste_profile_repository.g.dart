// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'taste_profile_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(tasteProfileRepository)
final tasteProfileRepositoryProvider = TasteProfileRepositoryProvider._();

final class TasteProfileRepositoryProvider
    extends
        $FunctionalProvider<
          TasteProfileRepository,
          TasteProfileRepository,
          TasteProfileRepository
        >
    with $Provider<TasteProfileRepository> {
  TasteProfileRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tasteProfileRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tasteProfileRepositoryHash();

  @$internal
  @override
  $ProviderElement<TasteProfileRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TasteProfileRepository create(Ref ref) {
    return tasteProfileRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TasteProfileRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TasteProfileRepository>(value),
    );
  }
}

String _$tasteProfileRepositoryHash() =>
    r'0ac0e4d104624f131b9b5469a32bf75a23b44823';

/// One-shot async profile. AI rail providers `ref.watch` this so
/// the profile is computed once per dashboard mount instead of
/// each rail rebuilding it. Auto-invalidates whenever feedback
/// changes (the repo watches `dislikedStreamIdsProvider`-equivalents).

@ProviderFor(tasteProfile)
final tasteProfileProvider = TasteProfileProvider._();

/// One-shot async profile. AI rail providers `ref.watch` this so
/// the profile is computed once per dashboard mount instead of
/// each rail rebuilding it. Auto-invalidates whenever feedback
/// changes (the repo watches `dislikedStreamIdsProvider`-equivalents).

final class TasteProfileProvider
    extends
        $FunctionalProvider<
          AsyncValue<TasteProfile>,
          TasteProfile,
          FutureOr<TasteProfile>
        >
    with $FutureModifier<TasteProfile>, $FutureProvider<TasteProfile> {
  /// One-shot async profile. AI rail providers `ref.watch` this so
  /// the profile is computed once per dashboard mount instead of
  /// each rail rebuilding it. Auto-invalidates whenever feedback
  /// changes (the repo watches `dislikedStreamIdsProvider`-equivalents).
  TasteProfileProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tasteProfileProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tasteProfileHash();

  @$internal
  @override
  $FutureProviderElement<TasteProfile> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<TasteProfile> create(Ref ref) {
    return tasteProfile(ref);
  }
}

String _$tasteProfileHash() => r'c5a2ec182eadb75f2ee77bbe6e74f8412b35bab7';
