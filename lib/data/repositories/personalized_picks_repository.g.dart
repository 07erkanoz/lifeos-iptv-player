// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'personalized_picks_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(personalizedPicksRepository)
final personalizedPicksRepositoryProvider =
    PersonalizedPicksRepositoryProvider._();

final class PersonalizedPicksRepositoryProvider
    extends
        $FunctionalProvider<
          PersonalizedPicksRepository,
          PersonalizedPicksRepository,
          PersonalizedPicksRepository
        >
    with $Provider<PersonalizedPicksRepository> {
  PersonalizedPicksRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'personalizedPicksRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$personalizedPicksRepositoryHash();

  @$internal
  @override
  $ProviderElement<PersonalizedPicksRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PersonalizedPicksRepository create(Ref ref) {
    return personalizedPicksRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PersonalizedPicksRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PersonalizedPicksRepository>(value),
    );
  }
}

String _$personalizedPicksRepositoryHash() =>
    r'e3ba58e49b9953bce5c8e561a1666212ed319341';
