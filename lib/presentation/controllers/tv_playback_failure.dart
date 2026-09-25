enum TvPlaybackFailure { source, decoder, other }

/// The native bridge sends Media3's stable code and cause class, never its
/// exception message: IPTV error messages can contain account credentials.
TvPlaybackFailure classifyTvPlaybackFailure(String? description) {
  if (description == null) return TvPlaybackFailure.other;
  if (description.contains('UnrecognizedInputFormatException') ||
      description.contains('ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED') ||
      description.contains('ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED')) {
    return TvPlaybackFailure.source;
  }
  if (description.contains('ERROR_CODE_DECODING_FORMAT_UNSUPPORTED') ||
      description.contains('ERROR_CODE_DECODING_FAILED') ||
      description.contains('DecoderInitializationException') ||
      description.contains('ERROR_CODE_AUDIO_TRACK_INIT_FAILED')) {
    return TvPlaybackFailure.decoder;
  }
  return TvPlaybackFailure.other;
}
