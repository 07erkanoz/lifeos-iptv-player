/// Semantic focus zones for Android TV / D-pad navigation.
///
/// Every screen that participates in TV navigation declares which zone it
/// currently sits in. Sidebar / category / grid / detail / EPG semantics
/// are different — directional traversal alone can't tell them apart, so
/// we name them explicitly and route transitions through the registry.
enum TvFocusZone {
  /// The left-edge primary navigation rail (movies/series/live/settings).
  mainSidebar,

  /// The secondary sidebar that lists categories within a content screen.
  categorySidebar,

  /// Sort / filter / search bar above the content grid.
  contentToolbar,

  /// The poster grid itself.
  contentGrid,

  /// A modal-ish detail view layered on top of the content area
  /// (movie / series detail, dialogs).
  detail,

  /// Live TV channel list on the left.
  epgChannelList,

  /// Live TV program timeline on the right.
  epgTimeline,
}
