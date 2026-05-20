// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intro_marker_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(introMarkerRepository)
final introMarkerRepositoryProvider = IntroMarkerRepositoryProvider._();

final class IntroMarkerRepositoryProvider
    extends
        $FunctionalProvider<
          IntroMarkerRepository,
          IntroMarkerRepository,
          IntroMarkerRepository
        >
    with $Provider<IntroMarkerRepository> {
  IntroMarkerRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'introMarkerRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$introMarkerRepositoryHash();

  @$internal
  @override
  $ProviderElement<IntroMarkerRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  IntroMarkerRepository create(Ref ref) {
    return introMarkerRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntroMarkerRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntroMarkerRepository>(value),
    );
  }
}

String _$introMarkerRepositoryHash() =>
    r'a74da4560fff1caac75ecf5312d798f3b484ea79';
