/// Branch indices for [StatefulShellRoute.indexedStack] in
/// `lib/config/router.dart`. Kept in one place so screens can register
/// their primary focus target with [TvFocusRegistry] without copying
/// magic numbers. Update both files together if the route order ever
/// changes.
class TvBranchIndex {
  TvBranchIndex._();

  static const dashboard = 0;
  static const liveTv = 1;
  static const movies = 2;
  static const series = 3;
  static const settings = 4;
}
