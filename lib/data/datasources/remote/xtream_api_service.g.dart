// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'xtream_api_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(xtreamApiService)
final xtreamApiServiceProvider = XtreamApiServiceProvider._();

final class XtreamApiServiceProvider
    extends
        $FunctionalProvider<
          XtreamApiService,
          XtreamApiService,
          XtreamApiService
        >
    with $Provider<XtreamApiService> {
  XtreamApiServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'xtreamApiServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$xtreamApiServiceHash();

  @$internal
  @override
  $ProviderElement<XtreamApiService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  XtreamApiService create(Ref ref) {
    return xtreamApiService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(XtreamApiService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<XtreamApiService>(value),
    );
  }
}

String _$xtreamApiServiceHash() => r'24d0829215b530b440a1835b417a8e55c90791c7';
