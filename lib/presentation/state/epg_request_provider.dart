import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/epg_request_gate.dart';

/// Shared by the channel grid and player overlays in the same account scope.
final epgRequestGateProvider = Provider((ref) {
  ref.watch(appDatabaseProvider);
  return EpgRequestGate();
});
