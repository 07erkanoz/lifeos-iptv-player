import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/controllers/tv_playback_failure.dart';

void main() {
  test('bad provider response is distinct from unsupported decoder', () {
    expect(
      classifyTvPlaybackFailure(
        'ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED:UnrecognizedInputFormatException',
      ),
      TvPlaybackFailure.source,
    );
    expect(
      classifyTvPlaybackFailure(
        'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED:DecoderInitializationException',
      ),
      TvPlaybackFailure.decoder,
    );
    expect(
      classifyTvPlaybackFailure(
        'ERROR_CODE_IO_BAD_HTTP_STATUS:InvalidResponseCodeException',
      ),
      TvPlaybackFailure.other,
    );
  });
}
