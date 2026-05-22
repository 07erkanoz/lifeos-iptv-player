// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_instrumentation_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiInstrumentation)
final aiInstrumentationProvider = AiInstrumentationProvider._();

final class AiInstrumentationProvider
    extends
        $FunctionalProvider<
          AiInstrumentationService,
          AiInstrumentationService,
          AiInstrumentationService
        >
    with $Provider<AiInstrumentationService> {
  AiInstrumentationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiInstrumentationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiInstrumentationHash();

  @$internal
  @override
  $ProviderElement<AiInstrumentationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiInstrumentationService create(Ref ref) {
    return aiInstrumentation(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiInstrumentationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiInstrumentationService>(value),
    );
  }
}

String _$aiInstrumentationHash() => r'eb095f6a9093f24ecbe316a8ee6fa337c82abfd6';
