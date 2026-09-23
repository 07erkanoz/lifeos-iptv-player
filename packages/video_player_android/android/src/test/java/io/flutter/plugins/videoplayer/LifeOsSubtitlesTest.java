package io.flutter.plugins.videoplayer;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;
import android.util.LongSparseArray;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.TrackSelectionParameters;
import androidx.media3.common.Tracks;
import androidx.media3.common.text.Cue;
import androidx.media3.common.text.CueGroup;
import androidx.media3.exoplayer.ExoPlayer;
import com.google.common.collect.ImmutableList;
import java.util.HashMap;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

@RunWith(RobolectricTestRunner.class)
public class LifeOsSubtitlesTest {
  private ExoPlayer player() {
    var player = mock(ExoPlayer.class);
    var format = new Format.Builder().setId("tr-text").setSampleMimeType("text/vtt").setLanguage("tr").setLabel("Turkish").build();
    var text = new Tracks.Group(new TrackGroup("text", format), false, new int[]{C.FORMAT_HANDLED}, new boolean[]{true});
    var audio = new Tracks.Group(new TrackGroup("audio", new Format.Builder().setSampleMimeType("audio/aac").build()), false, new int[]{C.FORMAT_HANDLED}, new boolean[]{true});
    when(player.getCurrentTracks()).thenReturn(new Tracks(ImmutableList.of(text, audio)));
    when(player.getTrackSelectionParameters()).thenReturn(TrackSelectionParameters.DEFAULT_WITHOUT_CONTEXT);
    return player;
  }
  @Test public void selectionUsesSupportedTextGroupAndRejectsStaleManifest() {
    var player = player();
    var rows = LifeOsSubtitles.tracks(player);
    assertEquals(1, rows.size());
    assertEquals("tr", rows.get(0).get("language"));
    LifeOsSubtitles.select(player, rows.get(0));
    var captor = ArgumentCaptor.forClass(TrackSelectionParameters.class);
    verify(player).setTrackSelectionParameters(captor.capture());
    assertFalse(captor.getValue().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT));
    assertEquals(1, captor.getValue().overrides.size());
    clearInvocations(player);
    var stale = new HashMap<String, Object>(rows.get(0));
    stale.put("formatId", "different-manifest-track");
    assertThrows(IllegalArgumentException.class, () -> LifeOsSubtitles.select(player, stale));
    stale.put("group", 1);
    assertThrows(IllegalArgumentException.class, () -> LifeOsSubtitles.select(player, stale));
    verify(player, never()).setTrackSelectionParameters(any());
  }
  @Test public void offDisablesOnlyText() {
    var player = player();
    var args = new HashMap<String, Object>(); args.put("off", true);
    LifeOsSubtitles.select(player, args);
    var captor = ArgumentCaptor.forClass(TrackSelectionParameters.class);
    verify(player).setTrackSelectionParameters(captor.capture());
    assertTrue(captor.getValue().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT));
    assertFalse(captor.getValue().disabledTrackTypes.contains(C.TRACK_TYPE_AUDIO));
  }
  @Test public void ambiguousOrRetiredUriCannotBindAnotherPlayer() {
    var players = new LongSparseArray<VideoPlayer>();
    var wrapper = mock(VideoPlayer.class);
    var player = player();
    when(wrapper.getExoPlayer()).thenReturn(player);
    when(player.getCurrentMediaItem()).thenReturn(MediaItem.fromUri("https://example.invalid/1"));
    players.put(7, wrapper);
    assertEquals(Long.valueOf(7), LifeOsSubtitles.resolve(players, "https://example.invalid/1"));
    assertNull(LifeOsSubtitles.resolve(players, "https://example.invalid/2"));
    players.put(8, wrapper);
    assertThrows(IllegalStateException.class, () -> LifeOsSubtitles.resolve(players, "https://example.invalid/1"));
    players.clear();
    assertNull(LifeOsSubtitles.resolve(players, "https://example.invalid/1"));
  }
  @Test public void overlayCannotTakeRemoteFocusAndReleasesItsListener() {
    var player = player();
    var cues = new CueGroup(ImmutableList.of(new Cue.Builder().setText("Caption").build()), 0);
    when(player.getCurrentCues()).thenReturn(cues);
    var overlay = new LifeOsSubtitles.Overlay(RuntimeEnvironment.getApplication(), player, new HashMap<>());
    assertFalse(overlay.getView().isFocusable());
    verify(player).addListener(overlay);
    overlay.onCues(cues);
    overlay.dispose();
    verify(player).removeListener(overlay);
  }
}
