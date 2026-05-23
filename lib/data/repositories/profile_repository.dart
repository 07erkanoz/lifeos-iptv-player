import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CRUD + active-selection helpers for [Profiles] (Netflix-style
/// per-person personas).
///
/// State model:
///   * The DB always has at least one profile (`Profiles` is seeded
///     with id=1 during the v18 migration and re-asserted on every
///     boot via `beforeOpen`).
///   * The "active" profile id is held in SharedPreferences under
///     [_activeProfileKey] so it survives restarts without a
///     Drift round-trip on every read.
///   * All user-specific tables (favorites, playbackProgress,
///     watchlist, seriesTracking, aiFeedback, searchHistory) carry
///     a `profileId` foreign key; readers join / filter by the
///     currently-active id.
///
/// Threading: every method is async to keep the Riverpod surface
/// consistent, but the SharedPreferences read after [init] is a
/// pure in-memory map so most calls return in <1 ms.
class ProfileRepository {
  static const _activeProfileKey = 'active_profile_id';

  final AppDatabase _db;
  final SharedPreferences _prefs;

  ProfileRepository(this._db, this._prefs);

  /// Active profile id. Falls back to 1 (the seeded default) on
  /// first boot or after a "factory reset". Callers should treat
  /// this as the SQL filter value when running per-profile queries.
  int get activeProfileId => _prefs.getInt(_activeProfileKey) ?? 1;

  /// Switch the active profile. Persisted to prefs immediately;
  /// callers should `ref.invalidate(activeProfileProvider)` (or
  /// any downstream provider) after this returns so the UI rebuilds
  /// against the new id.
  Future<void> setActiveProfile(int id) async {
    await _prefs.setInt(_activeProfileKey, id);
  }

  /// All profiles, oldest-created first. The list is small (UI cap
  /// of ~5 profiles in practice) so we materialise rather than
  /// stream.
  Future<List<Profile>> getAll() async {
    return (_db.select(_db.profiles)
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)
          ]))
        .get();
    // No filter — every profile is owned by the same household. The
    // UI surfaces them all on the picker.
  }

  /// Live stream of all profiles, for the picker / settings UI.
  Stream<List<Profile>> watchAll() {
    return (_db.select(_db.profiles)
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)
          ]))
        .watch();
  }

  /// One-shot lookup by id. Returns null if the id is gone (e.g.
  /// the user deleted the profile currently active in prefs —
  /// callers fall back to id=1).
  Future<Profile?> getById(int id) async {
    return (_db.select(_db.profiles)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Create a new profile. Returns the newly-assigned id so the
  /// caller can switch into it immediately if the UX wants that.
  Future<int> create({
    required String name,
    String avatarKey = 'default',
    bool isKids = false,
    String? pin,
  }) async {
    final id = await _db.into(_db.profiles).insert(
          ProfilesCompanion.insert(
            name: name.trim(),
            avatarKey: Value(avatarKey),
            isKids: Value(isKids),
            pin: Value(pin),
          ),
        );
    return id;
  }

  /// Update an existing profile. Pass only the fields you want to
  /// change — pass [name]=null to leave name untouched, etc.
  /// PIN handling: passing null leaves the existing PIN. To clear
  /// a PIN, use [clearPin] instead.
  Future<void> update(
    int id, {
    String? name,
    String? avatarKey,
    bool? isKids,
    String? pin,
  }) async {
    await (_db.update(_db.profiles)..where((t) => t.id.equals(id))).write(
      ProfilesCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        avatarKey:
            avatarKey == null ? const Value.absent() : Value(avatarKey),
        isKids: isKids == null ? const Value.absent() : Value(isKids),
        pin: pin == null ? const Value.absent() : Value(pin),
      ),
    );
  }

  /// Explicit PIN-clear. The [update] API treats null as "leave
  /// alone"; this method writes `null` so the row's PIN is removed.
  Future<void> clearPin(int id) async {
    await (_db.update(_db.profiles)..where((t) => t.id.equals(id))).write(
      const ProfilesCompanion(pin: Value(null)),
    );
  }

  /// Delete a profile AND every user-specific row tied to it. We do
  /// this as a single transaction so a power-cut mid-delete can't
  /// leave orphaned favourites / progress rows behind. The default
  /// profile (id=1) cannot be deleted — the UI hides the delete
  /// affordance for it, but we guard here too as a backstop.
  Future<void> delete(int id) async {
    if (id == 1) return;
    await _db.transaction(() async {
      await (_db.delete(_db.favorites)
            ..where((t) => t.profileId.equals(id)))
          .go();
      await (_db.delete(_db.playbackProgress)
            ..where((t) => t.profileId.equals(id)))
          .go();
      await (_db.delete(_db.watchlist)
            ..where((t) => t.profileId.equals(id)))
          .go();
      await (_db.delete(_db.seriesTracking)
            ..where((t) => t.profileId.equals(id)))
          .go();
      await (_db.delete(_db.aiFeedback)
            ..where((t) => t.profileId.equals(id)))
          .go();
      await (_db.delete(_db.searchHistory)
            ..where((t) => t.profileId.equals(id)))
          .go();
      await (_db.delete(_db.profiles)..where((t) => t.id.equals(id))).go();
    });

    // If the user deleted the profile they were on, fall back to
    // the default so the next query has a valid filter.
    if (activeProfileId == id) {
      await setActiveProfile(1);
    }
  }
}

/// Async one-shot SharedPreferences handle. Kept alive so the
/// shared_preferences singleton is read once and reused across
/// every dependent provider (no repeated platform-channel
/// round-trip).
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// Profile repository — keepAlive so a single instance backs every
/// downstream provider. Resolved lazily once both the DB and prefs
/// are ready.
final profileRepositoryProvider =
    FutureProvider<ProfileRepository>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return ProfileRepository(db, prefs);
});

/// The currently-active profile id. Plain `int` so consumers can
/// slot it into Drift `where(...)` clauses without further hops.
/// Defaults to 1 (the seeded "Varsayılan" profile) when prefs are
/// empty.
///
/// Bump with `ref.invalidate(activeProfileIdProvider)` after
/// `repo.setActiveProfile(...)` so every downstream provider re-
/// runs against the new id.
final activeProfileIdProvider = FutureProvider<int>((ref) async {
  final repo = await ref.watch(profileRepositoryProvider.future);
  return repo.activeProfileId;
});

/// Live list of all profiles, for the picker + settings UI. Emits on
/// every insert / update / delete.
final profilesListProvider = StreamProvider<List<Profile>>((ref) async* {
  final repo = await ref.watch(profileRepositoryProvider.future);
  yield* repo.watchAll();
});

/// The active profile row itself. Returns null when the active id
/// has been deleted underneath us; callers fall back to "Varsayılan"
/// labelling.
final activeProfileProvider = FutureProvider<Profile?>((ref) async {
  final repo = await ref.watch(profileRepositoryProvider.future);
  final id = await ref.watch(activeProfileIdProvider.future);
  return repo.getById(id);
});
