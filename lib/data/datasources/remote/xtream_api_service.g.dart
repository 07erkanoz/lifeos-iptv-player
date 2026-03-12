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

String _$xtreamApiServiceHash() => r'c655e525b4327406f548ac686b35f38f34b90fa4';
