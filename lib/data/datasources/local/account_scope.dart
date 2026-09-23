part of 'database.dart';

/// A bound handle never changes account. Futures, batches and query streams
/// keep this identity even after the UI activates a different account.
/// Registry/backup/migrations use the root handle (accountScope == null).
mixin AccountQueries on GeneratedDatabase {
  int? get accountScope;
  void checkAccountWrite();

  Expression<bool> accountFilter(ResultSetImplementation table) {
    final column = table.columnsByName['account_id'];
    return accountScope == null || column == null
        ? const Constant(true)
        : (column as GeneratedColumn<int>).equals(accountScope!);
  }

  bool _isScoped(ResultSetImplementation table) =>
      accountScope != null && table.columnsByName.containsKey('account_id');

  Insertable<D> scopeRow<T extends Table, D>(
    TableInfo<T, D> table,
    Insertable<D> row,
  ) {
    checkAccountWrite();
    return !_isScoped(table)
        ? row
        : RawValuesInsertable<D>({
            ...row.toColumns(true),
            'account_id': Variable(accountScope!),
          });
  }

  @override
  SimpleSelectStatement<T, R> select<T extends HasResultSet, R>(
    ResultSetImplementation<T, R> table, {
    bool distinct = false,
  }) {
    final statement = super.select(table, distinct: distinct);
    if (_isScoped(table)) statement.where((_) => accountFilter(table));
    return statement;
  }

  @override
  JoinedSelectStatement<T, R> selectOnly<T extends HasResultSet, R>(
    ResultSetImplementation<T, R> table, {
    bool distinct = false,
  }) {
    final statement = super.selectOnly(table, distinct: distinct);
    if (_isScoped(table)) statement.where(accountFilter(table));
    return statement;
  }

  Join accountInnerJoin(
    HasResultSet table,
    Expression<bool> on, {
    bool? useColumns,
  }) => innerJoin(
    table,
    on & accountFilter(table as ResultSetImplementation),
    useColumns: useColumns,
  );
  Join accountLeftJoin(
    HasResultSet table,
    Expression<bool> on, {
    bool? useColumns,
  }) => leftOuterJoin(
    table,
    on & accountFilter(table as ResultSetImplementation),
    useColumns: useColumns,
  );

  @override
  InsertStatement<T, D> into<T extends Table, D>(TableInfo<T, D> table) =>
      _AccountInsert(this, table);

  @override
  UpdateStatement<T, D> update<T extends Table, D>(TableInfo<T, D> table) {
    final statement = _AccountUpdate<T, D>(this, table);
    return statement;
  }

  @override
  DeleteStatement<T, D> delete<T extends Table, D>(TableInfo<T, D> table) {
    checkAccountWrite();
    final statement = _AccountDelete<T, D>(this, table);
    return statement;
  }

  @override
  Future<void> batch(FutureOr<void> Function(Batch batch) runInBatch) {
    if (accountScope != null) {
      throw StateError('Use accountBatch for account-bound writes');
    }
    return super.batch(runInBatch);
  }

  /// Drift's raw Batch bypasses into/update overrides. All app batches use
  /// this adapter so insert and update boundaries remain enforced centrally.
  Future<void> accountBatch(
    FutureOr<void> Function(AccountBatch batch) action,
  ) => super.batch((batch) async {
    checkAccountWrite();
    await action(AccountBatch(this, batch));
    checkAccountWrite();
  });
}

class _AccountInsert<T extends Table, D> extends InsertStatement<T, D> {
  final AccountQueries owner;
  _AccountInsert(this.owner, TableInfo<T, D> table) : super(owner, table);

  @override
  GenerationContext createContext(
    Insertable<D> entry,
    InsertMode mode, {
    UpsertClause<T, D>? onConflict,
    bool returning = false,
  }) => super.createContext(
    owner.scopeRow(table, entry),
    mode,
    onConflict: onConflict,
    returning: returning,
  );

  @override
  Future<int> insertOnConflictUpdate(Insertable<D> entity) =>
      super.insertOnConflictUpdate(owner.scopeRow(table, entity));
}

class _AccountUpdate<T extends Table, D> extends UpdateStatement<T, D> {
  final AccountQueries owner;
  final TableInfo<T, D> target;
  _AccountUpdate(this.owner, this.target) : super(owner, target);

  @override
  GenerationContext constructQuery() {
    owner.checkAccountWrite();
    where((_) => owner.accountFilter(target));
    return super.constructQuery();
  }

  @override
  Future<int> write(Insertable<D> entity, {bool dontExecute = false}) =>
      super.write(owner.scopeRow(target, entity), dontExecute: dontExecute);

  @override
  Future<bool> replace(Insertable<D> entity, {bool dontExecute = false}) =>
      super.replace(owner.scopeRow(target, entity), dontExecute: dontExecute);
}

class _AccountDelete<T extends Table, D> extends DeleteStatement<T, D> {
  final AccountQueries owner;
  _AccountDelete(this.owner, TableInfo<T, D> table) : super(owner, table);

  @override
  GenerationContext constructQuery() {
    owner.checkAccountWrite();
    where((_) => owner.accountFilter(table));
    return super.constructQuery();
  }
}

class AccountBatch {
  final AccountQueries owner;
  final Batch _batch;
  AccountBatch(this.owner, this._batch);

  void insert<T extends Table, D>(
    TableInfo<T, D> table,
    Insertable<D> row, {
    InsertMode? mode,
    UpsertClause<T, D>? onConflict,
  }) => _batch.insert(
    table,
    owner.scopeRow(table, row),
    mode: mode,
    onConflict: onConflict,
  );

  void update<T extends Table, D>(
    TableInfo<T, D> table,
    Insertable<D> row, {
    Expression<bool> Function(T table)? where,
  }) => _batch.update(
    table,
    owner.scopeRow(table, row),
    where: (t) =>
        owner.accountFilter(table) & (where?.call(t) ?? const Constant(true)),
  );
}
