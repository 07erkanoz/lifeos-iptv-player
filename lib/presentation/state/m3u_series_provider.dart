import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/services/m3u_series_catalog.dart';
import 'auth_provider.dart';

/// One account-scoped index shared by grids and detail. Group BEFORE paging,
/// otherwise the first show's episodes can consume the whole grid window.
final m3uSeriesCatalogProvider = StreamProvider<M3uSeriesCatalog>((ref) {
  final account = ref.watch(currentAccountProvider).value;
  if (account?.type != 'm3u') {
    return Stream.value(const M3uSeriesCatalog([], {}));
  }
  return ref
      .watch(contentRepositoryProvider)
      .forAccount(account!.id)
      .watchAllChannelsByType('series')
      .asyncMap(buildM3uSeriesCatalogAsync);
});
