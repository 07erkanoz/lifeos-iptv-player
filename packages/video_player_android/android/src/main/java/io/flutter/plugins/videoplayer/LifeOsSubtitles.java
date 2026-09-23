package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.util.LongSparseArray;
import android.view.View;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.Player;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.Tracks;
import androidx.media3.common.text.CueGroup;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.ui.CaptionStyleCompat;
import androidx.media3.ui.SubtitleView;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Engine-local subtitle controls. Never guesses between duplicate media sessions. */
@UnstableApi
public final class LifeOsSubtitles {
  public static Long resolve(LongSparseArray<VideoPlayer> players, String uri) {
    Long found = null;
    for (int i = 0; i < players.size(); i++) {
      MediaItem item = players.valueAt(i).getExoPlayer().getCurrentMediaItem();
      if (item != null && item.localConfiguration != null &&
          item.localConfiguration.uri.toString().equals(uri)) {
        if (found != null) throw new IllegalStateException("Ambiguous media session");
        found = players.keyAt(i);
      }
    }
    return found;
  }

  public static List<Map<String, Object>> tracks(ExoPlayer player) {
    var result = new ArrayList<Map<String, Object>>();
    Tracks tracks = player.getCurrentTracks();
    for (int g = 0; g < tracks.getGroups().size(); g++) {
      var group = tracks.getGroups().get(g);
      if (group.getType() != C.TRACK_TYPE_TEXT) continue;
      for (int t = 0; t < group.length; t++) {
        if (!group.isTrackSupported(t)) continue;
        Format format = group.getTrackFormat(t);
        var row = new HashMap<String, Object>();
        row.put("group", g);
        row.put("track", t);
        row.put("formatId", format.id);
        row.put("language", format.language);
        row.put("label", format.label);
        row.put("mime", format.sampleMimeType);
        row.put("selected", group.isTrackSelected(t));
        result.add(row);
      }
    }
    return result;
  }

  public static void select(ExoPlayer player, Map<?, ?> args) {
    var params = player.getTrackSelectionParameters().buildUpon()
        .clearOverridesOfType(C.TRACK_TYPE_TEXT);
    if (Boolean.TRUE.equals(args.get("off"))) {
      player.setTrackSelectionParameters(params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build());
      return;
    }
    if (!(args.get("group") instanceof Number) || !(args.get("track") instanceof Number))
      throw new IllegalArgumentException("Missing subtitle track");
    int g = ((Number) args.get("group")).intValue();
    int t = ((Number) args.get("track")).intValue();
    var groups = player.getCurrentTracks().getGroups();
    if (g < 0 || g >= groups.size()) throw new IllegalArgumentException("Subtitle group changed");
    var group = groups.get(g);
    if (group.getType() != C.TRACK_TYPE_TEXT || t < 0 || t >= group.length || !group.isTrackSupported(t))
      throw new IllegalArgumentException("Unavailable subtitle track");
    Format format = group.getTrackFormat(t);
    // The manifest may have changed while a selection dialog was open.
    if (!java.util.Objects.equals(format.id, args.get("formatId")) ||
        !java.util.Objects.equals(format.language, args.get("language")) ||
        !java.util.Objects.equals(format.sampleMimeType, args.get("mime")))
      throw new IllegalArgumentException("Subtitle format changed");
    player.setTrackSelectionParameters(params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
        .setOverrideForType(new TrackSelectionOverride(group.getMediaTrackGroup(), t)).build());
  }

  public static final class Factory extends PlatformViewFactory {
    private final LongSparseArray<VideoPlayer> players;
    public Factory(LongSparseArray<VideoPlayer> players) {
      super(StandardMessageCodec.INSTANCE);
      this.players = players;
    }
    @Override public PlatformView create(Context context, int id, Object raw) {
      Map<?, ?> args = raw instanceof Map ? (Map<?, ?>) raw : new HashMap<>();
      Object key = args.get("playerId");
      VideoPlayer target = key instanceof Number ? players.get(((Number) key).longValue()) : null;
      return new Overlay(context, target == null ? null : target.getExoPlayer(), args);
    }
  }

  public static final class Overlay implements PlatformView, Player.Listener {
    private final SubtitleView view;
    private final ExoPlayer player;
    public Overlay(Context context, ExoPlayer player, Map<?, ?> args) {
      this.player = player;
      view = new SubtitleView(context);
      view.setFocusable(false);
      view.setFocusableInTouchMode(false);
      view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
      float fraction = args.get("fontFraction") instanceof Number ? ((Number) args.get("fontFraction")).floatValue() : 0.0533f;
      if (!Float.isFinite(fraction)) fraction = 0.0533f;
      view.setFractionalTextSize(Math.max(0.018f, Math.min(0.12f, fraction)));
      int foreground = args.get("color") instanceof Number ? ((Number) args.get("color")).intValue() : Color.WHITE;
      int background = Boolean.TRUE.equals(args.get("background")) ? 0xA0000000 : Color.TRANSPARENT;
      view.setStyle(new CaptionStyleCompat(foreground, background, Color.TRANSPARENT,
          CaptionStyleCompat.EDGE_TYPE_OUTLINE, Color.BLACK,
          Boolean.TRUE.equals(args.get("bold")) ? Typeface.DEFAULT_BOLD : Typeface.DEFAULT));
      if (player != null) {
        view.setCues(player.getCurrentCues().cues);
        player.addListener(this);
      }
    }
    @Override public View getView() { return view; }
    @Override public void onCues(CueGroup cues) { view.setCues(cues.cues); }
    @Override public void dispose() {
      if (player != null) player.removeListener(this);
      view.setCues(null);
    }
  }
}
