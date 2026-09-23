package io.flutter.plugins.videoplayer;

import android.content.Context;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import java.util.ArrayList;
import java.util.Map;

/** Per-engine playback preferences applied only when creating the next player. */
@UnstableApi
public final class LifeOsPlaybackConfig {
  private boolean hardwareAcceleration = true;
  private boolean live = false;
  private int bufferSeconds = 30;
  private int maxVideoBitrate = Integer.MAX_VALUE;

  public void update(Map<?, ?> args) {
    hardwareAcceleration = !Boolean.FALSE.equals(args.get("hardwareAcceleration"));
    live = Boolean.TRUE.equals(args.get("live"));
    Object seconds = args.get("bufferSeconds");
    bufferSeconds = Math.max(5, Math.min(120, seconds instanceof Number ? ((Number) seconds).intValue() : 30));
    Object quality = args.get("quality");
    maxVideoBitrate = "low".equals(quality) ? 1000000 : "medium".equals(quality) ? 3000000 : Integer.MAX_VALUE;
  }

  public ExoPlayer.Builder configure(Context context, DefaultTrackSelector selector) {
    DefaultRenderersFactory renderers = new DefaultRenderersFactory(context)
        .setEnableDecoderFallback(true);
    if (!hardwareAcceleration) {
      // Use software MediaCodec implementations only. Unsupported formats produce
      // a normal player error; do not silently turn hardware decoding back on.
      renderers.setMediaCodecSelector((mimeType, secure, tunneling) -> {
        var candidates = MediaCodecSelector.DEFAULT.getDecoderInfos(mimeType, secure, tunneling);
        var software = new ArrayList<androidx.media3.exoplayer.mediacodec.MediaCodecInfo>();
        for (var codec : candidates) {
          if (codec.softwareOnly) software.add(codec);
        }
        return software;
      });
    }
    int maxMs = (live ? Math.min(bufferSeconds, 30) : bufferSeconds) * 1000;
    int minMs = Math.min(maxMs, live ? 5000 : 10000);
    DefaultLoadControl load = new DefaultLoadControl.Builder()
        .setBufferDurationsMs(minMs, maxMs, live ? 1000 : 1500, 2000)
        .setTargetBufferBytes((live ? 32 : 64) * 1024 * 1024)
        .setPrioritizeTimeOverSizeThresholds(false)
        .setBackBuffer(live ? 0 : 10000, true)
        .build();
    selector.setParameters(selector.buildUponParameters().setMaxVideoBitrate(maxVideoBitrate));
    return new ExoPlayer.Builder(context, renderers).setTrackSelector(selector).setLoadControl(load);
  }
}
