import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/personalized_picks_repository.dart';

void main() {
  test('persistent AI cache isolates account, profile and language', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tr = PersonalizedPicksRepository(db.forAccount(1), cacheId: 102);
    final en = PersonalizedPicksRepository(db.forAccount(1), cacheId: 101);
    final otherProfile = PersonalizedPicksRepository(
      db.forAccount(1),
      cacheId: 202,
    );
    final otherAccount = PersonalizedPicksRepository(
      db.forAccount(2),
      cacheId: 102,
    );
    await tr.store(
      sourceHash: 'same',
      picks: [(streamId: 11, reason: 'Türkçe')],
    );
    expect((await tr.lookup(sourceHash: 'same'))!.single.reason, 'Türkçe');
    for (final other in [en, otherProfile, otherAccount]) {
      expect(await other.lookupLatest(), isNull);
    }
    await en.store(
      sourceHash: 'same',
      picks: [(streamId: 11, reason: 'English')],
    );
    await tr.clear();
    expect(await tr.lookupLatest(), isNull);
    expect((await en.lookupLatest())!.single.reason, 'English');
  });
}
