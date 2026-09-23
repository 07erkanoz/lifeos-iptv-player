package io.flutter.plugins.videoplayer;

import static org.junit.Assert.assertEquals;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import java.util.HashMap;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

@RunWith(RobolectricTestRunner.class)
public class LifeOsPlaybackConfigTest {
  @Test
  public void qualityBoundsAndAutoResetReachTrackSelector() {
    var context = RuntimeEnvironment.getApplication();
    var selector = new DefaultTrackSelector(context);
    var config = new LifeOsPlaybackConfig();
    String[] qualities = {"low", "medium", "high", "auto"};
    int[] heights = {480, 720, 1080, Integer.MAX_VALUE};
    int[] bitrates = {1000000, 3000000, Integer.MAX_VALUE, Integer.MAX_VALUE};
    for (int i = 0; i < qualities.length; i++) {
      var args = new HashMap<String, Object>();
      args.put("quality", qualities[i]);
      config.update(args);
      config.configure(context, selector);
      assertEquals(heights[i], selector.getParameters().maxVideoHeight);
      assertEquals(bitrates[i], selector.getParameters().maxVideoBitrate);
    }
    selector.release();
  }
}
