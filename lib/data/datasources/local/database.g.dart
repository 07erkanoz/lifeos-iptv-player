// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _passwordMeta = const VerificationMeta(
    'password',
  );
  @override
  late final GeneratedColumn<String> password = GeneratedColumn<String>(
    'password',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    url,
    username,
    password,
    isActive,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Account> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('password')) {
      context.handle(
        _passwordMeta,
        password.isAcceptableOrUnknown(data['password']!, _passwordMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      password: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class Account extends DataClass implements Insertable<Account> {
  final int id;
  final String name;
  final String type;
  final String url;
  final String? username;
  final String? password;
  final bool isActive;
  final DateTime createdAt;
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.username,
    this.password,
    required this.isActive,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    if (!nullToAbsent || password != null) {
      map['password'] = Variable<String>(password);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      url: Value(url),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      password: password == null && nullToAbsent
          ? const Value.absent()
          : Value(password),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory Account.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      url: serializer.fromJson<String>(json['url']),
      username: serializer.fromJson<String?>(json['username']),
      password: serializer.fromJson<String?>(json['password']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'url': serializer.toJson<String>(url),
      'username': serializer.toJson<String?>(username),
      'password': serializer.toJson<String?>(password),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Account copyWith({
    int? id,
    String? name,
    String? type,
    String? url,
    Value<String?> username = const Value.absent(),
    Value<String?> password = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    url: url ?? this.url,
    username: username.present ? username.value : this.username,
    password: password.present ? password.value : this.password,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      url: data.url.present ? data.url.value : this.url,
      username: data.username.present ? data.username.value : this.username,
      password: data.password.present ? data.password.value : this.password,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('url: $url, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, type, url, username, password, isActive, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.url == this.url &&
          other.username == this.username &&
          other.password == this.password &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String> url;
  final Value<String?> username;
  final Value<String?> password;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.url = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  AccountsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String type,
    required String url,
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : name = Value(name),
       type = Value(type),
       url = Value(url);
  static Insertable<Account> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? url,
    Expression<String>? username,
    Expression<String>? password,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (url != null) 'url': url,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  AccountsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? type,
    Value<String>? url,
    Value<String?>? username,
    Value<String?>? password,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (password.present) {
      map['password'] = Variable<String>(password.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('url: $url, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarKeyMeta = const VerificationMeta(
    'avatarKey',
  );
  @override
  late final GeneratedColumn<String> avatarKey = GeneratedColumn<String>(
    'avatar_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('default'),
  );
  static const VerificationMeta _isKidsMeta = const VerificationMeta('isKids');
  @override
  late final GeneratedColumn<bool> isKids = GeneratedColumn<bool>(
    'is_kids',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_kids" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinMeta = const VerificationMeta('pin');
  @override
  late final GeneratedColumn<String> pin = GeneratedColumn<String>(
    'pin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    avatarKey,
    isKids,
    pin,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<Profile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar_key')) {
      context.handle(
        _avatarKeyMeta,
        avatarKey.isAcceptableOrUnknown(data['avatar_key']!, _avatarKeyMeta),
      );
    }
    if (data.containsKey('is_kids')) {
      context.handle(
        _isKidsMeta,
        isKids.isAcceptableOrUnknown(data['is_kids']!, _isKidsMeta),
      );
    }
    if (data.containsKey('pin')) {
      context.handle(
        _pinMeta,
        pin.isAcceptableOrUnknown(data['pin']!, _pinMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatarKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_key'],
      )!,
      isKids: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_kids'],
      )!,
      pin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pin'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  final int id;
  final String name;
  final String avatarKey;
  final bool isKids;

  /// Optional 4-digit PIN gating the switch INTO this profile. Set
  /// only on kids profiles by parents; null elsewhere.
  final String? pin;
  final DateTime createdAt;
  const Profile({
    required this.id,
    required this.name,
    required this.avatarKey,
    required this.isKids,
    this.pin,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['avatar_key'] = Variable<String>(avatarKey);
    map['is_kids'] = Variable<bool>(isKids);
    if (!nullToAbsent || pin != null) {
      map['pin'] = Variable<String>(pin);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      name: Value(name),
      avatarKey: Value(avatarKey),
      isKids: Value(isKids),
      pin: pin == null && nullToAbsent ? const Value.absent() : Value(pin),
      createdAt: Value(createdAt),
    );
  }

  factory Profile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      avatarKey: serializer.fromJson<String>(json['avatarKey']),
      isKids: serializer.fromJson<bool>(json['isKids']),
      pin: serializer.fromJson<String?>(json['pin']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'avatarKey': serializer.toJson<String>(avatarKey),
      'isKids': serializer.toJson<bool>(isKids),
      'pin': serializer.toJson<String?>(pin),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Profile copyWith({
    int? id,
    String? name,
    String? avatarKey,
    bool? isKids,
    Value<String?> pin = const Value.absent(),
    DateTime? createdAt,
  }) => Profile(
    id: id ?? this.id,
    name: name ?? this.name,
    avatarKey: avatarKey ?? this.avatarKey,
    isKids: isKids ?? this.isKids,
    pin: pin.present ? pin.value : this.pin,
    createdAt: createdAt ?? this.createdAt,
  );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      avatarKey: data.avatarKey.present ? data.avatarKey.value : this.avatarKey,
      isKids: data.isKids.present ? data.isKids.value : this.isKids,
      pin: data.pin.present ? data.pin.value : this.pin,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarKey: $avatarKey, ')
          ..write('isKids: $isKids, ')
          ..write('pin: $pin, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, avatarKey, isKids, pin, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.id == this.id &&
          other.name == this.name &&
          other.avatarKey == this.avatarKey &&
          other.isKids == this.isKids &&
          other.pin == this.pin &&
          other.createdAt == this.createdAt);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> avatarKey;
  final Value<bool> isKids;
  final Value<String?> pin;
  final Value<DateTime> createdAt;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarKey = const Value.absent(),
    this.isKids = const Value.absent(),
    this.pin = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ProfilesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.avatarKey = const Value.absent(),
    this.isKids = const Value.absent(),
    this.pin = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Profile> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? avatarKey,
    Expression<bool>? isKids,
    Expression<String>? pin,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (avatarKey != null) 'avatar_key': avatarKey,
      if (isKids != null) 'is_kids': isKids,
      if (pin != null) 'pin': pin,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ProfilesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? avatarKey,
    Value<bool>? isKids,
    Value<String?>? pin,
    Value<DateTime>? createdAt,
  }) {
    return ProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarKey: avatarKey ?? this.avatarKey,
      isKids: isKids ?? this.isKids,
      pin: pin ?? this.pin,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatarKey.present) {
      map['avatar_key'] = Variable<String>(avatarKey.value);
    }
    if (isKids.present) {
      map['is_kids'] = Variable<bool>(isKids.value);
    }
    if (pin.present) {
      map['pin'] = Variable<String>(pin.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarKey: $avatarKey, ')
          ..write('isKids: $isKids, ')
          ..write('pin: $pin, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isHiddenMeta = const VerificationMeta(
    'isHidden',
  );
  @override
  late final GeneratedColumn<bool> isHidden = GeneratedColumn<bool>(
    'is_hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, type, isHidden];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('is_hidden')) {
      context.handle(
        _isHiddenMeta,
        isHidden.isAcceptableOrUnknown(data['is_hidden']!, _isHiddenMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, type};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      isHidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_hidden'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final String id;
  final String name;
  final String type;
  final bool isHidden;
  const Category({
    required this.id,
    required this.name,
    required this.type,
    required this.isHidden,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['is_hidden'] = Variable<bool>(isHidden);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      isHidden: Value(isHidden),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      isHidden: serializer.fromJson<bool>(json['isHidden']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'isHidden': serializer.toJson<bool>(isHidden),
    };
  }

  Category copyWith({String? id, String? name, String? type, bool? isHidden}) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        isHidden: isHidden ?? this.isHidden,
      );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      isHidden: data.isHidden.present ? data.isHidden.value : this.isHidden,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('isHidden: $isHidden')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, type, isHidden);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.isHidden == this.isHidden);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> type;
  final Value<bool> isHidden;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.isHidden = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required String name,
    required String type,
    this.isHidden = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       type = Value(type);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<bool>? isHidden,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (isHidden != null) 'is_hidden': isHidden,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? type,
    Value<bool>? isHidden,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isHidden: isHidden ?? this.isHidden,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (isHidden.present) {
      map['is_hidden'] = Variable<bool>(isHidden.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('isHidden: $isHidden, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChannelsTable extends Channels with TableInfo<$ChannelsTable, Channel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<int> streamId = GeneratedColumn<int>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _streamIconMeta = const VerificationMeta(
    'streamIcon',
  );
  @override
  late final GeneratedColumn<String> streamIcon = GeneratedColumn<String>(
    'stream_icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<String> year = GeneratedColumn<String>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedMeta = const VerificationMeta('added');
  @override
  late final GeneratedColumn<String> added = GeneratedColumn<String>(
    'added',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backdropPathMeta = const VerificationMeta(
    'backdropPath',
  );
  @override
  late final GeneratedColumn<String> backdropPath = GeneratedColumn<String>(
    'backdrop_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _youtubeTrailerMeta = const VerificationMeta(
    'youtubeTrailer',
  );
  @override
  late final GeneratedColumn<String> youtubeTrailer = GeneratedColumn<String>(
    'youtube_trailer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plotMeta = const VerificationMeta('plot');
  @override
  late final GeneratedColumn<String> plot = GeneratedColumn<String>(
    'plot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directorMeta = const VerificationMeta(
    'director',
  );
  @override
  late final GeneratedColumn<String> director = GeneratedColumn<String>(
    'director',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _castMeta = const VerificationMeta('cast');
  @override
  late final GeneratedColumn<String> cast = GeneratedColumn<String>(
    'cast',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _streamUrlMeta = const VerificationMeta(
    'streamUrl',
  );
  @override
  late final GeneratedColumn<String> streamUrl = GeneratedColumn<String>(
    'stream_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _epgChannelIdMeta = const VerificationMeta(
    'epgChannelId',
  );
  @override
  late final GeneratedColumn<String> epgChannelId = GeneratedColumn<String>(
    'epg_channel_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    streamId,
    name,
    type,
    categoryId,
    streamIcon,
    rating,
    year,
    added,
    backdropPath,
    youtubeTrailer,
    genre,
    plot,
    director,
    cast,
    streamUrl,
    epgChannelId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<Channel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('stream_icon')) {
      context.handle(
        _streamIconMeta,
        streamIcon.isAcceptableOrUnknown(data['stream_icon']!, _streamIconMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('added')) {
      context.handle(
        _addedMeta,
        added.isAcceptableOrUnknown(data['added']!, _addedMeta),
      );
    }
    if (data.containsKey('backdrop_path')) {
      context.handle(
        _backdropPathMeta,
        backdropPath.isAcceptableOrUnknown(
          data['backdrop_path']!,
          _backdropPathMeta,
        ),
      );
    }
    if (data.containsKey('youtube_trailer')) {
      context.handle(
        _youtubeTrailerMeta,
        youtubeTrailer.isAcceptableOrUnknown(
          data['youtube_trailer']!,
          _youtubeTrailerMeta,
        ),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('plot')) {
      context.handle(
        _plotMeta,
        plot.isAcceptableOrUnknown(data['plot']!, _plotMeta),
      );
    }
    if (data.containsKey('director')) {
      context.handle(
        _directorMeta,
        director.isAcceptableOrUnknown(data['director']!, _directorMeta),
      );
    }
    if (data.containsKey('cast')) {
      context.handle(
        _castMeta,
        cast.isAcceptableOrUnknown(data['cast']!, _castMeta),
      );
    }
    if (data.containsKey('stream_url')) {
      context.handle(
        _streamUrlMeta,
        streamUrl.isAcceptableOrUnknown(data['stream_url']!, _streamUrlMeta),
      );
    }
    if (data.containsKey('epg_channel_id')) {
      context.handle(
        _epgChannelIdMeta,
        epgChannelId.isAcceptableOrUnknown(
          data['epg_channel_id']!,
          _epgChannelIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {streamId, type};
  @override
  Channel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Channel(
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stream_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      streamIcon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_icon'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}year'],
      ),
      added: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added'],
      ),
      backdropPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backdrop_path'],
      ),
      youtubeTrailer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}youtube_trailer'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      plot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot'],
      ),
      director: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}director'],
      ),
      cast: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cast'],
      ),
      streamUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_url'],
      ),
      epgChannelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}epg_channel_id'],
      ),
    );
  }

  @override
  $ChannelsTable createAlias(String alias) {
    return $ChannelsTable(attachedDatabase, alias);
  }
}

class Channel extends DataClass implements Insertable<Channel> {
  final int streamId;
  final String name;
  final String type;
  final String categoryId;
  final String? streamIcon;
  final double? rating;
  final String? year;
  final String? added;
  final String? backdropPath;
  final String? youtubeTrailer;
  final String? genre;
  final String? plot;
  final String? director;
  final String? cast;
  final String? streamUrl;
  final String? epgChannelId;
  const Channel({
    required this.streamId,
    required this.name,
    required this.type,
    required this.categoryId,
    this.streamIcon,
    this.rating,
    this.year,
    this.added,
    this.backdropPath,
    this.youtubeTrailer,
    this.genre,
    this.plot,
    this.director,
    this.cast,
    this.streamUrl,
    this.epgChannelId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stream_id'] = Variable<int>(streamId);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['category_id'] = Variable<String>(categoryId);
    if (!nullToAbsent || streamIcon != null) {
      map['stream_icon'] = Variable<String>(streamIcon);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<double>(rating);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<String>(year);
    }
    if (!nullToAbsent || added != null) {
      map['added'] = Variable<String>(added);
    }
    if (!nullToAbsent || backdropPath != null) {
      map['backdrop_path'] = Variable<String>(backdropPath);
    }
    if (!nullToAbsent || youtubeTrailer != null) {
      map['youtube_trailer'] = Variable<String>(youtubeTrailer);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || plot != null) {
      map['plot'] = Variable<String>(plot);
    }
    if (!nullToAbsent || director != null) {
      map['director'] = Variable<String>(director);
    }
    if (!nullToAbsent || cast != null) {
      map['cast'] = Variable<String>(cast);
    }
    if (!nullToAbsent || streamUrl != null) {
      map['stream_url'] = Variable<String>(streamUrl);
    }
    if (!nullToAbsent || epgChannelId != null) {
      map['epg_channel_id'] = Variable<String>(epgChannelId);
    }
    return map;
  }

  ChannelsCompanion toCompanion(bool nullToAbsent) {
    return ChannelsCompanion(
      streamId: Value(streamId),
      name: Value(name),
      type: Value(type),
      categoryId: Value(categoryId),
      streamIcon: streamIcon == null && nullToAbsent
          ? const Value.absent()
          : Value(streamIcon),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      added: added == null && nullToAbsent
          ? const Value.absent()
          : Value(added),
      backdropPath: backdropPath == null && nullToAbsent
          ? const Value.absent()
          : Value(backdropPath),
      youtubeTrailer: youtubeTrailer == null && nullToAbsent
          ? const Value.absent()
          : Value(youtubeTrailer),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      plot: plot == null && nullToAbsent ? const Value.absent() : Value(plot),
      director: director == null && nullToAbsent
          ? const Value.absent()
          : Value(director),
      cast: cast == null && nullToAbsent ? const Value.absent() : Value(cast),
      streamUrl: streamUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(streamUrl),
      epgChannelId: epgChannelId == null && nullToAbsent
          ? const Value.absent()
          : Value(epgChannelId),
    );
  }

  factory Channel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Channel(
      streamId: serializer.fromJson<int>(json['streamId']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      streamIcon: serializer.fromJson<String?>(json['streamIcon']),
      rating: serializer.fromJson<double?>(json['rating']),
      year: serializer.fromJson<String?>(json['year']),
      added: serializer.fromJson<String?>(json['added']),
      backdropPath: serializer.fromJson<String?>(json['backdropPath']),
      youtubeTrailer: serializer.fromJson<String?>(json['youtubeTrailer']),
      genre: serializer.fromJson<String?>(json['genre']),
      plot: serializer.fromJson<String?>(json['plot']),
      director: serializer.fromJson<String?>(json['director']),
      cast: serializer.fromJson<String?>(json['cast']),
      streamUrl: serializer.fromJson<String?>(json['streamUrl']),
      epgChannelId: serializer.fromJson<String?>(json['epgChannelId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'streamId': serializer.toJson<int>(streamId),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'categoryId': serializer.toJson<String>(categoryId),
      'streamIcon': serializer.toJson<String?>(streamIcon),
      'rating': serializer.toJson<double?>(rating),
      'year': serializer.toJson<String?>(year),
      'added': serializer.toJson<String?>(added),
      'backdropPath': serializer.toJson<String?>(backdropPath),
      'youtubeTrailer': serializer.toJson<String?>(youtubeTrailer),
      'genre': serializer.toJson<String?>(genre),
      'plot': serializer.toJson<String?>(plot),
      'director': serializer.toJson<String?>(director),
      'cast': serializer.toJson<String?>(cast),
      'streamUrl': serializer.toJson<String?>(streamUrl),
      'epgChannelId': serializer.toJson<String?>(epgChannelId),
    };
  }

  Channel copyWith({
    int? streamId,
    String? name,
    String? type,
    String? categoryId,
    Value<String?> streamIcon = const Value.absent(),
    Value<double?> rating = const Value.absent(),
    Value<String?> year = const Value.absent(),
    Value<String?> added = const Value.absent(),
    Value<String?> backdropPath = const Value.absent(),
    Value<String?> youtubeTrailer = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<String?> plot = const Value.absent(),
    Value<String?> director = const Value.absent(),
    Value<String?> cast = const Value.absent(),
    Value<String?> streamUrl = const Value.absent(),
    Value<String?> epgChannelId = const Value.absent(),
  }) => Channel(
    streamId: streamId ?? this.streamId,
    name: name ?? this.name,
    type: type ?? this.type,
    categoryId: categoryId ?? this.categoryId,
    streamIcon: streamIcon.present ? streamIcon.value : this.streamIcon,
    rating: rating.present ? rating.value : this.rating,
    year: year.present ? year.value : this.year,
    added: added.present ? added.value : this.added,
    backdropPath: backdropPath.present ? backdropPath.value : this.backdropPath,
    youtubeTrailer: youtubeTrailer.present
        ? youtubeTrailer.value
        : this.youtubeTrailer,
    genre: genre.present ? genre.value : this.genre,
    plot: plot.present ? plot.value : this.plot,
    director: director.present ? director.value : this.director,
    cast: cast.present ? cast.value : this.cast,
    streamUrl: streamUrl.present ? streamUrl.value : this.streamUrl,
    epgChannelId: epgChannelId.present ? epgChannelId.value : this.epgChannelId,
  );
  Channel copyWithCompanion(ChannelsCompanion data) {
    return Channel(
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      streamIcon: data.streamIcon.present
          ? data.streamIcon.value
          : this.streamIcon,
      rating: data.rating.present ? data.rating.value : this.rating,
      year: data.year.present ? data.year.value : this.year,
      added: data.added.present ? data.added.value : this.added,
      backdropPath: data.backdropPath.present
          ? data.backdropPath.value
          : this.backdropPath,
      youtubeTrailer: data.youtubeTrailer.present
          ? data.youtubeTrailer.value
          : this.youtubeTrailer,
      genre: data.genre.present ? data.genre.value : this.genre,
      plot: data.plot.present ? data.plot.value : this.plot,
      director: data.director.present ? data.director.value : this.director,
      cast: data.cast.present ? data.cast.value : this.cast,
      streamUrl: data.streamUrl.present ? data.streamUrl.value : this.streamUrl,
      epgChannelId: data.epgChannelId.present
          ? data.epgChannelId.value
          : this.epgChannelId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Channel(')
          ..write('streamId: $streamId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('categoryId: $categoryId, ')
          ..write('streamIcon: $streamIcon, ')
          ..write('rating: $rating, ')
          ..write('year: $year, ')
          ..write('added: $added, ')
          ..write('backdropPath: $backdropPath, ')
          ..write('youtubeTrailer: $youtubeTrailer, ')
          ..write('genre: $genre, ')
          ..write('plot: $plot, ')
          ..write('director: $director, ')
          ..write('cast: $cast, ')
          ..write('streamUrl: $streamUrl, ')
          ..write('epgChannelId: $epgChannelId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    streamId,
    name,
    type,
    categoryId,
    streamIcon,
    rating,
    year,
    added,
    backdropPath,
    youtubeTrailer,
    genre,
    plot,
    director,
    cast,
    streamUrl,
    epgChannelId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Channel &&
          other.streamId == this.streamId &&
          other.name == this.name &&
          other.type == this.type &&
          other.categoryId == this.categoryId &&
          other.streamIcon == this.streamIcon &&
          other.rating == this.rating &&
          other.year == this.year &&
          other.added == this.added &&
          other.backdropPath == this.backdropPath &&
          other.youtubeTrailer == this.youtubeTrailer &&
          other.genre == this.genre &&
          other.plot == this.plot &&
          other.director == this.director &&
          other.cast == this.cast &&
          other.streamUrl == this.streamUrl &&
          other.epgChannelId == this.epgChannelId);
}

class ChannelsCompanion extends UpdateCompanion<Channel> {
  final Value<int> streamId;
  final Value<String> name;
  final Value<String> type;
  final Value<String> categoryId;
  final Value<String?> streamIcon;
  final Value<double?> rating;
  final Value<String?> year;
  final Value<String?> added;
  final Value<String?> backdropPath;
  final Value<String?> youtubeTrailer;
  final Value<String?> genre;
  final Value<String?> plot;
  final Value<String?> director;
  final Value<String?> cast;
  final Value<String?> streamUrl;
  final Value<String?> epgChannelId;
  final Value<int> rowid;
  const ChannelsCompanion({
    this.streamId = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.streamIcon = const Value.absent(),
    this.rating = const Value.absent(),
    this.year = const Value.absent(),
    this.added = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.youtubeTrailer = const Value.absent(),
    this.genre = const Value.absent(),
    this.plot = const Value.absent(),
    this.director = const Value.absent(),
    this.cast = const Value.absent(),
    this.streamUrl = const Value.absent(),
    this.epgChannelId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelsCompanion.insert({
    required int streamId,
    required String name,
    required String type,
    required String categoryId,
    this.streamIcon = const Value.absent(),
    this.rating = const Value.absent(),
    this.year = const Value.absent(),
    this.added = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.youtubeTrailer = const Value.absent(),
    this.genre = const Value.absent(),
    this.plot = const Value.absent(),
    this.director = const Value.absent(),
    this.cast = const Value.absent(),
    this.streamUrl = const Value.absent(),
    this.epgChannelId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : streamId = Value(streamId),
       name = Value(name),
       type = Value(type),
       categoryId = Value(categoryId);
  static Insertable<Channel> custom({
    Expression<int>? streamId,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? categoryId,
    Expression<String>? streamIcon,
    Expression<double>? rating,
    Expression<String>? year,
    Expression<String>? added,
    Expression<String>? backdropPath,
    Expression<String>? youtubeTrailer,
    Expression<String>? genre,
    Expression<String>? plot,
    Expression<String>? director,
    Expression<String>? cast,
    Expression<String>? streamUrl,
    Expression<String>? epgChannelId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (streamId != null) 'stream_id': streamId,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (categoryId != null) 'category_id': categoryId,
      if (streamIcon != null) 'stream_icon': streamIcon,
      if (rating != null) 'rating': rating,
      if (year != null) 'year': year,
      if (added != null) 'added': added,
      if (backdropPath != null) 'backdrop_path': backdropPath,
      if (youtubeTrailer != null) 'youtube_trailer': youtubeTrailer,
      if (genre != null) 'genre': genre,
      if (plot != null) 'plot': plot,
      if (director != null) 'director': director,
      if (cast != null) 'cast': cast,
      if (streamUrl != null) 'stream_url': streamUrl,
      if (epgChannelId != null) 'epg_channel_id': epgChannelId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelsCompanion copyWith({
    Value<int>? streamId,
    Value<String>? name,
    Value<String>? type,
    Value<String>? categoryId,
    Value<String?>? streamIcon,
    Value<double?>? rating,
    Value<String?>? year,
    Value<String?>? added,
    Value<String?>? backdropPath,
    Value<String?>? youtubeTrailer,
    Value<String?>? genre,
    Value<String?>? plot,
    Value<String?>? director,
    Value<String?>? cast,
    Value<String?>? streamUrl,
    Value<String?>? epgChannelId,
    Value<int>? rowid,
  }) {
    return ChannelsCompanion(
      streamId: streamId ?? this.streamId,
      name: name ?? this.name,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      streamIcon: streamIcon ?? this.streamIcon,
      rating: rating ?? this.rating,
      year: year ?? this.year,
      added: added ?? this.added,
      backdropPath: backdropPath ?? this.backdropPath,
      youtubeTrailer: youtubeTrailer ?? this.youtubeTrailer,
      genre: genre ?? this.genre,
      plot: plot ?? this.plot,
      director: director ?? this.director,
      cast: cast ?? this.cast,
      streamUrl: streamUrl ?? this.streamUrl,
      epgChannelId: epgChannelId ?? this.epgChannelId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (streamId.present) {
      map['stream_id'] = Variable<int>(streamId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (streamIcon.present) {
      map['stream_icon'] = Variable<String>(streamIcon.value);
    }
    if (rating.present) {
      map['rating'] = Variable<double>(rating.value);
    }
    if (year.present) {
      map['year'] = Variable<String>(year.value);
    }
    if (added.present) {
      map['added'] = Variable<String>(added.value);
    }
    if (backdropPath.present) {
      map['backdrop_path'] = Variable<String>(backdropPath.value);
    }
    if (youtubeTrailer.present) {
      map['youtube_trailer'] = Variable<String>(youtubeTrailer.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (plot.present) {
      map['plot'] = Variable<String>(plot.value);
    }
    if (director.present) {
      map['director'] = Variable<String>(director.value);
    }
    if (cast.present) {
      map['cast'] = Variable<String>(cast.value);
    }
    if (streamUrl.present) {
      map['stream_url'] = Variable<String>(streamUrl.value);
    }
    if (epgChannelId.present) {
      map['epg_channel_id'] = Variable<String>(epgChannelId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelsCompanion(')
          ..write('streamId: $streamId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('categoryId: $categoryId, ')
          ..write('streamIcon: $streamIcon, ')
          ..write('rating: $rating, ')
          ..write('year: $year, ')
          ..write('added: $added, ')
          ..write('backdropPath: $backdropPath, ')
          ..write('youtubeTrailer: $youtubeTrailer, ')
          ..write('genre: $genre, ')
          ..write('plot: $plot, ')
          ..write('director: $director, ')
          ..write('cast: $cast, ')
          ..write('streamUrl: $streamUrl, ')
          ..write('epgChannelId: $epgChannelId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgramsTable extends Programs with TableInfo<$ProgramsTable, Program> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgramsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _channelIdMeta = const VerificationMeta(
    'channelId',
  );
  @override
  late final GeneratedColumn<int> channelId = GeneratedColumn<int>(
    'channel_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES channels (stream_id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startMeta = const VerificationMeta('start');
  @override
  late final GeneratedColumn<DateTime> start = GeneratedColumn<DateTime>(
    'start',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stopMeta = const VerificationMeta('stop');
  @override
  late final GeneratedColumn<DateTime> stop = GeneratedColumn<DateTime>(
    'stop',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    channelId,
    title,
    description,
    start,
    stop,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'programs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Program> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('channel_id')) {
      context.handle(
        _channelIdMeta,
        channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_channelIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('start')) {
      context.handle(
        _startMeta,
        start.isAcceptableOrUnknown(data['start']!, _startMeta),
      );
    } else if (isInserting) {
      context.missing(_startMeta);
    }
    if (data.containsKey('stop')) {
      context.handle(
        _stopMeta,
        stop.isAcceptableOrUnknown(data['stop']!, _stopMeta),
      );
    } else if (isInserting) {
      context.missing(_stopMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Program map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Program(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      channelId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}channel_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      start: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start'],
      )!,
      stop: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}stop'],
      )!,
    );
  }

  @override
  $ProgramsTable createAlias(String alias) {
    return $ProgramsTable(attachedDatabase, alias);
  }
}

class Program extends DataClass implements Insertable<Program> {
  final int id;
  final int channelId;
  final String title;
  final String? description;
  final DateTime start;
  final DateTime stop;
  const Program({
    required this.id,
    required this.channelId,
    required this.title,
    this.description,
    required this.start,
    required this.stop,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['channel_id'] = Variable<int>(channelId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['start'] = Variable<DateTime>(start);
    map['stop'] = Variable<DateTime>(stop);
    return map;
  }

  ProgramsCompanion toCompanion(bool nullToAbsent) {
    return ProgramsCompanion(
      id: Value(id),
      channelId: Value(channelId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      start: Value(start),
      stop: Value(stop),
    );
  }

  factory Program.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Program(
      id: serializer.fromJson<int>(json['id']),
      channelId: serializer.fromJson<int>(json['channelId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      start: serializer.fromJson<DateTime>(json['start']),
      stop: serializer.fromJson<DateTime>(json['stop']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'channelId': serializer.toJson<int>(channelId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'start': serializer.toJson<DateTime>(start),
      'stop': serializer.toJson<DateTime>(stop),
    };
  }

  Program copyWith({
    int? id,
    int? channelId,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? start,
    DateTime? stop,
  }) => Program(
    id: id ?? this.id,
    channelId: channelId ?? this.channelId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    start: start ?? this.start,
    stop: stop ?? this.stop,
  );
  Program copyWithCompanion(ProgramsCompanion data) {
    return Program(
      id: data.id.present ? data.id.value : this.id,
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      start: data.start.present ? data.start.value : this.start,
      stop: data.stop.present ? data.stop.value : this.stop,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Program(')
          ..write('id: $id, ')
          ..write('channelId: $channelId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('start: $start, ')
          ..write('stop: $stop')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, channelId, title, description, start, stop);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Program &&
          other.id == this.id &&
          other.channelId == this.channelId &&
          other.title == this.title &&
          other.description == this.description &&
          other.start == this.start &&
          other.stop == this.stop);
}

class ProgramsCompanion extends UpdateCompanion<Program> {
  final Value<int> id;
  final Value<int> channelId;
  final Value<String> title;
  final Value<String?> description;
  final Value<DateTime> start;
  final Value<DateTime> stop;
  const ProgramsCompanion({
    this.id = const Value.absent(),
    this.channelId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.start = const Value.absent(),
    this.stop = const Value.absent(),
  });
  ProgramsCompanion.insert({
    this.id = const Value.absent(),
    required int channelId,
    required String title,
    this.description = const Value.absent(),
    required DateTime start,
    required DateTime stop,
  }) : channelId = Value(channelId),
       title = Value(title),
       start = Value(start),
       stop = Value(stop);
  static Insertable<Program> custom({
    Expression<int>? id,
    Expression<int>? channelId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<DateTime>? start,
    Expression<DateTime>? stop,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (channelId != null) 'channel_id': channelId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (start != null) 'start': start,
      if (stop != null) 'stop': stop,
    });
  }

  ProgramsCompanion copyWith({
    Value<int>? id,
    Value<int>? channelId,
    Value<String>? title,
    Value<String?>? description,
    Value<DateTime>? start,
    Value<DateTime>? stop,
  }) {
    return ProgramsCompanion(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      title: title ?? this.title,
      description: description ?? this.description,
      start: start ?? this.start,
      stop: stop ?? this.stop,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (channelId.present) {
      map['channel_id'] = Variable<int>(channelId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (start.present) {
      map['start'] = Variable<DateTime>(start.value);
    }
    if (stop.present) {
      map['stop'] = Variable<DateTime>(stop.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgramsCompanion(')
          ..write('id: $id, ')
          ..write('channelId: $channelId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('start: $start, ')
          ..write('stop: $stop')
          ..write(')'))
        .toString();
  }
}

class $PlaybackProgressTable extends PlaybackProgress
    with TableInfo<$PlaybackProgressTable, PlaybackProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<int> streamId = GeneratedColumn<int>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMeta = const VerificationMeta(
    'duration',
  );
  @override
  late final GeneratedColumn<int> duration = GeneratedColumn<int>(
    'duration',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _isFinishedMeta = const VerificationMeta(
    'isFinished',
  );
  @override
  late final GeneratedColumn<bool> isFinished = GeneratedColumn<bool>(
    'is_finished',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_finished" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<int> profileId = GeneratedColumn<int>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    streamId,
    type,
    position,
    duration,
    updatedAt,
    isFinished,
    profileId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaybackProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('duration')) {
      context.handle(
        _durationMeta,
        duration.isAcceptableOrUnknown(data['duration']!, _durationMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('is_finished')) {
      context.handle(
        _isFinishedMeta,
        isFinished.isAcceptableOrUnknown(data['is_finished']!, _isFinishedMeta),
      );
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {streamId, type, profileId};
  @override
  PlaybackProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackProgressData(
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stream_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      duration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isFinished: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_finished'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_id'],
      )!,
    );
  }

  @override
  $PlaybackProgressTable createAlias(String alias) {
    return $PlaybackProgressTable(attachedDatabase, alias);
  }
}

class PlaybackProgressData extends DataClass
    implements Insertable<PlaybackProgressData> {
  final int streamId;
  final String type;
  final int position;
  final int duration;
  final DateTime updatedAt;
  final bool isFinished;

  /// Owning profile. See [Favorites.profileId] for rationale.
  final int profileId;
  const PlaybackProgressData({
    required this.streamId,
    required this.type,
    required this.position,
    required this.duration,
    required this.updatedAt,
    required this.isFinished,
    required this.profileId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stream_id'] = Variable<int>(streamId);
    map['type'] = Variable<String>(type);
    map['position'] = Variable<int>(position);
    map['duration'] = Variable<int>(duration);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_finished'] = Variable<bool>(isFinished);
    map['profile_id'] = Variable<int>(profileId);
    return map;
  }

  PlaybackProgressCompanion toCompanion(bool nullToAbsent) {
    return PlaybackProgressCompanion(
      streamId: Value(streamId),
      type: Value(type),
      position: Value(position),
      duration: Value(duration),
      updatedAt: Value(updatedAt),
      isFinished: Value(isFinished),
      profileId: Value(profileId),
    );
  }

  factory PlaybackProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackProgressData(
      streamId: serializer.fromJson<int>(json['streamId']),
      type: serializer.fromJson<String>(json['type']),
      position: serializer.fromJson<int>(json['position']),
      duration: serializer.fromJson<int>(json['duration']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isFinished: serializer.fromJson<bool>(json['isFinished']),
      profileId: serializer.fromJson<int>(json['profileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'streamId': serializer.toJson<int>(streamId),
      'type': serializer.toJson<String>(type),
      'position': serializer.toJson<int>(position),
      'duration': serializer.toJson<int>(duration),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isFinished': serializer.toJson<bool>(isFinished),
      'profileId': serializer.toJson<int>(profileId),
    };
  }

  PlaybackProgressData copyWith({
    int? streamId,
    String? type,
    int? position,
    int? duration,
    DateTime? updatedAt,
    bool? isFinished,
    int? profileId,
  }) => PlaybackProgressData(
    streamId: streamId ?? this.streamId,
    type: type ?? this.type,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    updatedAt: updatedAt ?? this.updatedAt,
    isFinished: isFinished ?? this.isFinished,
    profileId: profileId ?? this.profileId,
  );
  PlaybackProgressData copyWithCompanion(PlaybackProgressCompanion data) {
    return PlaybackProgressData(
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      type: data.type.present ? data.type.value : this.type,
      position: data.position.present ? data.position.value : this.position,
      duration: data.duration.present ? data.duration.value : this.duration,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isFinished: data.isFinished.present
          ? data.isFinished.value
          : this.isFinished,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackProgressData(')
          ..write('streamId: $streamId, ')
          ..write('type: $type, ')
          ..write('position: $position, ')
          ..write('duration: $duration, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isFinished: $isFinished, ')
          ..write('profileId: $profileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    streamId,
    type,
    position,
    duration,
    updatedAt,
    isFinished,
    profileId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackProgressData &&
          other.streamId == this.streamId &&
          other.type == this.type &&
          other.position == this.position &&
          other.duration == this.duration &&
          other.updatedAt == this.updatedAt &&
          other.isFinished == this.isFinished &&
          other.profileId == this.profileId);
}

class PlaybackProgressCompanion extends UpdateCompanion<PlaybackProgressData> {
  final Value<int> streamId;
  final Value<String> type;
  final Value<int> position;
  final Value<int> duration;
  final Value<DateTime> updatedAt;
  final Value<bool> isFinished;
  final Value<int> profileId;
  final Value<int> rowid;
  const PlaybackProgressCompanion({
    this.streamId = const Value.absent(),
    this.type = const Value.absent(),
    this.position = const Value.absent(),
    this.duration = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isFinished = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaybackProgressCompanion.insert({
    required int streamId,
    required String type,
    required int position,
    required int duration,
    this.updatedAt = const Value.absent(),
    this.isFinished = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : streamId = Value(streamId),
       type = Value(type),
       position = Value(position),
       duration = Value(duration);
  static Insertable<PlaybackProgressData> custom({
    Expression<int>? streamId,
    Expression<String>? type,
    Expression<int>? position,
    Expression<int>? duration,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isFinished,
    Expression<int>? profileId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (streamId != null) 'stream_id': streamId,
      if (type != null) 'type': type,
      if (position != null) 'position': position,
      if (duration != null) 'duration': duration,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isFinished != null) 'is_finished': isFinished,
      if (profileId != null) 'profile_id': profileId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaybackProgressCompanion copyWith({
    Value<int>? streamId,
    Value<String>? type,
    Value<int>? position,
    Value<int>? duration,
    Value<DateTime>? updatedAt,
    Value<bool>? isFinished,
    Value<int>? profileId,
    Value<int>? rowid,
  }) {
    return PlaybackProgressCompanion(
      streamId: streamId ?? this.streamId,
      type: type ?? this.type,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      updatedAt: updatedAt ?? this.updatedAt,
      isFinished: isFinished ?? this.isFinished,
      profileId: profileId ?? this.profileId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (streamId.present) {
      map['stream_id'] = Variable<int>(streamId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (duration.present) {
      map['duration'] = Variable<int>(duration.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isFinished.present) {
      map['is_finished'] = Variable<bool>(isFinished.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<int>(profileId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackProgressCompanion(')
          ..write('streamId: $streamId, ')
          ..write('type: $type, ')
          ..write('position: $position, ')
          ..write('duration: $duration, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isFinished: $isFinished, ')
          ..write('profileId: $profileId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoritesTable extends Favorites
    with TableInfo<$FavoritesTable, Favorite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<int> streamId = GeneratedColumn<int>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streamTypeMeta = const VerificationMeta(
    'streamType',
  );
  @override
  late final GeneratedColumn<String> streamType = GeneratedColumn<String>(
    'stream_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbnailMeta = const VerificationMeta(
    'thumbnail',
  );
  @override
  late final GeneratedColumn<String> thumbnail = GeneratedColumn<String>(
    'thumbnail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<int> profileId = GeneratedColumn<int>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    streamId,
    streamType,
    name,
    thumbnail,
    addedAt,
    profileId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorites';
  @override
  VerificationContext validateIntegrity(
    Insertable<Favorite> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('stream_type')) {
      context.handle(
        _streamTypeMeta,
        streamType.isAcceptableOrUnknown(data['stream_type']!, _streamTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_streamTypeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('thumbnail')) {
      context.handle(
        _thumbnailMeta,
        thumbnail.isAcceptableOrUnknown(data['thumbnail']!, _thumbnailMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {streamId, streamType, profileId};
  @override
  Favorite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Favorite(
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stream_id'],
      )!,
      streamType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      thumbnail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_id'],
      )!,
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }
}

class Favorite extends DataClass implements Insertable<Favorite> {
  final int streamId;
  final String streamType;
  final String name;
  final String? thumbnail;
  final DateTime addedAt;

  /// Owning profile. Drift v18 migration backfills every existing row
  /// to profileId=1 (the seeded "Varsayılan" profile) so single-user
  /// installs upgrade in place. Added to the primary key so the same
  /// title can independently appear in two profiles' favourites.
  final int profileId;
  const Favorite({
    required this.streamId,
    required this.streamType,
    required this.name,
    this.thumbnail,
    required this.addedAt,
    required this.profileId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stream_id'] = Variable<int>(streamId);
    map['stream_type'] = Variable<String>(streamType);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || thumbnail != null) {
      map['thumbnail'] = Variable<String>(thumbnail);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    map['profile_id'] = Variable<int>(profileId);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      streamId: Value(streamId),
      streamType: Value(streamType),
      name: Value(name),
      thumbnail: thumbnail == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnail),
      addedAt: Value(addedAt),
      profileId: Value(profileId),
    );
  }

  factory Favorite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Favorite(
      streamId: serializer.fromJson<int>(json['streamId']),
      streamType: serializer.fromJson<String>(json['streamType']),
      name: serializer.fromJson<String>(json['name']),
      thumbnail: serializer.fromJson<String?>(json['thumbnail']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      profileId: serializer.fromJson<int>(json['profileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'streamId': serializer.toJson<int>(streamId),
      'streamType': serializer.toJson<String>(streamType),
      'name': serializer.toJson<String>(name),
      'thumbnail': serializer.toJson<String?>(thumbnail),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'profileId': serializer.toJson<int>(profileId),
    };
  }

  Favorite copyWith({
    int? streamId,
    String? streamType,
    String? name,
    Value<String?> thumbnail = const Value.absent(),
    DateTime? addedAt,
    int? profileId,
  }) => Favorite(
    streamId: streamId ?? this.streamId,
    streamType: streamType ?? this.streamType,
    name: name ?? this.name,
    thumbnail: thumbnail.present ? thumbnail.value : this.thumbnail,
    addedAt: addedAt ?? this.addedAt,
    profileId: profileId ?? this.profileId,
  );
  Favorite copyWithCompanion(FavoritesCompanion data) {
    return Favorite(
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      streamType: data.streamType.present
          ? data.streamType.value
          : this.streamType,
      name: data.name.present ? data.name.value : this.name,
      thumbnail: data.thumbnail.present ? data.thumbnail.value : this.thumbnail,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Favorite(')
          ..write('streamId: $streamId, ')
          ..write('streamType: $streamType, ')
          ..write('name: $name, ')
          ..write('thumbnail: $thumbnail, ')
          ..write('addedAt: $addedAt, ')
          ..write('profileId: $profileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(streamId, streamType, name, thumbnail, addedAt, profileId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Favorite &&
          other.streamId == this.streamId &&
          other.streamType == this.streamType &&
          other.name == this.name &&
          other.thumbnail == this.thumbnail &&
          other.addedAt == this.addedAt &&
          other.profileId == this.profileId);
}

class FavoritesCompanion extends UpdateCompanion<Favorite> {
  final Value<int> streamId;
  final Value<String> streamType;
  final Value<String> name;
  final Value<String?> thumbnail;
  final Value<DateTime> addedAt;
  final Value<int> profileId;
  final Value<int> rowid;
  const FavoritesCompanion({
    this.streamId = const Value.absent(),
    this.streamType = const Value.absent(),
    this.name = const Value.absent(),
    this.thumbnail = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required int streamId,
    required String streamType,
    required String name,
    this.thumbnail = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : streamId = Value(streamId),
       streamType = Value(streamType),
       name = Value(name);
  static Insertable<Favorite> custom({
    Expression<int>? streamId,
    Expression<String>? streamType,
    Expression<String>? name,
    Expression<String>? thumbnail,
    Expression<DateTime>? addedAt,
    Expression<int>? profileId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (streamId != null) 'stream_id': streamId,
      if (streamType != null) 'stream_type': streamType,
      if (name != null) 'name': name,
      if (thumbnail != null) 'thumbnail': thumbnail,
      if (addedAt != null) 'added_at': addedAt,
      if (profileId != null) 'profile_id': profileId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoritesCompanion copyWith({
    Value<int>? streamId,
    Value<String>? streamType,
    Value<String>? name,
    Value<String?>? thumbnail,
    Value<DateTime>? addedAt,
    Value<int>? profileId,
    Value<int>? rowid,
  }) {
    return FavoritesCompanion(
      streamId: streamId ?? this.streamId,
      streamType: streamType ?? this.streamType,
      name: name ?? this.name,
      thumbnail: thumbnail ?? this.thumbnail,
      addedAt: addedAt ?? this.addedAt,
      profileId: profileId ?? this.profileId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (streamId.present) {
      map['stream_id'] = Variable<int>(streamId.value);
    }
    if (streamType.present) {
      map['stream_type'] = Variable<String>(streamType.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (thumbnail.present) {
      map['thumbnail'] = Variable<String>(thumbnail.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<int>(profileId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('streamId: $streamId, ')
          ..write('streamType: $streamType, ')
          ..write('name: $name, ')
          ..write('thumbnail: $thumbnail, ')
          ..write('addedAt: $addedAt, ')
          ..write('profileId: $profileId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchlistTable extends Watchlist
    with TableInfo<$WatchlistTable, WatchlistData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchlistTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<int> streamId = GeneratedColumn<int>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streamTypeMeta = const VerificationMeta(
    'streamType',
  );
  @override
  late final GeneratedColumn<String> streamType = GeneratedColumn<String>(
    'stream_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbnailMeta = const VerificationMeta(
    'thumbnail',
  );
  @override
  late final GeneratedColumn<String> thumbnail = GeneratedColumn<String>(
    'thumbnail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<int> profileId = GeneratedColumn<int>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    streamId,
    streamType,
    name,
    thumbnail,
    addedAt,
    profileId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watchlist';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchlistData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('stream_type')) {
      context.handle(
        _streamTypeMeta,
        streamType.isAcceptableOrUnknown(data['stream_type']!, _streamTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_streamTypeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('thumbnail')) {
      context.handle(
        _thumbnailMeta,
        thumbnail.isAcceptableOrUnknown(data['thumbnail']!, _thumbnailMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {streamId, streamType, profileId};
  @override
  WatchlistData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchlistData(
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stream_id'],
      )!,
      streamType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      thumbnail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_id'],
      )!,
    );
  }

  @override
  $WatchlistTable createAlias(String alias) {
    return $WatchlistTable(attachedDatabase, alias);
  }
}

class WatchlistData extends DataClass implements Insertable<WatchlistData> {
  final int streamId;
  final String streamType;
  final String name;
  final String? thumbnail;
  final DateTime addedAt;

  /// Owning profile. See [Favorites.profileId].
  final int profileId;
  const WatchlistData({
    required this.streamId,
    required this.streamType,
    required this.name,
    this.thumbnail,
    required this.addedAt,
    required this.profileId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stream_id'] = Variable<int>(streamId);
    map['stream_type'] = Variable<String>(streamType);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || thumbnail != null) {
      map['thumbnail'] = Variable<String>(thumbnail);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    map['profile_id'] = Variable<int>(profileId);
    return map;
  }

  WatchlistCompanion toCompanion(bool nullToAbsent) {
    return WatchlistCompanion(
      streamId: Value(streamId),
      streamType: Value(streamType),
      name: Value(name),
      thumbnail: thumbnail == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnail),
      addedAt: Value(addedAt),
      profileId: Value(profileId),
    );
  }

  factory WatchlistData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchlistData(
      streamId: serializer.fromJson<int>(json['streamId']),
      streamType: serializer.fromJson<String>(json['streamType']),
      name: serializer.fromJson<String>(json['name']),
      thumbnail: serializer.fromJson<String?>(json['thumbnail']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      profileId: serializer.fromJson<int>(json['profileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'streamId': serializer.toJson<int>(streamId),
      'streamType': serializer.toJson<String>(streamType),
      'name': serializer.toJson<String>(name),
      'thumbnail': serializer.toJson<String?>(thumbnail),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'profileId': serializer.toJson<int>(profileId),
    };
  }

  WatchlistData copyWith({
    int? streamId,
    String? streamType,
    String? name,
    Value<String?> thumbnail = const Value.absent(),
    DateTime? addedAt,
    int? profileId,
  }) => WatchlistData(
    streamId: streamId ?? this.streamId,
    streamType: streamType ?? this.streamType,
    name: name ?? this.name,
    thumbnail: thumbnail.present ? thumbnail.value : this.thumbnail,
    addedAt: addedAt ?? this.addedAt,
    profileId: profileId ?? this.profileId,
  );
  WatchlistData copyWithCompanion(WatchlistCompanion data) {
    return WatchlistData(
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      streamType: data.streamType.present
          ? data.streamType.value
          : this.streamType,
      name: data.name.present ? data.name.value : this.name,
      thumbnail: data.thumbnail.present ? data.thumbnail.value : this.thumbnail,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchlistData(')
          ..write('streamId: $streamId, ')
          ..write('streamType: $streamType, ')
          ..write('name: $name, ')
          ..write('thumbnail: $thumbnail, ')
          ..write('addedAt: $addedAt, ')
          ..write('profileId: $profileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(streamId, streamType, name, thumbnail, addedAt, profileId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchlistData &&
          other.streamId == this.streamId &&
          other.streamType == this.streamType &&
          other.name == this.name &&
          other.thumbnail == this.thumbnail &&
          other.addedAt == this.addedAt &&
          other.profileId == this.profileId);
}

class WatchlistCompanion extends UpdateCompanion<WatchlistData> {
  final Value<int> streamId;
  final Value<String> streamType;
  final Value<String> name;
  final Value<String?> thumbnail;
  final Value<DateTime> addedAt;
  final Value<int> profileId;
  final Value<int> rowid;
  const WatchlistCompanion({
    this.streamId = const Value.absent(),
    this.streamType = const Value.absent(),
    this.name = const Value.absent(),
    this.thumbnail = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchlistCompanion.insert({
    required int streamId,
    required String streamType,
    required String name,
    this.thumbnail = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : streamId = Value(streamId),
       streamType = Value(streamType),
       name = Value(name);
  static Insertable<WatchlistData> custom({
    Expression<int>? streamId,
    Expression<String>? streamType,
    Expression<String>? name,
    Expression<String>? thumbnail,
    Expression<DateTime>? addedAt,
    Expression<int>? profileId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (streamId != null) 'stream_id': streamId,
      if (streamType != null) 'stream_type': streamType,
      if (name != null) 'name': name,
      if (thumbnail != null) 'thumbnail': thumbnail,
      if (addedAt != null) 'added_at': addedAt,
      if (profileId != null) 'profile_id': profileId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchlistCompanion copyWith({
    Value<int>? streamId,
    Value<String>? streamType,
    Value<String>? name,
    Value<String?>? thumbnail,
    Value<DateTime>? addedAt,
    Value<int>? profileId,
    Value<int>? rowid,
  }) {
    return WatchlistCompanion(
      streamId: streamId ?? this.streamId,
      streamType: streamType ?? this.streamType,
      name: name ?? this.name,
      thumbnail: thumbnail ?? this.thumbnail,
      addedAt: addedAt ?? this.addedAt,
      profileId: profileId ?? this.profileId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (streamId.present) {
      map['stream_id'] = Variable<int>(streamId.value);
    }
    if (streamType.present) {
      map['stream_type'] = Variable<String>(streamType.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (thumbnail.present) {
      map['thumbnail'] = Variable<String>(thumbnail.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<int>(profileId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchlistCompanion(')
          ..write('streamId: $streamId, ')
          ..write('streamType: $streamType, ')
          ..write('name: $name, ')
          ..write('thumbnail: $thumbnail, ')
          ..write('addedAt: $addedAt, ')
          ..write('profileId: $profileId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeriesTrackingTable extends SeriesTracking
    with TableInfo<$SeriesTrackingTable, SeriesTrackingData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesTrackingTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<int> seriesId = GeneratedColumn<int>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _knownEpisodeCountMeta = const VerificationMeta(
    'knownEpisodeCount',
  );
  @override
  late final GeneratedColumn<int> knownEpisodeCount = GeneratedColumn<int>(
    'known_episode_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _newEpisodeCountMeta = const VerificationMeta(
    'newEpisodeCount',
  );
  @override
  late final GeneratedColumn<int> newEpisodeCount = GeneratedColumn<int>(
    'new_episode_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _hasNewEpisodesMeta = const VerificationMeta(
    'hasNewEpisodes',
  );
  @override
  late final GeneratedColumn<bool> hasNewEpisodes = GeneratedColumn<bool>(
    'has_new_episodes',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_new_episodes" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastCheckedAtMeta = const VerificationMeta(
    'lastCheckedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastCheckedAt =
      GeneratedColumn<DateTime>(
        'last_checked_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: currentDateAndTime,
      );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<int> profileId = GeneratedColumn<int>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    seriesId,
    knownEpisodeCount,
    newEpisodeCount,
    hasNewEpisodes,
    lastCheckedAt,
    profileId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series_tracking';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeriesTrackingData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('known_episode_count')) {
      context.handle(
        _knownEpisodeCountMeta,
        knownEpisodeCount.isAcceptableOrUnknown(
          data['known_episode_count']!,
          _knownEpisodeCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_knownEpisodeCountMeta);
    }
    if (data.containsKey('new_episode_count')) {
      context.handle(
        _newEpisodeCountMeta,
        newEpisodeCount.isAcceptableOrUnknown(
          data['new_episode_count']!,
          _newEpisodeCountMeta,
        ),
      );
    }
    if (data.containsKey('has_new_episodes')) {
      context.handle(
        _hasNewEpisodesMeta,
        hasNewEpisodes.isAcceptableOrUnknown(
          data['has_new_episodes']!,
          _hasNewEpisodesMeta,
        ),
      );
    }
    if (data.containsKey('last_checked_at')) {
      context.handle(
        _lastCheckedAtMeta,
        lastCheckedAt.isAcceptableOrUnknown(
          data['last_checked_at']!,
          _lastCheckedAtMeta,
        ),
      );
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seriesId, profileId};
  @override
  SeriesTrackingData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeriesTrackingData(
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}series_id'],
      )!,
      knownEpisodeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}known_episode_count'],
      )!,
      newEpisodeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}new_episode_count'],
      )!,
      hasNewEpisodes: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_new_episodes'],
      )!,
      lastCheckedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_checked_at'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_id'],
      )!,
    );
  }

  @override
  $SeriesTrackingTable createAlias(String alias) {
    return $SeriesTrackingTable(attachedDatabase, alias);
  }
}

class SeriesTrackingData extends DataClass
    implements Insertable<SeriesTrackingData> {
  final int seriesId;
  final int knownEpisodeCount;
  final int newEpisodeCount;
  final bool hasNewEpisodes;
  final DateTime lastCheckedAt;

  /// Owning profile. Different profiles can be at different episode
  /// counts on the same series — kids may finish a season faster
  /// than the parent.
  final int profileId;
  const SeriesTrackingData({
    required this.seriesId,
    required this.knownEpisodeCount,
    required this.newEpisodeCount,
    required this.hasNewEpisodes,
    required this.lastCheckedAt,
    required this.profileId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['series_id'] = Variable<int>(seriesId);
    map['known_episode_count'] = Variable<int>(knownEpisodeCount);
    map['new_episode_count'] = Variable<int>(newEpisodeCount);
    map['has_new_episodes'] = Variable<bool>(hasNewEpisodes);
    map['last_checked_at'] = Variable<DateTime>(lastCheckedAt);
    map['profile_id'] = Variable<int>(profileId);
    return map;
  }

  SeriesTrackingCompanion toCompanion(bool nullToAbsent) {
    return SeriesTrackingCompanion(
      seriesId: Value(seriesId),
      knownEpisodeCount: Value(knownEpisodeCount),
      newEpisodeCount: Value(newEpisodeCount),
      hasNewEpisodes: Value(hasNewEpisodes),
      lastCheckedAt: Value(lastCheckedAt),
      profileId: Value(profileId),
    );
  }

  factory SeriesTrackingData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeriesTrackingData(
      seriesId: serializer.fromJson<int>(json['seriesId']),
      knownEpisodeCount: serializer.fromJson<int>(json['knownEpisodeCount']),
      newEpisodeCount: serializer.fromJson<int>(json['newEpisodeCount']),
      hasNewEpisodes: serializer.fromJson<bool>(json['hasNewEpisodes']),
      lastCheckedAt: serializer.fromJson<DateTime>(json['lastCheckedAt']),
      profileId: serializer.fromJson<int>(json['profileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seriesId': serializer.toJson<int>(seriesId),
      'knownEpisodeCount': serializer.toJson<int>(knownEpisodeCount),
      'newEpisodeCount': serializer.toJson<int>(newEpisodeCount),
      'hasNewEpisodes': serializer.toJson<bool>(hasNewEpisodes),
      'lastCheckedAt': serializer.toJson<DateTime>(lastCheckedAt),
      'profileId': serializer.toJson<int>(profileId),
    };
  }

  SeriesTrackingData copyWith({
    int? seriesId,
    int? knownEpisodeCount,
    int? newEpisodeCount,
    bool? hasNewEpisodes,
    DateTime? lastCheckedAt,
    int? profileId,
  }) => SeriesTrackingData(
    seriesId: seriesId ?? this.seriesId,
    knownEpisodeCount: knownEpisodeCount ?? this.knownEpisodeCount,
    newEpisodeCount: newEpisodeCount ?? this.newEpisodeCount,
    hasNewEpisodes: hasNewEpisodes ?? this.hasNewEpisodes,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    profileId: profileId ?? this.profileId,
  );
  SeriesTrackingData copyWithCompanion(SeriesTrackingCompanion data) {
    return SeriesTrackingData(
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      knownEpisodeCount: data.knownEpisodeCount.present
          ? data.knownEpisodeCount.value
          : this.knownEpisodeCount,
      newEpisodeCount: data.newEpisodeCount.present
          ? data.newEpisodeCount.value
          : this.newEpisodeCount,
      hasNewEpisodes: data.hasNewEpisodes.present
          ? data.hasNewEpisodes.value
          : this.hasNewEpisodes,
      lastCheckedAt: data.lastCheckedAt.present
          ? data.lastCheckedAt.value
          : this.lastCheckedAt,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeriesTrackingData(')
          ..write('seriesId: $seriesId, ')
          ..write('knownEpisodeCount: $knownEpisodeCount, ')
          ..write('newEpisodeCount: $newEpisodeCount, ')
          ..write('hasNewEpisodes: $hasNewEpisodes, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('profileId: $profileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    seriesId,
    knownEpisodeCount,
    newEpisodeCount,
    hasNewEpisodes,
    lastCheckedAt,
    profileId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeriesTrackingData &&
          other.seriesId == this.seriesId &&
          other.knownEpisodeCount == this.knownEpisodeCount &&
          other.newEpisodeCount == this.newEpisodeCount &&
          other.hasNewEpisodes == this.hasNewEpisodes &&
          other.lastCheckedAt == this.lastCheckedAt &&
          other.profileId == this.profileId);
}

class SeriesTrackingCompanion extends UpdateCompanion<SeriesTrackingData> {
  final Value<int> seriesId;
  final Value<int> knownEpisodeCount;
  final Value<int> newEpisodeCount;
  final Value<bool> hasNewEpisodes;
  final Value<DateTime> lastCheckedAt;
  final Value<int> profileId;
  final Value<int> rowid;
  const SeriesTrackingCompanion({
    this.seriesId = const Value.absent(),
    this.knownEpisodeCount = const Value.absent(),
    this.newEpisodeCount = const Value.absent(),
    this.hasNewEpisodes = const Value.absent(),
    this.lastCheckedAt = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeriesTrackingCompanion.insert({
    required int seriesId,
    required int knownEpisodeCount,
    this.newEpisodeCount = const Value.absent(),
    this.hasNewEpisodes = const Value.absent(),
    this.lastCheckedAt = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : seriesId = Value(seriesId),
       knownEpisodeCount = Value(knownEpisodeCount);
  static Insertable<SeriesTrackingData> custom({
    Expression<int>? seriesId,
    Expression<int>? knownEpisodeCount,
    Expression<int>? newEpisodeCount,
    Expression<bool>? hasNewEpisodes,
    Expression<DateTime>? lastCheckedAt,
    Expression<int>? profileId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (seriesId != null) 'series_id': seriesId,
      if (knownEpisodeCount != null) 'known_episode_count': knownEpisodeCount,
      if (newEpisodeCount != null) 'new_episode_count': newEpisodeCount,
      if (hasNewEpisodes != null) 'has_new_episodes': hasNewEpisodes,
      if (lastCheckedAt != null) 'last_checked_at': lastCheckedAt,
      if (profileId != null) 'profile_id': profileId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeriesTrackingCompanion copyWith({
    Value<int>? seriesId,
    Value<int>? knownEpisodeCount,
    Value<int>? newEpisodeCount,
    Value<bool>? hasNewEpisodes,
    Value<DateTime>? lastCheckedAt,
    Value<int>? profileId,
    Value<int>? rowid,
  }) {
    return SeriesTrackingCompanion(
      seriesId: seriesId ?? this.seriesId,
      knownEpisodeCount: knownEpisodeCount ?? this.knownEpisodeCount,
      newEpisodeCount: newEpisodeCount ?? this.newEpisodeCount,
      hasNewEpisodes: hasNewEpisodes ?? this.hasNewEpisodes,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      profileId: profileId ?? this.profileId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seriesId.present) {
      map['series_id'] = Variable<int>(seriesId.value);
    }
    if (knownEpisodeCount.present) {
      map['known_episode_count'] = Variable<int>(knownEpisodeCount.value);
    }
    if (newEpisodeCount.present) {
      map['new_episode_count'] = Variable<int>(newEpisodeCount.value);
    }
    if (hasNewEpisodes.present) {
      map['has_new_episodes'] = Variable<bool>(hasNewEpisodes.value);
    }
    if (lastCheckedAt.present) {
      map['last_checked_at'] = Variable<DateTime>(lastCheckedAt.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<int>(profileId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesTrackingCompanion(')
          ..write('seriesId: $seriesId, ')
          ..write('knownEpisodeCount: $knownEpisodeCount, ')
          ..write('newEpisodeCount: $newEpisodeCount, ')
          ..write('hasNewEpisodes: $hasNewEpisodes, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('profileId: $profileId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IntroMarkersTable extends IntroMarkers
    with TableInfo<$IntroMarkersTable, IntroMarker> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IntroMarkersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<int> seriesId = GeneratedColumn<int>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _introStartMsMeta = const VerificationMeta(
    'introStartMs',
  );
  @override
  late final GeneratedColumn<int> introStartMs = GeneratedColumn<int>(
    'intro_start_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _introEndMsMeta = const VerificationMeta(
    'introEndMs',
  );
  @override
  late final GeneratedColumn<int> introEndMs = GeneratedColumn<int>(
    'intro_end_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    seriesId,
    introStartMs,
    introEndMs,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'intro_markers';
  @override
  VerificationContext validateIntegrity(
    Insertable<IntroMarker> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    }
    if (data.containsKey('intro_start_ms')) {
      context.handle(
        _introStartMsMeta,
        introStartMs.isAcceptableOrUnknown(
          data['intro_start_ms']!,
          _introStartMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_introStartMsMeta);
    }
    if (data.containsKey('intro_end_ms')) {
      context.handle(
        _introEndMsMeta,
        introEndMs.isAcceptableOrUnknown(
          data['intro_end_ms']!,
          _introEndMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_introEndMsMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seriesId};
  @override
  IntroMarker map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IntroMarker(
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}series_id'],
      )!,
      introStartMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}intro_start_ms'],
      )!,
      introEndMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}intro_end_ms'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $IntroMarkersTable createAlias(String alias) {
    return $IntroMarkersTable(attachedDatabase, alias);
  }
}

class IntroMarker extends DataClass implements Insertable<IntroMarker> {
  /// References [Channels.streamId] for the *parent series*, not an
  /// individual episode. Comes from `widget.parentStreamId` in the
  /// player route.
  final int seriesId;
  final int introStartMs;
  final int introEndMs;
  final DateTime updatedAt;
  const IntroMarker({
    required this.seriesId,
    required this.introStartMs,
    required this.introEndMs,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['series_id'] = Variable<int>(seriesId);
    map['intro_start_ms'] = Variable<int>(introStartMs);
    map['intro_end_ms'] = Variable<int>(introEndMs);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  IntroMarkersCompanion toCompanion(bool nullToAbsent) {
    return IntroMarkersCompanion(
      seriesId: Value(seriesId),
      introStartMs: Value(introStartMs),
      introEndMs: Value(introEndMs),
      updatedAt: Value(updatedAt),
    );
  }

  factory IntroMarker.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IntroMarker(
      seriesId: serializer.fromJson<int>(json['seriesId']),
      introStartMs: serializer.fromJson<int>(json['introStartMs']),
      introEndMs: serializer.fromJson<int>(json['introEndMs']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seriesId': serializer.toJson<int>(seriesId),
      'introStartMs': serializer.toJson<int>(introStartMs),
      'introEndMs': serializer.toJson<int>(introEndMs),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  IntroMarker copyWith({
    int? seriesId,
    int? introStartMs,
    int? introEndMs,
    DateTime? updatedAt,
  }) => IntroMarker(
    seriesId: seriesId ?? this.seriesId,
    introStartMs: introStartMs ?? this.introStartMs,
    introEndMs: introEndMs ?? this.introEndMs,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  IntroMarker copyWithCompanion(IntroMarkersCompanion data) {
    return IntroMarker(
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      introStartMs: data.introStartMs.present
          ? data.introStartMs.value
          : this.introStartMs,
      introEndMs: data.introEndMs.present
          ? data.introEndMs.value
          : this.introEndMs,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IntroMarker(')
          ..write('seriesId: $seriesId, ')
          ..write('introStartMs: $introStartMs, ')
          ..write('introEndMs: $introEndMs, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(seriesId, introStartMs, introEndMs, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IntroMarker &&
          other.seriesId == this.seriesId &&
          other.introStartMs == this.introStartMs &&
          other.introEndMs == this.introEndMs &&
          other.updatedAt == this.updatedAt);
}

class IntroMarkersCompanion extends UpdateCompanion<IntroMarker> {
  final Value<int> seriesId;
  final Value<int> introStartMs;
  final Value<int> introEndMs;
  final Value<DateTime> updatedAt;
  const IntroMarkersCompanion({
    this.seriesId = const Value.absent(),
    this.introStartMs = const Value.absent(),
    this.introEndMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  IntroMarkersCompanion.insert({
    this.seriesId = const Value.absent(),
    required int introStartMs,
    required int introEndMs,
    this.updatedAt = const Value.absent(),
  }) : introStartMs = Value(introStartMs),
       introEndMs = Value(introEndMs);
  static Insertable<IntroMarker> custom({
    Expression<int>? seriesId,
    Expression<int>? introStartMs,
    Expression<int>? introEndMs,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (seriesId != null) 'series_id': seriesId,
      if (introStartMs != null) 'intro_start_ms': introStartMs,
      if (introEndMs != null) 'intro_end_ms': introEndMs,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  IntroMarkersCompanion copyWith({
    Value<int>? seriesId,
    Value<int>? introStartMs,
    Value<int>? introEndMs,
    Value<DateTime>? updatedAt,
  }) {
    return IntroMarkersCompanion(
      seriesId: seriesId ?? this.seriesId,
      introStartMs: introStartMs ?? this.introStartMs,
      introEndMs: introEndMs ?? this.introEndMs,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seriesId.present) {
      map['series_id'] = Variable<int>(seriesId.value);
    }
    if (introStartMs.present) {
      map['intro_start_ms'] = Variable<int>(introStartMs.value);
    }
    if (introEndMs.present) {
      map['intro_end_ms'] = Variable<int>(introEndMs.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IntroMarkersCompanion(')
          ..write('seriesId: $seriesId, ')
          ..write('introStartMs: $introStartMs, ')
          ..write('introEndMs: $introEndMs, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PlotAiCacheTable extends PlotAiCache
    with TableInfo<$PlotAiCacheTable, PlotAiCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlotAiCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<int> streamId = GeneratedColumn<int>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetLanguageMeta = const VerificationMeta(
    'targetLanguage',
  );
  @override
  late final GeneratedColumn<String> targetLanguage = GeneratedColumn<String>(
    'target_language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceHashMeta = const VerificationMeta(
    'sourceHash',
  );
  @override
  late final GeneratedColumn<String> sourceHash = GeneratedColumn<String>(
    'source_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    streamId,
    mode,
    targetLanguage,
    content,
    sourceHash,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plot_ai_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlotAiCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('target_language')) {
      context.handle(
        _targetLanguageMeta,
        targetLanguage.isAcceptableOrUnknown(
          data['target_language']!,
          _targetLanguageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetLanguageMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('source_hash')) {
      context.handle(
        _sourceHashMeta,
        sourceHash.isAcceptableOrUnknown(data['source_hash']!, _sourceHashMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceHashMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {streamId, mode, targetLanguage};
  @override
  PlotAiCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlotAiCacheData(
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stream_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      targetLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_language'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      sourceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_hash'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PlotAiCacheTable createAlias(String alias) {
    return $PlotAiCacheTable(attachedDatabase, alias);
  }
}

class PlotAiCacheData extends DataClass implements Insertable<PlotAiCacheData> {
  /// `Channel.streamId` of the title this enrichment was generated for.
  final int streamId;

  /// One of the [PlotEnrichMode] enum names — kept as a string so the
  /// table doesn't break when modes are added/renamed.
  final String mode;

  /// ISO-639-1 code (e.g. "tr", "en") of the response language. Cached
  /// separately per language because translate(tr) and translate(en)
  /// of the same plot are different outputs.
  final String targetLanguage;

  /// The AI-produced text. Whatever `enrichPlot` returned.
  final String content;

  /// Cheap fingerprint of the metadata we fed Gemini (title, year,
  /// genre, director, cast, rating, originalPlot). Changing any of
  /// those changes the hash, invalidating the row on next read.
  final String sourceHash;
  final DateTime createdAt;
  const PlotAiCacheData({
    required this.streamId,
    required this.mode,
    required this.targetLanguage,
    required this.content,
    required this.sourceHash,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stream_id'] = Variable<int>(streamId);
    map['mode'] = Variable<String>(mode);
    map['target_language'] = Variable<String>(targetLanguage);
    map['content'] = Variable<String>(content);
    map['source_hash'] = Variable<String>(sourceHash);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PlotAiCacheCompanion toCompanion(bool nullToAbsent) {
    return PlotAiCacheCompanion(
      streamId: Value(streamId),
      mode: Value(mode),
      targetLanguage: Value(targetLanguage),
      content: Value(content),
      sourceHash: Value(sourceHash),
      createdAt: Value(createdAt),
    );
  }

  factory PlotAiCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlotAiCacheData(
      streamId: serializer.fromJson<int>(json['streamId']),
      mode: serializer.fromJson<String>(json['mode']),
      targetLanguage: serializer.fromJson<String>(json['targetLanguage']),
      content: serializer.fromJson<String>(json['content']),
      sourceHash: serializer.fromJson<String>(json['sourceHash']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'streamId': serializer.toJson<int>(streamId),
      'mode': serializer.toJson<String>(mode),
      'targetLanguage': serializer.toJson<String>(targetLanguage),
      'content': serializer.toJson<String>(content),
      'sourceHash': serializer.toJson<String>(sourceHash),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PlotAiCacheData copyWith({
    int? streamId,
    String? mode,
    String? targetLanguage,
    String? content,
    String? sourceHash,
    DateTime? createdAt,
  }) => PlotAiCacheData(
    streamId: streamId ?? this.streamId,
    mode: mode ?? this.mode,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    content: content ?? this.content,
    sourceHash: sourceHash ?? this.sourceHash,
    createdAt: createdAt ?? this.createdAt,
  );
  PlotAiCacheData copyWithCompanion(PlotAiCacheCompanion data) {
    return PlotAiCacheData(
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      mode: data.mode.present ? data.mode.value : this.mode,
      targetLanguage: data.targetLanguage.present
          ? data.targetLanguage.value
          : this.targetLanguage,
      content: data.content.present ? data.content.value : this.content,
      sourceHash: data.sourceHash.present
          ? data.sourceHash.value
          : this.sourceHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlotAiCacheData(')
          ..write('streamId: $streamId, ')
          ..write('mode: $mode, ')
          ..write('targetLanguage: $targetLanguage, ')
          ..write('content: $content, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    streamId,
    mode,
    targetLanguage,
    content,
    sourceHash,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlotAiCacheData &&
          other.streamId == this.streamId &&
          other.mode == this.mode &&
          other.targetLanguage == this.targetLanguage &&
          other.content == this.content &&
          other.sourceHash == this.sourceHash &&
          other.createdAt == this.createdAt);
}

class PlotAiCacheCompanion extends UpdateCompanion<PlotAiCacheData> {
  final Value<int> streamId;
  final Value<String> mode;
  final Value<String> targetLanguage;
  final Value<String> content;
  final Value<String> sourceHash;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PlotAiCacheCompanion({
    this.streamId = const Value.absent(),
    this.mode = const Value.absent(),
    this.targetLanguage = const Value.absent(),
    this.content = const Value.absent(),
    this.sourceHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlotAiCacheCompanion.insert({
    required int streamId,
    required String mode,
    required String targetLanguage,
    required String content,
    required String sourceHash,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : streamId = Value(streamId),
       mode = Value(mode),
       targetLanguage = Value(targetLanguage),
       content = Value(content),
       sourceHash = Value(sourceHash);
  static Insertable<PlotAiCacheData> custom({
    Expression<int>? streamId,
    Expression<String>? mode,
    Expression<String>? targetLanguage,
    Expression<String>? content,
    Expression<String>? sourceHash,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (streamId != null) 'stream_id': streamId,
      if (mode != null) 'mode': mode,
      if (targetLanguage != null) 'target_language': targetLanguage,
      if (content != null) 'content': content,
      if (sourceHash != null) 'source_hash': sourceHash,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlotAiCacheCompanion copyWith({
    Value<int>? streamId,
    Value<String>? mode,
    Value<String>? targetLanguage,
    Value<String>? content,
    Value<String>? sourceHash,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PlotAiCacheCompanion(
      streamId: streamId ?? this.streamId,
      mode: mode ?? this.mode,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      content: content ?? this.content,
      sourceHash: sourceHash ?? this.sourceHash,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (streamId.present) {
      map['stream_id'] = Variable<int>(streamId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (targetLanguage.present) {
      map['target_language'] = Variable<String>(targetLanguage.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (sourceHash.present) {
      map['source_hash'] = Variable<String>(sourceHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlotAiCacheCompanion(')
          ..write('streamId: $streamId, ')
          ..write('mode: $mode, ')
          ..write('targetLanguage: $targetLanguage, ')
          ..write('content: $content, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PersonalizedPicksCacheTable extends PersonalizedPicksCache
    with TableInfo<$PersonalizedPicksCacheTable, PersonalizedPicksCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonalizedPicksCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _picksJsonMeta = const VerificationMeta(
    'picksJson',
  );
  @override
  late final GeneratedColumn<String> picksJson = GeneratedColumn<String>(
    'picks_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceHashMeta = const VerificationMeta(
    'sourceHash',
  );
  @override
  late final GeneratedColumn<String> sourceHash = GeneratedColumn<String>(
    'source_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generatedAtMeta = const VerificationMeta(
    'generatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> generatedAt = GeneratedColumn<DateTime>(
    'generated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    picksJson,
    sourceHash,
    generatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'personalized_picks_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonalizedPicksCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('picks_json')) {
      context.handle(
        _picksJsonMeta,
        picksJson.isAcceptableOrUnknown(data['picks_json']!, _picksJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_picksJsonMeta);
    }
    if (data.containsKey('source_hash')) {
      context.handle(
        _sourceHashMeta,
        sourceHash.isAcceptableOrUnknown(data['source_hash']!, _sourceHashMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceHashMeta);
    }
    if (data.containsKey('generated_at')) {
      context.handle(
        _generatedAtMeta,
        generatedAt.isAcceptableOrUnknown(
          data['generated_at']!,
          _generatedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PersonalizedPicksCacheData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonalizedPicksCacheData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      picksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}picks_json'],
      )!,
      sourceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_hash'],
      )!,
      generatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}generated_at'],
      )!,
    );
  }

  @override
  $PersonalizedPicksCacheTable createAlias(String alias) {
    return $PersonalizedPicksCacheTable(attachedDatabase, alias);
  }
}

class PersonalizedPicksCacheData extends DataClass
    implements Insertable<PersonalizedPicksCacheData> {
  /// Singleton row — always 0. Avoids accidental multi-row state.
  final int id;

  /// JSON-encoded `[{streamId: int, reason: string}, ...]` —
  /// preserves order so the rail renders best-first as Gemini
  /// ranked it.
  final String picksJson;

  /// FNV-1a fingerprint of (history-ids + favourite-ids + prompt
  /// version). Mismatch on read invalidates the row.
  final String sourceHash;
  final DateTime generatedAt;
  const PersonalizedPicksCacheData({
    required this.id,
    required this.picksJson,
    required this.sourceHash,
    required this.generatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['picks_json'] = Variable<String>(picksJson);
    map['source_hash'] = Variable<String>(sourceHash);
    map['generated_at'] = Variable<DateTime>(generatedAt);
    return map;
  }

  PersonalizedPicksCacheCompanion toCompanion(bool nullToAbsent) {
    return PersonalizedPicksCacheCompanion(
      id: Value(id),
      picksJson: Value(picksJson),
      sourceHash: Value(sourceHash),
      generatedAt: Value(generatedAt),
    );
  }

  factory PersonalizedPicksCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonalizedPicksCacheData(
      id: serializer.fromJson<int>(json['id']),
      picksJson: serializer.fromJson<String>(json['picksJson']),
      sourceHash: serializer.fromJson<String>(json['sourceHash']),
      generatedAt: serializer.fromJson<DateTime>(json['generatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'picksJson': serializer.toJson<String>(picksJson),
      'sourceHash': serializer.toJson<String>(sourceHash),
      'generatedAt': serializer.toJson<DateTime>(generatedAt),
    };
  }

  PersonalizedPicksCacheData copyWith({
    int? id,
    String? picksJson,
    String? sourceHash,
    DateTime? generatedAt,
  }) => PersonalizedPicksCacheData(
    id: id ?? this.id,
    picksJson: picksJson ?? this.picksJson,
    sourceHash: sourceHash ?? this.sourceHash,
    generatedAt: generatedAt ?? this.generatedAt,
  );
  PersonalizedPicksCacheData copyWithCompanion(
    PersonalizedPicksCacheCompanion data,
  ) {
    return PersonalizedPicksCacheData(
      id: data.id.present ? data.id.value : this.id,
      picksJson: data.picksJson.present ? data.picksJson.value : this.picksJson,
      sourceHash: data.sourceHash.present
          ? data.sourceHash.value
          : this.sourceHash,
      generatedAt: data.generatedAt.present
          ? data.generatedAt.value
          : this.generatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonalizedPicksCacheData(')
          ..write('id: $id, ')
          ..write('picksJson: $picksJson, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('generatedAt: $generatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, picksJson, sourceHash, generatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonalizedPicksCacheData &&
          other.id == this.id &&
          other.picksJson == this.picksJson &&
          other.sourceHash == this.sourceHash &&
          other.generatedAt == this.generatedAt);
}

class PersonalizedPicksCacheCompanion
    extends UpdateCompanion<PersonalizedPicksCacheData> {
  final Value<int> id;
  final Value<String> picksJson;
  final Value<String> sourceHash;
  final Value<DateTime> generatedAt;
  const PersonalizedPicksCacheCompanion({
    this.id = const Value.absent(),
    this.picksJson = const Value.absent(),
    this.sourceHash = const Value.absent(),
    this.generatedAt = const Value.absent(),
  });
  PersonalizedPicksCacheCompanion.insert({
    this.id = const Value.absent(),
    required String picksJson,
    required String sourceHash,
    this.generatedAt = const Value.absent(),
  }) : picksJson = Value(picksJson),
       sourceHash = Value(sourceHash);
  static Insertable<PersonalizedPicksCacheData> custom({
    Expression<int>? id,
    Expression<String>? picksJson,
    Expression<String>? sourceHash,
    Expression<DateTime>? generatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (picksJson != null) 'picks_json': picksJson,
      if (sourceHash != null) 'source_hash': sourceHash,
      if (generatedAt != null) 'generated_at': generatedAt,
    });
  }

  PersonalizedPicksCacheCompanion copyWith({
    Value<int>? id,
    Value<String>? picksJson,
    Value<String>? sourceHash,
    Value<DateTime>? generatedAt,
  }) {
    return PersonalizedPicksCacheCompanion(
      id: id ?? this.id,
      picksJson: picksJson ?? this.picksJson,
      sourceHash: sourceHash ?? this.sourceHash,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (picksJson.present) {
      map['picks_json'] = Variable<String>(picksJson.value);
    }
    if (sourceHash.present) {
      map['source_hash'] = Variable<String>(sourceHash.value);
    }
    if (generatedAt.present) {
      map['generated_at'] = Variable<DateTime>(generatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonalizedPicksCacheCompanion(')
          ..write('id: $id, ')
          ..write('picksJson: $picksJson, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('generatedAt: $generatedAt')
          ..write(')'))
        .toString();
  }
}

class $AiCallLogsTable extends AiCallLogs
    with TableInfo<$AiCallLogsTable, AiCallLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiCallLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _featureMeta = const VerificationMeta(
    'feature',
  );
  @override
  late final GeneratedColumn<String> feature = GeneratedColumn<String>(
    'feature',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latencyMsMeta = const VerificationMeta(
    'latencyMs',
  );
  @override
  late final GeneratedColumn<int> latencyMs = GeneratedColumn<int>(
    'latency_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _successMeta = const VerificationMeta(
    'success',
  );
  @override
  late final GeneratedColumn<bool> success = GeneratedColumn<bool>(
    'success',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("success" IN (0, 1))',
    ),
  );
  static const VerificationMeta _timedOutMeta = const VerificationMeta(
    'timedOut',
  );
  @override
  late final GeneratedColumn<bool> timedOut = GeneratedColumn<bool>(
    'timed_out',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("timed_out" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _candidateCountMeta = const VerificationMeta(
    'candidateCount',
  );
  @override
  late final GeneratedColumn<int> candidateCount = GeneratedColumn<int>(
    'candidate_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _outputCountMeta = const VerificationMeta(
    'outputCount',
  );
  @override
  late final GeneratedColumn<int> outputCount = GeneratedColumn<int>(
    'output_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    feature,
    model,
    latencyMs,
    success,
    timedOut,
    candidateCount,
    outputCount,
    errorCode,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_call_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiCallLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('feature')) {
      context.handle(
        _featureMeta,
        feature.isAcceptableOrUnknown(data['feature']!, _featureMeta),
      );
    } else if (isInserting) {
      context.missing(_featureMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('latency_ms')) {
      context.handle(
        _latencyMsMeta,
        latencyMs.isAcceptableOrUnknown(data['latency_ms']!, _latencyMsMeta),
      );
    } else if (isInserting) {
      context.missing(_latencyMsMeta);
    }
    if (data.containsKey('success')) {
      context.handle(
        _successMeta,
        success.isAcceptableOrUnknown(data['success']!, _successMeta),
      );
    } else if (isInserting) {
      context.missing(_successMeta);
    }
    if (data.containsKey('timed_out')) {
      context.handle(
        _timedOutMeta,
        timedOut.isAcceptableOrUnknown(data['timed_out']!, _timedOutMeta),
      );
    }
    if (data.containsKey('candidate_count')) {
      context.handle(
        _candidateCountMeta,
        candidateCount.isAcceptableOrUnknown(
          data['candidate_count']!,
          _candidateCountMeta,
        ),
      );
    }
    if (data.containsKey('output_count')) {
      context.handle(
        _outputCountMeta,
        outputCount.isAcceptableOrUnknown(
          data['output_count']!,
          _outputCountMeta,
        ),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiCallLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiCallLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      feature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}feature'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      latencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latency_ms'],
      )!,
      success: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}success'],
      )!,
      timedOut: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}timed_out'],
      )!,
      candidateCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}candidate_count'],
      )!,
      outputCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}output_count'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AiCallLogsTable createAlias(String alias) {
    return $AiCallLogsTable(attachedDatabase, alias);
  }
}

class AiCallLog extends DataClass implements Insertable<AiCallLog> {
  final int id;
  final String feature;
  final String model;
  final int latencyMs;
  final bool success;
  final bool timedOut;
  final int candidateCount;
  final int outputCount;
  final String? errorCode;
  final DateTime createdAt;
  const AiCallLog({
    required this.id,
    required this.feature,
    required this.model,
    required this.latencyMs,
    required this.success,
    required this.timedOut,
    required this.candidateCount,
    required this.outputCount,
    this.errorCode,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['feature'] = Variable<String>(feature);
    map['model'] = Variable<String>(model);
    map['latency_ms'] = Variable<int>(latencyMs);
    map['success'] = Variable<bool>(success);
    map['timed_out'] = Variable<bool>(timedOut);
    map['candidate_count'] = Variable<int>(candidateCount);
    map['output_count'] = Variable<int>(outputCount);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AiCallLogsCompanion toCompanion(bool nullToAbsent) {
    return AiCallLogsCompanion(
      id: Value(id),
      feature: Value(feature),
      model: Value(model),
      latencyMs: Value(latencyMs),
      success: Value(success),
      timedOut: Value(timedOut),
      candidateCount: Value(candidateCount),
      outputCount: Value(outputCount),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      createdAt: Value(createdAt),
    );
  }

  factory AiCallLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiCallLog(
      id: serializer.fromJson<int>(json['id']),
      feature: serializer.fromJson<String>(json['feature']),
      model: serializer.fromJson<String>(json['model']),
      latencyMs: serializer.fromJson<int>(json['latencyMs']),
      success: serializer.fromJson<bool>(json['success']),
      timedOut: serializer.fromJson<bool>(json['timedOut']),
      candidateCount: serializer.fromJson<int>(json['candidateCount']),
      outputCount: serializer.fromJson<int>(json['outputCount']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'feature': serializer.toJson<String>(feature),
      'model': serializer.toJson<String>(model),
      'latencyMs': serializer.toJson<int>(latencyMs),
      'success': serializer.toJson<bool>(success),
      'timedOut': serializer.toJson<bool>(timedOut),
      'candidateCount': serializer.toJson<int>(candidateCount),
      'outputCount': serializer.toJson<int>(outputCount),
      'errorCode': serializer.toJson<String?>(errorCode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AiCallLog copyWith({
    int? id,
    String? feature,
    String? model,
    int? latencyMs,
    bool? success,
    bool? timedOut,
    int? candidateCount,
    int? outputCount,
    Value<String?> errorCode = const Value.absent(),
    DateTime? createdAt,
  }) => AiCallLog(
    id: id ?? this.id,
    feature: feature ?? this.feature,
    model: model ?? this.model,
    latencyMs: latencyMs ?? this.latencyMs,
    success: success ?? this.success,
    timedOut: timedOut ?? this.timedOut,
    candidateCount: candidateCount ?? this.candidateCount,
    outputCount: outputCount ?? this.outputCount,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    createdAt: createdAt ?? this.createdAt,
  );
  AiCallLog copyWithCompanion(AiCallLogsCompanion data) {
    return AiCallLog(
      id: data.id.present ? data.id.value : this.id,
      feature: data.feature.present ? data.feature.value : this.feature,
      model: data.model.present ? data.model.value : this.model,
      latencyMs: data.latencyMs.present ? data.latencyMs.value : this.latencyMs,
      success: data.success.present ? data.success.value : this.success,
      timedOut: data.timedOut.present ? data.timedOut.value : this.timedOut,
      candidateCount: data.candidateCount.present
          ? data.candidateCount.value
          : this.candidateCount,
      outputCount: data.outputCount.present
          ? data.outputCount.value
          : this.outputCount,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiCallLog(')
          ..write('id: $id, ')
          ..write('feature: $feature, ')
          ..write('model: $model, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('success: $success, ')
          ..write('timedOut: $timedOut, ')
          ..write('candidateCount: $candidateCount, ')
          ..write('outputCount: $outputCount, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    feature,
    model,
    latencyMs,
    success,
    timedOut,
    candidateCount,
    outputCount,
    errorCode,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiCallLog &&
          other.id == this.id &&
          other.feature == this.feature &&
          other.model == this.model &&
          other.latencyMs == this.latencyMs &&
          other.success == this.success &&
          other.timedOut == this.timedOut &&
          other.candidateCount == this.candidateCount &&
          other.outputCount == this.outputCount &&
          other.errorCode == this.errorCode &&
          other.createdAt == this.createdAt);
}

class AiCallLogsCompanion extends UpdateCompanion<AiCallLog> {
  final Value<int> id;
  final Value<String> feature;
  final Value<String> model;
  final Value<int> latencyMs;
  final Value<bool> success;
  final Value<bool> timedOut;
  final Value<int> candidateCount;
  final Value<int> outputCount;
  final Value<String?> errorCode;
  final Value<DateTime> createdAt;
  const AiCallLogsCompanion({
    this.id = const Value.absent(),
    this.feature = const Value.absent(),
    this.model = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.success = const Value.absent(),
    this.timedOut = const Value.absent(),
    this.candidateCount = const Value.absent(),
    this.outputCount = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  AiCallLogsCompanion.insert({
    this.id = const Value.absent(),
    required String feature,
    required String model,
    required int latencyMs,
    required bool success,
    this.timedOut = const Value.absent(),
    this.candidateCount = const Value.absent(),
    this.outputCount = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : feature = Value(feature),
       model = Value(model),
       latencyMs = Value(latencyMs),
       success = Value(success);
  static Insertable<AiCallLog> custom({
    Expression<int>? id,
    Expression<String>? feature,
    Expression<String>? model,
    Expression<int>? latencyMs,
    Expression<bool>? success,
    Expression<bool>? timedOut,
    Expression<int>? candidateCount,
    Expression<int>? outputCount,
    Expression<String>? errorCode,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (feature != null) 'feature': feature,
      if (model != null) 'model': model,
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (success != null) 'success': success,
      if (timedOut != null) 'timed_out': timedOut,
      if (candidateCount != null) 'candidate_count': candidateCount,
      if (outputCount != null) 'output_count': outputCount,
      if (errorCode != null) 'error_code': errorCode,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  AiCallLogsCompanion copyWith({
    Value<int>? id,
    Value<String>? feature,
    Value<String>? model,
    Value<int>? latencyMs,
    Value<bool>? success,
    Value<bool>? timedOut,
    Value<int>? candidateCount,
    Value<int>? outputCount,
    Value<String?>? errorCode,
    Value<DateTime>? createdAt,
  }) {
    return AiCallLogsCompanion(
      id: id ?? this.id,
      feature: feature ?? this.feature,
      model: model ?? this.model,
      latencyMs: latencyMs ?? this.latencyMs,
      success: success ?? this.success,
      timedOut: timedOut ?? this.timedOut,
      candidateCount: candidateCount ?? this.candidateCount,
      outputCount: outputCount ?? this.outputCount,
      errorCode: errorCode ?? this.errorCode,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (feature.present) {
      map['feature'] = Variable<String>(feature.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (latencyMs.present) {
      map['latency_ms'] = Variable<int>(latencyMs.value);
    }
    if (success.present) {
      map['success'] = Variable<bool>(success.value);
    }
    if (timedOut.present) {
      map['timed_out'] = Variable<bool>(timedOut.value);
    }
    if (candidateCount.present) {
      map['candidate_count'] = Variable<int>(candidateCount.value);
    }
    if (outputCount.present) {
      map['output_count'] = Variable<int>(outputCount.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiCallLogsCompanion(')
          ..write('id: $id, ')
          ..write('feature: $feature, ')
          ..write('model: $model, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('success: $success, ')
          ..write('timedOut: $timedOut, ')
          ..write('candidateCount: $candidateCount, ')
          ..write('outputCount: $outputCount, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $AiFeedbackTable extends AiFeedback
    with TableInfo<$AiFeedbackTable, AiFeedbackData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiFeedbackTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<int> streamId = GeneratedColumn<int>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _featureMeta = const VerificationMeta(
    'feature',
  );
  @override
  late final GeneratedColumn<String> feature = GeneratedColumn<String>(
    'feature',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<int> profileId = GeneratedColumn<int>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    streamId,
    type,
    action,
    feature,
    createdAt,
    profileId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_feedback';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiFeedbackData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('feature')) {
      context.handle(
        _featureMeta,
        feature.isAcceptableOrUnknown(data['feature']!, _featureMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {streamId, type, action, profileId};
  @override
  AiFeedbackData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiFeedbackData(
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stream_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      feature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}feature'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_id'],
      )!,
    );
  }

  @override
  $AiFeedbackTable createAlias(String alias) {
    return $AiFeedbackTable(attachedDatabase, alias);
  }
}

class AiFeedbackData extends DataClass implements Insertable<AiFeedbackData> {
  final int streamId;
  final String type;

  /// One of: 'dislike', 'moreLike'.
  ///
  /// `dislike` — never show in any AI surface again. Hard filter.
  /// `moreLike` — boost in AI prompts as a taste anchor. Soft signal.
  ///
  /// "Hide for now" stays in-memory in the rail; not persisted.
  final String action;

  /// Optional feature tag — useful for analytics ("most disliked
  /// rail = mood"). Nullable because some feedback comes from
  /// generic surfaces. Not used in filtering.
  final String? feature;
  final DateTime createdAt;

  /// Owning profile. Feedback (dislike / moreLike) is per-person —
  /// the father saying "show me less of this" must not affect the
  /// child's rail.
  final int profileId;
  const AiFeedbackData({
    required this.streamId,
    required this.type,
    required this.action,
    this.feature,
    required this.createdAt,
    required this.profileId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stream_id'] = Variable<int>(streamId);
    map['type'] = Variable<String>(type);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || feature != null) {
      map['feature'] = Variable<String>(feature);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['profile_id'] = Variable<int>(profileId);
    return map;
  }

  AiFeedbackCompanion toCompanion(bool nullToAbsent) {
    return AiFeedbackCompanion(
      streamId: Value(streamId),
      type: Value(type),
      action: Value(action),
      feature: feature == null && nullToAbsent
          ? const Value.absent()
          : Value(feature),
      createdAt: Value(createdAt),
      profileId: Value(profileId),
    );
  }

  factory AiFeedbackData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiFeedbackData(
      streamId: serializer.fromJson<int>(json['streamId']),
      type: serializer.fromJson<String>(json['type']),
      action: serializer.fromJson<String>(json['action']),
      feature: serializer.fromJson<String?>(json['feature']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      profileId: serializer.fromJson<int>(json['profileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'streamId': serializer.toJson<int>(streamId),
      'type': serializer.toJson<String>(type),
      'action': serializer.toJson<String>(action),
      'feature': serializer.toJson<String?>(feature),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'profileId': serializer.toJson<int>(profileId),
    };
  }

  AiFeedbackData copyWith({
    int? streamId,
    String? type,
    String? action,
    Value<String?> feature = const Value.absent(),
    DateTime? createdAt,
    int? profileId,
  }) => AiFeedbackData(
    streamId: streamId ?? this.streamId,
    type: type ?? this.type,
    action: action ?? this.action,
    feature: feature.present ? feature.value : this.feature,
    createdAt: createdAt ?? this.createdAt,
    profileId: profileId ?? this.profileId,
  );
  AiFeedbackData copyWithCompanion(AiFeedbackCompanion data) {
    return AiFeedbackData(
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      type: data.type.present ? data.type.value : this.type,
      action: data.action.present ? data.action.value : this.action,
      feature: data.feature.present ? data.feature.value : this.feature,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiFeedbackData(')
          ..write('streamId: $streamId, ')
          ..write('type: $type, ')
          ..write('action: $action, ')
          ..write('feature: $feature, ')
          ..write('createdAt: $createdAt, ')
          ..write('profileId: $profileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(streamId, type, action, feature, createdAt, profileId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiFeedbackData &&
          other.streamId == this.streamId &&
          other.type == this.type &&
          other.action == this.action &&
          other.feature == this.feature &&
          other.createdAt == this.createdAt &&
          other.profileId == this.profileId);
}

class AiFeedbackCompanion extends UpdateCompanion<AiFeedbackData> {
  final Value<int> streamId;
  final Value<String> type;
  final Value<String> action;
  final Value<String?> feature;
  final Value<DateTime> createdAt;
  final Value<int> profileId;
  final Value<int> rowid;
  const AiFeedbackCompanion({
    this.streamId = const Value.absent(),
    this.type = const Value.absent(),
    this.action = const Value.absent(),
    this.feature = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiFeedbackCompanion.insert({
    required int streamId,
    required String type,
    required String action,
    this.feature = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : streamId = Value(streamId),
       type = Value(type),
       action = Value(action);
  static Insertable<AiFeedbackData> custom({
    Expression<int>? streamId,
    Expression<String>? type,
    Expression<String>? action,
    Expression<String>? feature,
    Expression<DateTime>? createdAt,
    Expression<int>? profileId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (streamId != null) 'stream_id': streamId,
      if (type != null) 'type': type,
      if (action != null) 'action': action,
      if (feature != null) 'feature': feature,
      if (createdAt != null) 'created_at': createdAt,
      if (profileId != null) 'profile_id': profileId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiFeedbackCompanion copyWith({
    Value<int>? streamId,
    Value<String>? type,
    Value<String>? action,
    Value<String?>? feature,
    Value<DateTime>? createdAt,
    Value<int>? profileId,
    Value<int>? rowid,
  }) {
    return AiFeedbackCompanion(
      streamId: streamId ?? this.streamId,
      type: type ?? this.type,
      action: action ?? this.action,
      feature: feature ?? this.feature,
      createdAt: createdAt ?? this.createdAt,
      profileId: profileId ?? this.profileId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (streamId.present) {
      map['stream_id'] = Variable<int>(streamId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (feature.present) {
      map['feature'] = Variable<String>(feature.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<int>(profileId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiFeedbackCompanion(')
          ..write('streamId: $streamId, ')
          ..write('type: $type, ')
          ..write('action: $action, ')
          ..write('feature: $feature, ')
          ..write('createdAt: $createdAt, ')
          ..write('profileId: $profileId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SearchHistoryTable extends SearchHistory
    with TableInfo<$SearchHistoryTable, SearchHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _queryMeta = const VerificationMeta('query');
  @override
  late final GeneratedColumn<String> query = GeneratedColumn<String>(
    'query',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _useCountMeta = const VerificationMeta(
    'useCount',
  );
  @override
  late final GeneratedColumn<int> useCount = GeneratedColumn<int>(
    'use_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<int> profileId = GeneratedColumn<int>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    query,
    lastUsedAt,
    useCount,
    profileId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<SearchHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('query')) {
      context.handle(
        _queryMeta,
        query.isAcceptableOrUnknown(data['query']!, _queryMeta),
      );
    } else if (isInserting) {
      context.missing(_queryMeta);
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    if (data.containsKey('use_count')) {
      context.handle(
        _useCountMeta,
        useCount.isAcceptableOrUnknown(data['use_count']!, _useCountMeta),
      );
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {query, profileId};
  @override
  SearchHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchHistoryData(
      query: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      )!,
      useCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}use_count'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_id'],
      )!,
    );
  }

  @override
  $SearchHistoryTable createAlias(String alias) {
    return $SearchHistoryTable(attachedDatabase, alias);
  }
}

class SearchHistoryData extends DataClass
    implements Insertable<SearchHistoryData> {
  /// Normalised search query — lower-cased, trimmed, multi-space
  /// collapsed. Display layer re-cases for the chip label.
  final String query;

  /// Last time this query was submitted. Drives the "recent" sort.
  final DateTime lastUsedAt;

  /// How many times this query has been submitted. Drives the
  /// "trending" sort within the rolling 7-day window.
  final int useCount;

  /// Owning profile. Search history is private to each profile — a
  /// kid's chip rail shouldn't show the parent's "korku gerilim"
  /// queries.
  final int profileId;
  const SearchHistoryData({
    required this.query,
    required this.lastUsedAt,
    required this.useCount,
    required this.profileId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['query'] = Variable<String>(query);
    map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    map['use_count'] = Variable<int>(useCount);
    map['profile_id'] = Variable<int>(profileId);
    return map;
  }

  SearchHistoryCompanion toCompanion(bool nullToAbsent) {
    return SearchHistoryCompanion(
      query: Value(query),
      lastUsedAt: Value(lastUsedAt),
      useCount: Value(useCount),
      profileId: Value(profileId),
    );
  }

  factory SearchHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SearchHistoryData(
      query: serializer.fromJson<String>(json['query']),
      lastUsedAt: serializer.fromJson<DateTime>(json['lastUsedAt']),
      useCount: serializer.fromJson<int>(json['useCount']),
      profileId: serializer.fromJson<int>(json['profileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'query': serializer.toJson<String>(query),
      'lastUsedAt': serializer.toJson<DateTime>(lastUsedAt),
      'useCount': serializer.toJson<int>(useCount),
      'profileId': serializer.toJson<int>(profileId),
    };
  }

  SearchHistoryData copyWith({
    String? query,
    DateTime? lastUsedAt,
    int? useCount,
    int? profileId,
  }) => SearchHistoryData(
    query: query ?? this.query,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    useCount: useCount ?? this.useCount,
    profileId: profileId ?? this.profileId,
  );
  SearchHistoryData copyWithCompanion(SearchHistoryCompanion data) {
    return SearchHistoryData(
      query: data.query.present ? data.query.value : this.query,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
      useCount: data.useCount.present ? data.useCount.value : this.useCount,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryData(')
          ..write('query: $query, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('useCount: $useCount, ')
          ..write('profileId: $profileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(query, lastUsedAt, useCount, profileId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchHistoryData &&
          other.query == this.query &&
          other.lastUsedAt == this.lastUsedAt &&
          other.useCount == this.useCount &&
          other.profileId == this.profileId);
}

class SearchHistoryCompanion extends UpdateCompanion<SearchHistoryData> {
  final Value<String> query;
  final Value<DateTime> lastUsedAt;
  final Value<int> useCount;
  final Value<int> profileId;
  final Value<int> rowid;
  const SearchHistoryCompanion({
    this.query = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.useCount = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SearchHistoryCompanion.insert({
    required String query,
    this.lastUsedAt = const Value.absent(),
    this.useCount = const Value.absent(),
    this.profileId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : query = Value(query);
  static Insertable<SearchHistoryData> custom({
    Expression<String>? query,
    Expression<DateTime>? lastUsedAt,
    Expression<int>? useCount,
    Expression<int>? profileId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (query != null) 'query': query,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (useCount != null) 'use_count': useCount,
      if (profileId != null) 'profile_id': profileId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SearchHistoryCompanion copyWith({
    Value<String>? query,
    Value<DateTime>? lastUsedAt,
    Value<int>? useCount,
    Value<int>? profileId,
    Value<int>? rowid,
  }) {
    return SearchHistoryCompanion(
      query: query ?? this.query,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      useCount: useCount ?? this.useCount,
      profileId: profileId ?? this.profileId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (query.present) {
      map['query'] = Variable<String>(query.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (useCount.present) {
      map['use_count'] = Variable<int>(useCount.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<int>(profileId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryCompanion(')
          ..write('query: $query, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('useCount: $useCount, ')
          ..write('profileId: $profileId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiSimilarCacheTable extends AiSimilarCache
    with TableInfo<$AiSimilarCacheTable, AiSimilarCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiSimilarCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<int> streamId = GeneratedColumn<int>(
    'stream_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceHashMeta = const VerificationMeta(
    'sourceHash',
  );
  @override
  late final GeneratedColumn<String> sourceHash = GeneratedColumn<String>(
    'source_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generatedAtMeta = const VerificationMeta(
    'generatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> generatedAt = GeneratedColumn<DateTime>(
    'generated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    streamId,
    type,
    payloadJson,
    sourceHash,
    generatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_similar_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiSimilarCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streamIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('source_hash')) {
      context.handle(
        _sourceHashMeta,
        sourceHash.isAcceptableOrUnknown(data['source_hash']!, _sourceHashMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceHashMeta);
    }
    if (data.containsKey('generated_at')) {
      context.handle(
        _generatedAtMeta,
        generatedAt.isAcceptableOrUnknown(
          data['generated_at']!,
          _generatedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {streamId, type};
  @override
  AiSimilarCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiSimilarCacheData(
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stream_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      sourceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_hash'],
      )!,
      generatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}generated_at'],
      )!,
    );
  }

  @override
  $AiSimilarCacheTable createAlias(String alias) {
    return $AiSimilarCacheTable(attachedDatabase, alias);
  }
}

class AiSimilarCacheData extends DataClass
    implements Insertable<AiSimilarCacheData> {
  /// `Channel.streamId` of the title the user opened.
  final int streamId;

  /// `Channel.type` — movie / series / live. Same id can coexist
  /// across types in some Xtream catalogues, so it's part of the PK.
  final String type;

  /// JSON-encoded `[{label, items: [{streamId, reason}, ...]}, ...]`
  /// — the SimilarGroup payload, ready to be deserialised straight
  /// into the existing UI.
  final String payloadJson;

  /// Fingerprint of the inputs that would change the AI's answer:
  /// current title + favourites-snapshot-hash + prompt-version.
  /// Mismatch on read forces a refresh.
  final String sourceHash;
  final DateTime generatedAt;
  const AiSimilarCacheData({
    required this.streamId,
    required this.type,
    required this.payloadJson,
    required this.sourceHash,
    required this.generatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stream_id'] = Variable<int>(streamId);
    map['type'] = Variable<String>(type);
    map['payload_json'] = Variable<String>(payloadJson);
    map['source_hash'] = Variable<String>(sourceHash);
    map['generated_at'] = Variable<DateTime>(generatedAt);
    return map;
  }

  AiSimilarCacheCompanion toCompanion(bool nullToAbsent) {
    return AiSimilarCacheCompanion(
      streamId: Value(streamId),
      type: Value(type),
      payloadJson: Value(payloadJson),
      sourceHash: Value(sourceHash),
      generatedAt: Value(generatedAt),
    );
  }

  factory AiSimilarCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiSimilarCacheData(
      streamId: serializer.fromJson<int>(json['streamId']),
      type: serializer.fromJson<String>(json['type']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      sourceHash: serializer.fromJson<String>(json['sourceHash']),
      generatedAt: serializer.fromJson<DateTime>(json['generatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'streamId': serializer.toJson<int>(streamId),
      'type': serializer.toJson<String>(type),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'sourceHash': serializer.toJson<String>(sourceHash),
      'generatedAt': serializer.toJson<DateTime>(generatedAt),
    };
  }

  AiSimilarCacheData copyWith({
    int? streamId,
    String? type,
    String? payloadJson,
    String? sourceHash,
    DateTime? generatedAt,
  }) => AiSimilarCacheData(
    streamId: streamId ?? this.streamId,
    type: type ?? this.type,
    payloadJson: payloadJson ?? this.payloadJson,
    sourceHash: sourceHash ?? this.sourceHash,
    generatedAt: generatedAt ?? this.generatedAt,
  );
  AiSimilarCacheData copyWithCompanion(AiSimilarCacheCompanion data) {
    return AiSimilarCacheData(
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      type: data.type.present ? data.type.value : this.type,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      sourceHash: data.sourceHash.present
          ? data.sourceHash.value
          : this.sourceHash,
      generatedAt: data.generatedAt.present
          ? data.generatedAt.value
          : this.generatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiSimilarCacheData(')
          ..write('streamId: $streamId, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('generatedAt: $generatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(streamId, type, payloadJson, sourceHash, generatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiSimilarCacheData &&
          other.streamId == this.streamId &&
          other.type == this.type &&
          other.payloadJson == this.payloadJson &&
          other.sourceHash == this.sourceHash &&
          other.generatedAt == this.generatedAt);
}

class AiSimilarCacheCompanion extends UpdateCompanion<AiSimilarCacheData> {
  final Value<int> streamId;
  final Value<String> type;
  final Value<String> payloadJson;
  final Value<String> sourceHash;
  final Value<DateTime> generatedAt;
  final Value<int> rowid;
  const AiSimilarCacheCompanion({
    this.streamId = const Value.absent(),
    this.type = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.sourceHash = const Value.absent(),
    this.generatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiSimilarCacheCompanion.insert({
    required int streamId,
    required String type,
    required String payloadJson,
    required String sourceHash,
    this.generatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : streamId = Value(streamId),
       type = Value(type),
       payloadJson = Value(payloadJson),
       sourceHash = Value(sourceHash);
  static Insertable<AiSimilarCacheData> custom({
    Expression<int>? streamId,
    Expression<String>? type,
    Expression<String>? payloadJson,
    Expression<String>? sourceHash,
    Expression<DateTime>? generatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (streamId != null) 'stream_id': streamId,
      if (type != null) 'type': type,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (sourceHash != null) 'source_hash': sourceHash,
      if (generatedAt != null) 'generated_at': generatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiSimilarCacheCompanion copyWith({
    Value<int>? streamId,
    Value<String>? type,
    Value<String>? payloadJson,
    Value<String>? sourceHash,
    Value<DateTime>? generatedAt,
    Value<int>? rowid,
  }) {
    return AiSimilarCacheCompanion(
      streamId: streamId ?? this.streamId,
      type: type ?? this.type,
      payloadJson: payloadJson ?? this.payloadJson,
      sourceHash: sourceHash ?? this.sourceHash,
      generatedAt: generatedAt ?? this.generatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (streamId.present) {
      map['stream_id'] = Variable<int>(streamId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (sourceHash.present) {
      map['source_hash'] = Variable<String>(sourceHash.value);
    }
    if (generatedAt.present) {
      map['generated_at'] = Variable<DateTime>(generatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiSimilarCacheCompanion(')
          ..write('streamId: $streamId, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('generatedAt: $generatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $ChannelsTable channels = $ChannelsTable(this);
  late final $ProgramsTable programs = $ProgramsTable(this);
  late final $PlaybackProgressTable playbackProgress = $PlaybackProgressTable(
    this,
  );
  late final $FavoritesTable favorites = $FavoritesTable(this);
  late final $WatchlistTable watchlist = $WatchlistTable(this);
  late final $SeriesTrackingTable seriesTracking = $SeriesTrackingTable(this);
  late final $IntroMarkersTable introMarkers = $IntroMarkersTable(this);
  late final $PlotAiCacheTable plotAiCache = $PlotAiCacheTable(this);
  late final $PersonalizedPicksCacheTable personalizedPicksCache =
      $PersonalizedPicksCacheTable(this);
  late final $AiCallLogsTable aiCallLogs = $AiCallLogsTable(this);
  late final $AiFeedbackTable aiFeedback = $AiFeedbackTable(this);
  late final $SearchHistoryTable searchHistory = $SearchHistoryTable(this);
  late final $AiSimilarCacheTable aiSimilarCache = $AiSimilarCacheTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    accounts,
    profiles,
    categories,
    channels,
    programs,
    playbackProgress,
    favorites,
    watchlist,
    seriesTracking,
    introMarkers,
    plotAiCache,
    personalizedPicksCache,
    aiCallLogs,
    aiFeedback,
    searchHistory,
    aiSimilarCache,
  ];
}

typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      Value<int> id,
      required String name,
      required String type,
      required String url,
      Value<String?> username,
      Value<String?> password,
      Value<bool> isActive,
      Value<DateTime> createdAt,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> type,
      Value<String> url,
      Value<String?> username,
      Value<String?> password,
      Value<bool> isActive,
      Value<DateTime> createdAt,
    });

class $$AccountsTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get password =>
      $composableBuilder(column: $table.password, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          Account,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (Account, BaseReferences<_$AppDatabase, $AccountsTable, Account>),
          Account,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String?> password = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                name: name,
                type: type,
                url: url,
                username: username,
                password: password,
                isActive: isActive,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String type,
                required String url,
                Value<String?> username = const Value.absent(),
                Value<String?> password = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                name: name,
                type: type,
                url: url,
                username: username,
                password: password,
                isActive: isActive,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      Account,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (Account, BaseReferences<_$AppDatabase, $AccountsTable, Account>),
      Account,
      PrefetchHooks Function()
    >;
typedef $$ProfilesTableCreateCompanionBuilder =
    ProfilesCompanion Function({
      Value<int> id,
      required String name,
      Value<String> avatarKey,
      Value<bool> isKids,
      Value<String?> pin,
      Value<DateTime> createdAt,
    });
typedef $$ProfilesTableUpdateCompanionBuilder =
    ProfilesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> avatarKey,
      Value<bool> isKids,
      Value<String?> pin,
      Value<DateTime> createdAt,
    });

class $$ProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarKey => $composableBuilder(
    column: $table.avatarKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isKids => $composableBuilder(
    column: $table.isKids,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pin => $composableBuilder(
    column: $table.pin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarKey => $composableBuilder(
    column: $table.avatarKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isKids => $composableBuilder(
    column: $table.isKids,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pin => $composableBuilder(
    column: $table.pin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatarKey =>
      $composableBuilder(column: $table.avatarKey, builder: (column) => column);

  GeneratedColumn<bool> get isKids =>
      $composableBuilder(column: $table.isKids, builder: (column) => column);

  GeneratedColumn<String> get pin =>
      $composableBuilder(column: $table.pin, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfilesTable,
          Profile,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (Profile, BaseReferences<_$AppDatabase, $ProfilesTable, Profile>),
          Profile,
          PrefetchHooks Function()
        > {
  $$ProfilesTableTableManager(_$AppDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> avatarKey = const Value.absent(),
                Value<bool> isKids = const Value.absent(),
                Value<String?> pin = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ProfilesCompanion(
                id: id,
                name: name,
                avatarKey: avatarKey,
                isKids: isKids,
                pin: pin,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String> avatarKey = const Value.absent(),
                Value<bool> isKids = const Value.absent(),
                Value<String?> pin = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ProfilesCompanion.insert(
                id: id,
                name: name,
                avatarKey: avatarKey,
                isKids: isKids,
                pin: pin,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfilesTable,
      Profile,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (Profile, BaseReferences<_$AppDatabase, $ProfilesTable, Profile>),
      Profile,
      PrefetchHooks Function()
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required String id,
      required String name,
      required String type,
      Value<bool> isHidden,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> type,
      Value<bool> isHidden,
      Value<int> rowid,
    });

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $CategoriesTable, Category> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ChannelsTable, List<Channel>> _channelsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.channels,
    aliasName: $_aliasNameGenerator(db.categories.id, db.channels.categoryId),
  );

  $$ChannelsTableProcessedTableManager get channelsRefs {
    final manager = $$ChannelsTableTableManager(
      $_db,
      $_db.channels,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_channelsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> channelsRefs(
    Expression<bool> Function($$ChannelsTableFilterComposer f) f,
  ) {
    final $$ChannelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableFilterComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<bool> get isHidden =>
      $composableBuilder(column: $table.isHidden, builder: (column) => column);

  Expression<T> channelsRefs<T extends Object>(
    Expression<T> Function($$ChannelsTableAnnotationComposer a) f,
  ) {
    final $$ChannelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableAnnotationComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, $$CategoriesTableReferences),
          Category,
          PrefetchHooks Function({bool channelsRefs})
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<bool> isHidden = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                type: type,
                isHidden: isHidden,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String type,
                Value<bool> isHidden = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                type: type,
                isHidden: isHidden,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({channelsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (channelsRefs) db.channels],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (channelsRefs)
                    await $_getPrefetchedData<
                      Category,
                      $CategoriesTable,
                      Channel
                    >(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences
                          ._channelsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CategoriesTableReferences(
                            db,
                            table,
                            p0,
                          ).channelsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, $$CategoriesTableReferences),
      Category,
      PrefetchHooks Function({bool channelsRefs})
    >;
typedef $$ChannelsTableCreateCompanionBuilder =
    ChannelsCompanion Function({
      required int streamId,
      required String name,
      required String type,
      required String categoryId,
      Value<String?> streamIcon,
      Value<double?> rating,
      Value<String?> year,
      Value<String?> added,
      Value<String?> backdropPath,
      Value<String?> youtubeTrailer,
      Value<String?> genre,
      Value<String?> plot,
      Value<String?> director,
      Value<String?> cast,
      Value<String?> streamUrl,
      Value<String?> epgChannelId,
      Value<int> rowid,
    });
typedef $$ChannelsTableUpdateCompanionBuilder =
    ChannelsCompanion Function({
      Value<int> streamId,
      Value<String> name,
      Value<String> type,
      Value<String> categoryId,
      Value<String?> streamIcon,
      Value<double?> rating,
      Value<String?> year,
      Value<String?> added,
      Value<String?> backdropPath,
      Value<String?> youtubeTrailer,
      Value<String?> genre,
      Value<String?> plot,
      Value<String?> director,
      Value<String?> cast,
      Value<String?> streamUrl,
      Value<String?> epgChannelId,
      Value<int> rowid,
    });

final class $$ChannelsTableReferences
    extends BaseReferences<_$AppDatabase, $ChannelsTable, Channel> {
  $$ChannelsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias(
        $_aliasNameGenerator(db.channels.categoryId, db.categories.id),
      );

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<String>('category_id')!;

    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ProgramsTable, List<Program>> _programsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.programs,
    aliasName: $_aliasNameGenerator(
      db.channels.streamId,
      db.programs.channelId,
    ),
  );

  $$ProgramsTableProcessedTableManager get programsRefs {
    final manager = $$ProgramsTableTableManager($_db, $_db.programs).filter(
      (f) => f.channelId.streamId.sqlEquals($_itemColumn<int>('stream_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_programsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChannelsTableFilterComposer
    extends Composer<_$AppDatabase, $ChannelsTable> {
  $$ChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamIcon => $composableBuilder(
    column: $table.streamIcon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get added => $composableBuilder(
    column: $table.added,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get youtubeTrailer => $composableBuilder(
    column: $table.youtubeTrailer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get director => $composableBuilder(
    column: $table.director,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cast => $composableBuilder(
    column: $table.cast,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamUrl => $composableBuilder(
    column: $table.streamUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get epgChannelId => $composableBuilder(
    column: $table.epgChannelId,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> programsRefs(
    Expression<bool> Function($$ProgramsTableFilterComposer f) f,
  ) {
    final $$ProgramsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.streamId,
      referencedTable: $db.programs,
      getReferencedColumn: (t) => t.channelId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramsTableFilterComposer(
            $db: $db,
            $table: $db.programs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChannelsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChannelsTable> {
  $$ChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamIcon => $composableBuilder(
    column: $table.streamIcon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get added => $composableBuilder(
    column: $table.added,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get youtubeTrailer => $composableBuilder(
    column: $table.youtubeTrailer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get director => $composableBuilder(
    column: $table.director,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cast => $composableBuilder(
    column: $table.cast,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamUrl => $composableBuilder(
    column: $table.streamUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get epgChannelId => $composableBuilder(
    column: $table.epgChannelId,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChannelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChannelsTable> {
  $$ChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get streamIcon => $composableBuilder(
    column: $table.streamIcon,
    builder: (column) => column,
  );

  GeneratedColumn<double> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<String> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get added =>
      $composableBuilder(column: $table.added, builder: (column) => column);

  GeneratedColumn<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get youtubeTrailer => $composableBuilder(
    column: $table.youtubeTrailer,
    builder: (column) => column,
  );

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<String> get plot =>
      $composableBuilder(column: $table.plot, builder: (column) => column);

  GeneratedColumn<String> get director =>
      $composableBuilder(column: $table.director, builder: (column) => column);

  GeneratedColumn<String> get cast =>
      $composableBuilder(column: $table.cast, builder: (column) => column);

  GeneratedColumn<String> get streamUrl =>
      $composableBuilder(column: $table.streamUrl, builder: (column) => column);

  GeneratedColumn<String> get epgChannelId => $composableBuilder(
    column: $table.epgChannelId,
    builder: (column) => column,
  );

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> programsRefs<T extends Object>(
    Expression<T> Function($$ProgramsTableAnnotationComposer a) f,
  ) {
    final $$ProgramsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.streamId,
      referencedTable: $db.programs,
      getReferencedColumn: (t) => t.channelId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramsTableAnnotationComposer(
            $db: $db,
            $table: $db.programs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChannelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChannelsTable,
          Channel,
          $$ChannelsTableFilterComposer,
          $$ChannelsTableOrderingComposer,
          $$ChannelsTableAnnotationComposer,
          $$ChannelsTableCreateCompanionBuilder,
          $$ChannelsTableUpdateCompanionBuilder,
          (Channel, $$ChannelsTableReferences),
          Channel,
          PrefetchHooks Function({bool categoryId, bool programsRefs})
        > {
  $$ChannelsTableTableManager(_$AppDatabase db, $ChannelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> streamId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<String?> streamIcon = const Value.absent(),
                Value<double?> rating = const Value.absent(),
                Value<String?> year = const Value.absent(),
                Value<String?> added = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<String?> youtubeTrailer = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String?> director = const Value.absent(),
                Value<String?> cast = const Value.absent(),
                Value<String?> streamUrl = const Value.absent(),
                Value<String?> epgChannelId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion(
                streamId: streamId,
                name: name,
                type: type,
                categoryId: categoryId,
                streamIcon: streamIcon,
                rating: rating,
                year: year,
                added: added,
                backdropPath: backdropPath,
                youtubeTrailer: youtubeTrailer,
                genre: genre,
                plot: plot,
                director: director,
                cast: cast,
                streamUrl: streamUrl,
                epgChannelId: epgChannelId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int streamId,
                required String name,
                required String type,
                required String categoryId,
                Value<String?> streamIcon = const Value.absent(),
                Value<double?> rating = const Value.absent(),
                Value<String?> year = const Value.absent(),
                Value<String?> added = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<String?> youtubeTrailer = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String?> director = const Value.absent(),
                Value<String?> cast = const Value.absent(),
                Value<String?> streamUrl = const Value.absent(),
                Value<String?> epgChannelId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion.insert(
                streamId: streamId,
                name: name,
                type: type,
                categoryId: categoryId,
                streamIcon: streamIcon,
                rating: rating,
                year: year,
                added: added,
                backdropPath: backdropPath,
                youtubeTrailer: youtubeTrailer,
                genre: genre,
                plot: plot,
                director: director,
                cast: cast,
                streamUrl: streamUrl,
                epgChannelId: epgChannelId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChannelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false, programsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (programsRefs) db.programs],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.categoryId,
                                referencedTable: $$ChannelsTableReferences
                                    ._categoryIdTable(db),
                                referencedColumn: $$ChannelsTableReferences
                                    ._categoryIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (programsRefs)
                    await $_getPrefetchedData<Channel, $ChannelsTable, Program>(
                      currentTable: table,
                      referencedTable: $$ChannelsTableReferences
                          ._programsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ChannelsTableReferences(db, table, p0).programsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.channelId == item.streamId,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChannelsTable,
      Channel,
      $$ChannelsTableFilterComposer,
      $$ChannelsTableOrderingComposer,
      $$ChannelsTableAnnotationComposer,
      $$ChannelsTableCreateCompanionBuilder,
      $$ChannelsTableUpdateCompanionBuilder,
      (Channel, $$ChannelsTableReferences),
      Channel,
      PrefetchHooks Function({bool categoryId, bool programsRefs})
    >;
typedef $$ProgramsTableCreateCompanionBuilder =
    ProgramsCompanion Function({
      Value<int> id,
      required int channelId,
      required String title,
      Value<String?> description,
      required DateTime start,
      required DateTime stop,
    });
typedef $$ProgramsTableUpdateCompanionBuilder =
    ProgramsCompanion Function({
      Value<int> id,
      Value<int> channelId,
      Value<String> title,
      Value<String?> description,
      Value<DateTime> start,
      Value<DateTime> stop,
    });

final class $$ProgramsTableReferences
    extends BaseReferences<_$AppDatabase, $ProgramsTable, Program> {
  $$ProgramsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChannelsTable _channelIdTable(_$AppDatabase db) =>
      db.channels.createAlias(
        $_aliasNameGenerator(db.programs.channelId, db.channels.streamId),
      );

  $$ChannelsTableProcessedTableManager get channelId {
    final $_column = $_itemColumn<int>('channel_id')!;

    final manager = $$ChannelsTableTableManager(
      $_db,
      $_db.channels,
    ).filter((f) => f.streamId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_channelIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProgramsTableFilterComposer
    extends Composer<_$AppDatabase, $ProgramsTable> {
  $$ProgramsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get stop => $composableBuilder(
    column: $table.stop,
    builder: (column) => ColumnFilters(column),
  );

  $$ChannelsTableFilterComposer get channelId {
    final $$ChannelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.channelId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.streamId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableFilterComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgramsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProgramsTable> {
  $$ProgramsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get stop => $composableBuilder(
    column: $table.stop,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChannelsTableOrderingComposer get channelId {
    final $$ChannelsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.channelId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.streamId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableOrderingComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgramsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProgramsTable> {
  $$ProgramsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get start =>
      $composableBuilder(column: $table.start, builder: (column) => column);

  GeneratedColumn<DateTime> get stop =>
      $composableBuilder(column: $table.stop, builder: (column) => column);

  $$ChannelsTableAnnotationComposer get channelId {
    final $$ChannelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.channelId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.streamId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableAnnotationComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgramsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProgramsTable,
          Program,
          $$ProgramsTableFilterComposer,
          $$ProgramsTableOrderingComposer,
          $$ProgramsTableAnnotationComposer,
          $$ProgramsTableCreateCompanionBuilder,
          $$ProgramsTableUpdateCompanionBuilder,
          (Program, $$ProgramsTableReferences),
          Program,
          PrefetchHooks Function({bool channelId})
        > {
  $$ProgramsTableTableManager(_$AppDatabase db, $ProgramsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgramsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgramsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgramsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> channelId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> start = const Value.absent(),
                Value<DateTime> stop = const Value.absent(),
              }) => ProgramsCompanion(
                id: id,
                channelId: channelId,
                title: title,
                description: description,
                start: start,
                stop: stop,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int channelId,
                required String title,
                Value<String?> description = const Value.absent(),
                required DateTime start,
                required DateTime stop,
              }) => ProgramsCompanion.insert(
                id: id,
                channelId: channelId,
                title: title,
                description: description,
                start: start,
                stop: stop,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProgramsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({channelId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (channelId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.channelId,
                                referencedTable: $$ProgramsTableReferences
                                    ._channelIdTable(db),
                                referencedColumn: $$ProgramsTableReferences
                                    ._channelIdTable(db)
                                    .streamId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProgramsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProgramsTable,
      Program,
      $$ProgramsTableFilterComposer,
      $$ProgramsTableOrderingComposer,
      $$ProgramsTableAnnotationComposer,
      $$ProgramsTableCreateCompanionBuilder,
      $$ProgramsTableUpdateCompanionBuilder,
      (Program, $$ProgramsTableReferences),
      Program,
      PrefetchHooks Function({bool channelId})
    >;
typedef $$PlaybackProgressTableCreateCompanionBuilder =
    PlaybackProgressCompanion Function({
      required int streamId,
      required String type,
      required int position,
      required int duration,
      Value<DateTime> updatedAt,
      Value<bool> isFinished,
      Value<int> profileId,
      Value<int> rowid,
    });
typedef $$PlaybackProgressTableUpdateCompanionBuilder =
    PlaybackProgressCompanion Function({
      Value<int> streamId,
      Value<String> type,
      Value<int> position,
      Value<int> duration,
      Value<DateTime> updatedAt,
      Value<bool> isFinished,
      Value<int> profileId,
      Value<int> rowid,
    });

class $$PlaybackProgressTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackProgressTable> {
  $$PlaybackProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFinished => $composableBuilder(
    column: $table.isFinished,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaybackProgressTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackProgressTable> {
  $$PlaybackProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFinished => $composableBuilder(
    column: $table.isFinished,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaybackProgressTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackProgressTable> {
  $$PlaybackProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get duration =>
      $composableBuilder(column: $table.duration, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isFinished => $composableBuilder(
    column: $table.isFinished,
    builder: (column) => column,
  );

  GeneratedColumn<int> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);
}

class $$PlaybackProgressTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaybackProgressTable,
          PlaybackProgressData,
          $$PlaybackProgressTableFilterComposer,
          $$PlaybackProgressTableOrderingComposer,
          $$PlaybackProgressTableAnnotationComposer,
          $$PlaybackProgressTableCreateCompanionBuilder,
          $$PlaybackProgressTableUpdateCompanionBuilder,
          (
            PlaybackProgressData,
            BaseReferences<
              _$AppDatabase,
              $PlaybackProgressTable,
              PlaybackProgressData
            >,
          ),
          PlaybackProgressData,
          PrefetchHooks Function()
        > {
  $$PlaybackProgressTableTableManager(
    _$AppDatabase db,
    $PlaybackProgressTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaybackProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaybackProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> streamId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> duration = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isFinished = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaybackProgressCompanion(
                streamId: streamId,
                type: type,
                position: position,
                duration: duration,
                updatedAt: updatedAt,
                isFinished: isFinished,
                profileId: profileId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int streamId,
                required String type,
                required int position,
                required int duration,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isFinished = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaybackProgressCompanion.insert(
                streamId: streamId,
                type: type,
                position: position,
                duration: duration,
                updatedAt: updatedAt,
                isFinished: isFinished,
                profileId: profileId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaybackProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaybackProgressTable,
      PlaybackProgressData,
      $$PlaybackProgressTableFilterComposer,
      $$PlaybackProgressTableOrderingComposer,
      $$PlaybackProgressTableAnnotationComposer,
      $$PlaybackProgressTableCreateCompanionBuilder,
      $$PlaybackProgressTableUpdateCompanionBuilder,
      (
        PlaybackProgressData,
        BaseReferences<
          _$AppDatabase,
          $PlaybackProgressTable,
          PlaybackProgressData
        >,
      ),
      PlaybackProgressData,
      PrefetchHooks Function()
    >;
typedef $$FavoritesTableCreateCompanionBuilder =
    FavoritesCompanion Function({
      required int streamId,
      required String streamType,
      required String name,
      Value<String?> thumbnail,
      Value<DateTime> addedAt,
      Value<int> profileId,
      Value<int> rowid,
    });
typedef $$FavoritesTableUpdateCompanionBuilder =
    FavoritesCompanion Function({
      Value<int> streamId,
      Value<String> streamType,
      Value<String> name,
      Value<String?> thumbnail,
      Value<DateTime> addedAt,
      Value<int> profileId,
      Value<int> rowid,
    });

class $$FavoritesTableFilterComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamType => $composableBuilder(
    column: $table.streamType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnail => $composableBuilder(
    column: $table.thumbnail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoritesTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamType => $composableBuilder(
    column: $table.streamType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnail => $composableBuilder(
    column: $table.thumbnail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoritesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get streamType => $composableBuilder(
    column: $table.streamType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get thumbnail =>
      $composableBuilder(column: $table.thumbnail, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);
}

class $$FavoritesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoritesTable,
          Favorite,
          $$FavoritesTableFilterComposer,
          $$FavoritesTableOrderingComposer,
          $$FavoritesTableAnnotationComposer,
          $$FavoritesTableCreateCompanionBuilder,
          $$FavoritesTableUpdateCompanionBuilder,
          (Favorite, BaseReferences<_$AppDatabase, $FavoritesTable, Favorite>),
          Favorite,
          PrefetchHooks Function()
        > {
  $$FavoritesTableTableManager(_$AppDatabase db, $FavoritesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> streamId = const Value.absent(),
                Value<String> streamType = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> thumbnail = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion(
                streamId: streamId,
                streamType: streamType,
                name: name,
                thumbnail: thumbnail,
                addedAt: addedAt,
                profileId: profileId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int streamId,
                required String streamType,
                required String name,
                Value<String?> thumbnail = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion.insert(
                streamId: streamId,
                streamType: streamType,
                name: name,
                thumbnail: thumbnail,
                addedAt: addedAt,
                profileId: profileId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoritesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoritesTable,
      Favorite,
      $$FavoritesTableFilterComposer,
      $$FavoritesTableOrderingComposer,
      $$FavoritesTableAnnotationComposer,
      $$FavoritesTableCreateCompanionBuilder,
      $$FavoritesTableUpdateCompanionBuilder,
      (Favorite, BaseReferences<_$AppDatabase, $FavoritesTable, Favorite>),
      Favorite,
      PrefetchHooks Function()
    >;
typedef $$WatchlistTableCreateCompanionBuilder =
    WatchlistCompanion Function({
      required int streamId,
      required String streamType,
      required String name,
      Value<String?> thumbnail,
      Value<DateTime> addedAt,
      Value<int> profileId,
      Value<int> rowid,
    });
typedef $$WatchlistTableUpdateCompanionBuilder =
    WatchlistCompanion Function({
      Value<int> streamId,
      Value<String> streamType,
      Value<String> name,
      Value<String?> thumbnail,
      Value<DateTime> addedAt,
      Value<int> profileId,
      Value<int> rowid,
    });

class $$WatchlistTableFilterComposer
    extends Composer<_$AppDatabase, $WatchlistTable> {
  $$WatchlistTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamType => $composableBuilder(
    column: $table.streamType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnail => $composableBuilder(
    column: $table.thumbnail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchlistTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchlistTable> {
  $$WatchlistTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamType => $composableBuilder(
    column: $table.streamType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnail => $composableBuilder(
    column: $table.thumbnail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchlistTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchlistTable> {
  $$WatchlistTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get streamType => $composableBuilder(
    column: $table.streamType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get thumbnail =>
      $composableBuilder(column: $table.thumbnail, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);
}

class $$WatchlistTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchlistTable,
          WatchlistData,
          $$WatchlistTableFilterComposer,
          $$WatchlistTableOrderingComposer,
          $$WatchlistTableAnnotationComposer,
          $$WatchlistTableCreateCompanionBuilder,
          $$WatchlistTableUpdateCompanionBuilder,
          (
            WatchlistData,
            BaseReferences<_$AppDatabase, $WatchlistTable, WatchlistData>,
          ),
          WatchlistData,
          PrefetchHooks Function()
        > {
  $$WatchlistTableTableManager(_$AppDatabase db, $WatchlistTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchlistTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchlistTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchlistTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> streamId = const Value.absent(),
                Value<String> streamType = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> thumbnail = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchlistCompanion(
                streamId: streamId,
                streamType: streamType,
                name: name,
                thumbnail: thumbnail,
                addedAt: addedAt,
                profileId: profileId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int streamId,
                required String streamType,
                required String name,
                Value<String?> thumbnail = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchlistCompanion.insert(
                streamId: streamId,
                streamType: streamType,
                name: name,
                thumbnail: thumbnail,
                addedAt: addedAt,
                profileId: profileId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchlistTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchlistTable,
      WatchlistData,
      $$WatchlistTableFilterComposer,
      $$WatchlistTableOrderingComposer,
      $$WatchlistTableAnnotationComposer,
      $$WatchlistTableCreateCompanionBuilder,
      $$WatchlistTableUpdateCompanionBuilder,
      (
        WatchlistData,
        BaseReferences<_$AppDatabase, $WatchlistTable, WatchlistData>,
      ),
      WatchlistData,
      PrefetchHooks Function()
    >;
typedef $$SeriesTrackingTableCreateCompanionBuilder =
    SeriesTrackingCompanion Function({
      required int seriesId,
      required int knownEpisodeCount,
      Value<int> newEpisodeCount,
      Value<bool> hasNewEpisodes,
      Value<DateTime> lastCheckedAt,
      Value<int> profileId,
      Value<int> rowid,
    });
typedef $$SeriesTrackingTableUpdateCompanionBuilder =
    SeriesTrackingCompanion Function({
      Value<int> seriesId,
      Value<int> knownEpisodeCount,
      Value<int> newEpisodeCount,
      Value<bool> hasNewEpisodes,
      Value<DateTime> lastCheckedAt,
      Value<int> profileId,
      Value<int> rowid,
    });

class $$SeriesTrackingTableFilterComposer
    extends Composer<_$AppDatabase, $SeriesTrackingTable> {
  $$SeriesTrackingTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get knownEpisodeCount => $composableBuilder(
    column: $table.knownEpisodeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get newEpisodeCount => $composableBuilder(
    column: $table.newEpisodeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasNewEpisodes => $composableBuilder(
    column: $table.hasNewEpisodes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeriesTrackingTableOrderingComposer
    extends Composer<_$AppDatabase, $SeriesTrackingTable> {
  $$SeriesTrackingTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get knownEpisodeCount => $composableBuilder(
    column: $table.knownEpisodeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get newEpisodeCount => $composableBuilder(
    column: $table.newEpisodeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasNewEpisodes => $composableBuilder(
    column: $table.hasNewEpisodes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeriesTrackingTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeriesTrackingTable> {
  $$SeriesTrackingTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<int> get knownEpisodeCount => $composableBuilder(
    column: $table.knownEpisodeCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get newEpisodeCount => $composableBuilder(
    column: $table.newEpisodeCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasNewEpisodes => $composableBuilder(
    column: $table.hasNewEpisodes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);
}

class $$SeriesTrackingTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeriesTrackingTable,
          SeriesTrackingData,
          $$SeriesTrackingTableFilterComposer,
          $$SeriesTrackingTableOrderingComposer,
          $$SeriesTrackingTableAnnotationComposer,
          $$SeriesTrackingTableCreateCompanionBuilder,
          $$SeriesTrackingTableUpdateCompanionBuilder,
          (
            SeriesTrackingData,
            BaseReferences<
              _$AppDatabase,
              $SeriesTrackingTable,
              SeriesTrackingData
            >,
          ),
          SeriesTrackingData,
          PrefetchHooks Function()
        > {
  $$SeriesTrackingTableTableManager(
    _$AppDatabase db,
    $SeriesTrackingTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeriesTrackingTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeriesTrackingTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeriesTrackingTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seriesId = const Value.absent(),
                Value<int> knownEpisodeCount = const Value.absent(),
                Value<int> newEpisodeCount = const Value.absent(),
                Value<bool> hasNewEpisodes = const Value.absent(),
                Value<DateTime> lastCheckedAt = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeriesTrackingCompanion(
                seriesId: seriesId,
                knownEpisodeCount: knownEpisodeCount,
                newEpisodeCount: newEpisodeCount,
                hasNewEpisodes: hasNewEpisodes,
                lastCheckedAt: lastCheckedAt,
                profileId: profileId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int seriesId,
                required int knownEpisodeCount,
                Value<int> newEpisodeCount = const Value.absent(),
                Value<bool> hasNewEpisodes = const Value.absent(),
                Value<DateTime> lastCheckedAt = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeriesTrackingCompanion.insert(
                seriesId: seriesId,
                knownEpisodeCount: knownEpisodeCount,
                newEpisodeCount: newEpisodeCount,
                hasNewEpisodes: hasNewEpisodes,
                lastCheckedAt: lastCheckedAt,
                profileId: profileId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeriesTrackingTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeriesTrackingTable,
      SeriesTrackingData,
      $$SeriesTrackingTableFilterComposer,
      $$SeriesTrackingTableOrderingComposer,
      $$SeriesTrackingTableAnnotationComposer,
      $$SeriesTrackingTableCreateCompanionBuilder,
      $$SeriesTrackingTableUpdateCompanionBuilder,
      (
        SeriesTrackingData,
        BaseReferences<_$AppDatabase, $SeriesTrackingTable, SeriesTrackingData>,
      ),
      SeriesTrackingData,
      PrefetchHooks Function()
    >;
typedef $$IntroMarkersTableCreateCompanionBuilder =
    IntroMarkersCompanion Function({
      Value<int> seriesId,
      required int introStartMs,
      required int introEndMs,
      Value<DateTime> updatedAt,
    });
typedef $$IntroMarkersTableUpdateCompanionBuilder =
    IntroMarkersCompanion Function({
      Value<int> seriesId,
      Value<int> introStartMs,
      Value<int> introEndMs,
      Value<DateTime> updatedAt,
    });

class $$IntroMarkersTableFilterComposer
    extends Composer<_$AppDatabase, $IntroMarkersTable> {
  $$IntroMarkersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get introStartMs => $composableBuilder(
    column: $table.introStartMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get introEndMs => $composableBuilder(
    column: $table.introEndMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IntroMarkersTableOrderingComposer
    extends Composer<_$AppDatabase, $IntroMarkersTable> {
  $$IntroMarkersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get introStartMs => $composableBuilder(
    column: $table.introStartMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get introEndMs => $composableBuilder(
    column: $table.introEndMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IntroMarkersTableAnnotationComposer
    extends Composer<_$AppDatabase, $IntroMarkersTable> {
  $$IntroMarkersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<int> get introStartMs => $composableBuilder(
    column: $table.introStartMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get introEndMs => $composableBuilder(
    column: $table.introEndMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$IntroMarkersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IntroMarkersTable,
          IntroMarker,
          $$IntroMarkersTableFilterComposer,
          $$IntroMarkersTableOrderingComposer,
          $$IntroMarkersTableAnnotationComposer,
          $$IntroMarkersTableCreateCompanionBuilder,
          $$IntroMarkersTableUpdateCompanionBuilder,
          (
            IntroMarker,
            BaseReferences<_$AppDatabase, $IntroMarkersTable, IntroMarker>,
          ),
          IntroMarker,
          PrefetchHooks Function()
        > {
  $$IntroMarkersTableTableManager(_$AppDatabase db, $IntroMarkersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IntroMarkersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IntroMarkersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IntroMarkersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seriesId = const Value.absent(),
                Value<int> introStartMs = const Value.absent(),
                Value<int> introEndMs = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => IntroMarkersCompanion(
                seriesId: seriesId,
                introStartMs: introStartMs,
                introEndMs: introEndMs,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> seriesId = const Value.absent(),
                required int introStartMs,
                required int introEndMs,
                Value<DateTime> updatedAt = const Value.absent(),
              }) => IntroMarkersCompanion.insert(
                seriesId: seriesId,
                introStartMs: introStartMs,
                introEndMs: introEndMs,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IntroMarkersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IntroMarkersTable,
      IntroMarker,
      $$IntroMarkersTableFilterComposer,
      $$IntroMarkersTableOrderingComposer,
      $$IntroMarkersTableAnnotationComposer,
      $$IntroMarkersTableCreateCompanionBuilder,
      $$IntroMarkersTableUpdateCompanionBuilder,
      (
        IntroMarker,
        BaseReferences<_$AppDatabase, $IntroMarkersTable, IntroMarker>,
      ),
      IntroMarker,
      PrefetchHooks Function()
    >;
typedef $$PlotAiCacheTableCreateCompanionBuilder =
    PlotAiCacheCompanion Function({
      required int streamId,
      required String mode,
      required String targetLanguage,
      required String content,
      required String sourceHash,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$PlotAiCacheTableUpdateCompanionBuilder =
    PlotAiCacheCompanion Function({
      Value<int> streamId,
      Value<String> mode,
      Value<String> targetLanguage,
      Value<String> content,
      Value<String> sourceHash,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$PlotAiCacheTableFilterComposer
    extends Composer<_$AppDatabase, $PlotAiCacheTable> {
  $$PlotAiCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetLanguage => $composableBuilder(
    column: $table.targetLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlotAiCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $PlotAiCacheTable> {
  $$PlotAiCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetLanguage => $composableBuilder(
    column: $table.targetLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlotAiCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlotAiCacheTable> {
  $$PlotAiCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get targetLanguage => $composableBuilder(
    column: $table.targetLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PlotAiCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlotAiCacheTable,
          PlotAiCacheData,
          $$PlotAiCacheTableFilterComposer,
          $$PlotAiCacheTableOrderingComposer,
          $$PlotAiCacheTableAnnotationComposer,
          $$PlotAiCacheTableCreateCompanionBuilder,
          $$PlotAiCacheTableUpdateCompanionBuilder,
          (
            PlotAiCacheData,
            BaseReferences<_$AppDatabase, $PlotAiCacheTable, PlotAiCacheData>,
          ),
          PlotAiCacheData,
          PrefetchHooks Function()
        > {
  $$PlotAiCacheTableTableManager(_$AppDatabase db, $PlotAiCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlotAiCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlotAiCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlotAiCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> streamId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> targetLanguage = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> sourceHash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlotAiCacheCompanion(
                streamId: streamId,
                mode: mode,
                targetLanguage: targetLanguage,
                content: content,
                sourceHash: sourceHash,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int streamId,
                required String mode,
                required String targetLanguage,
                required String content,
                required String sourceHash,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlotAiCacheCompanion.insert(
                streamId: streamId,
                mode: mode,
                targetLanguage: targetLanguage,
                content: content,
                sourceHash: sourceHash,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlotAiCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlotAiCacheTable,
      PlotAiCacheData,
      $$PlotAiCacheTableFilterComposer,
      $$PlotAiCacheTableOrderingComposer,
      $$PlotAiCacheTableAnnotationComposer,
      $$PlotAiCacheTableCreateCompanionBuilder,
      $$PlotAiCacheTableUpdateCompanionBuilder,
      (
        PlotAiCacheData,
        BaseReferences<_$AppDatabase, $PlotAiCacheTable, PlotAiCacheData>,
      ),
      PlotAiCacheData,
      PrefetchHooks Function()
    >;
typedef $$PersonalizedPicksCacheTableCreateCompanionBuilder =
    PersonalizedPicksCacheCompanion Function({
      Value<int> id,
      required String picksJson,
      required String sourceHash,
      Value<DateTime> generatedAt,
    });
typedef $$PersonalizedPicksCacheTableUpdateCompanionBuilder =
    PersonalizedPicksCacheCompanion Function({
      Value<int> id,
      Value<String> picksJson,
      Value<String> sourceHash,
      Value<DateTime> generatedAt,
    });

class $$PersonalizedPicksCacheTableFilterComposer
    extends Composer<_$AppDatabase, $PersonalizedPicksCacheTable> {
  $$PersonalizedPicksCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get picksJson => $composableBuilder(
    column: $table.picksJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PersonalizedPicksCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $PersonalizedPicksCacheTable> {
  $$PersonalizedPicksCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get picksJson => $composableBuilder(
    column: $table.picksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PersonalizedPicksCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $PersonalizedPicksCacheTable> {
  $$PersonalizedPicksCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get picksJson =>
      $composableBuilder(column: $table.picksJson, builder: (column) => column);

  GeneratedColumn<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => column,
  );
}

class $$PersonalizedPicksCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PersonalizedPicksCacheTable,
          PersonalizedPicksCacheData,
          $$PersonalizedPicksCacheTableFilterComposer,
          $$PersonalizedPicksCacheTableOrderingComposer,
          $$PersonalizedPicksCacheTableAnnotationComposer,
          $$PersonalizedPicksCacheTableCreateCompanionBuilder,
          $$PersonalizedPicksCacheTableUpdateCompanionBuilder,
          (
            PersonalizedPicksCacheData,
            BaseReferences<
              _$AppDatabase,
              $PersonalizedPicksCacheTable,
              PersonalizedPicksCacheData
            >,
          ),
          PersonalizedPicksCacheData,
          PrefetchHooks Function()
        > {
  $$PersonalizedPicksCacheTableTableManager(
    _$AppDatabase db,
    $PersonalizedPicksCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonalizedPicksCacheTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PersonalizedPicksCacheTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PersonalizedPicksCacheTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> picksJson = const Value.absent(),
                Value<String> sourceHash = const Value.absent(),
                Value<DateTime> generatedAt = const Value.absent(),
              }) => PersonalizedPicksCacheCompanion(
                id: id,
                picksJson: picksJson,
                sourceHash: sourceHash,
                generatedAt: generatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String picksJson,
                required String sourceHash,
                Value<DateTime> generatedAt = const Value.absent(),
              }) => PersonalizedPicksCacheCompanion.insert(
                id: id,
                picksJson: picksJson,
                sourceHash: sourceHash,
                generatedAt: generatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PersonalizedPicksCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PersonalizedPicksCacheTable,
      PersonalizedPicksCacheData,
      $$PersonalizedPicksCacheTableFilterComposer,
      $$PersonalizedPicksCacheTableOrderingComposer,
      $$PersonalizedPicksCacheTableAnnotationComposer,
      $$PersonalizedPicksCacheTableCreateCompanionBuilder,
      $$PersonalizedPicksCacheTableUpdateCompanionBuilder,
      (
        PersonalizedPicksCacheData,
        BaseReferences<
          _$AppDatabase,
          $PersonalizedPicksCacheTable,
          PersonalizedPicksCacheData
        >,
      ),
      PersonalizedPicksCacheData,
      PrefetchHooks Function()
    >;
typedef $$AiCallLogsTableCreateCompanionBuilder =
    AiCallLogsCompanion Function({
      Value<int> id,
      required String feature,
      required String model,
      required int latencyMs,
      required bool success,
      Value<bool> timedOut,
      Value<int> candidateCount,
      Value<int> outputCount,
      Value<String?> errorCode,
      Value<DateTime> createdAt,
    });
typedef $$AiCallLogsTableUpdateCompanionBuilder =
    AiCallLogsCompanion Function({
      Value<int> id,
      Value<String> feature,
      Value<String> model,
      Value<int> latencyMs,
      Value<bool> success,
      Value<bool> timedOut,
      Value<int> candidateCount,
      Value<int> outputCount,
      Value<String?> errorCode,
      Value<DateTime> createdAt,
    });

class $$AiCallLogsTableFilterComposer
    extends Composer<_$AppDatabase, $AiCallLogsTable> {
  $$AiCallLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feature => $composableBuilder(
    column: $table.feature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get success => $composableBuilder(
    column: $table.success,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get timedOut => $composableBuilder(
    column: $table.timedOut,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get candidateCount => $composableBuilder(
    column: $table.candidateCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get outputCount => $composableBuilder(
    column: $table.outputCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiCallLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $AiCallLogsTable> {
  $$AiCallLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feature => $composableBuilder(
    column: $table.feature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get success => $composableBuilder(
    column: $table.success,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get timedOut => $composableBuilder(
    column: $table.timedOut,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get candidateCount => $composableBuilder(
    column: $table.candidateCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get outputCount => $composableBuilder(
    column: $table.outputCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiCallLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiCallLogsTable> {
  $$AiCallLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get feature =>
      $composableBuilder(column: $table.feature, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get latencyMs =>
      $composableBuilder(column: $table.latencyMs, builder: (column) => column);

  GeneratedColumn<bool> get success =>
      $composableBuilder(column: $table.success, builder: (column) => column);

  GeneratedColumn<bool> get timedOut =>
      $composableBuilder(column: $table.timedOut, builder: (column) => column);

  GeneratedColumn<int> get candidateCount => $composableBuilder(
    column: $table.candidateCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get outputCount => $composableBuilder(
    column: $table.outputCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AiCallLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiCallLogsTable,
          AiCallLog,
          $$AiCallLogsTableFilterComposer,
          $$AiCallLogsTableOrderingComposer,
          $$AiCallLogsTableAnnotationComposer,
          $$AiCallLogsTableCreateCompanionBuilder,
          $$AiCallLogsTableUpdateCompanionBuilder,
          (
            AiCallLog,
            BaseReferences<_$AppDatabase, $AiCallLogsTable, AiCallLog>,
          ),
          AiCallLog,
          PrefetchHooks Function()
        > {
  $$AiCallLogsTableTableManager(_$AppDatabase db, $AiCallLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiCallLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiCallLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiCallLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> feature = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int> latencyMs = const Value.absent(),
                Value<bool> success = const Value.absent(),
                Value<bool> timedOut = const Value.absent(),
                Value<int> candidateCount = const Value.absent(),
                Value<int> outputCount = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AiCallLogsCompanion(
                id: id,
                feature: feature,
                model: model,
                latencyMs: latencyMs,
                success: success,
                timedOut: timedOut,
                candidateCount: candidateCount,
                outputCount: outputCount,
                errorCode: errorCode,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String feature,
                required String model,
                required int latencyMs,
                required bool success,
                Value<bool> timedOut = const Value.absent(),
                Value<int> candidateCount = const Value.absent(),
                Value<int> outputCount = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AiCallLogsCompanion.insert(
                id: id,
                feature: feature,
                model: model,
                latencyMs: latencyMs,
                success: success,
                timedOut: timedOut,
                candidateCount: candidateCount,
                outputCount: outputCount,
                errorCode: errorCode,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiCallLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiCallLogsTable,
      AiCallLog,
      $$AiCallLogsTableFilterComposer,
      $$AiCallLogsTableOrderingComposer,
      $$AiCallLogsTableAnnotationComposer,
      $$AiCallLogsTableCreateCompanionBuilder,
      $$AiCallLogsTableUpdateCompanionBuilder,
      (AiCallLog, BaseReferences<_$AppDatabase, $AiCallLogsTable, AiCallLog>),
      AiCallLog,
      PrefetchHooks Function()
    >;
typedef $$AiFeedbackTableCreateCompanionBuilder =
    AiFeedbackCompanion Function({
      required int streamId,
      required String type,
      required String action,
      Value<String?> feature,
      Value<DateTime> createdAt,
      Value<int> profileId,
      Value<int> rowid,
    });
typedef $$AiFeedbackTableUpdateCompanionBuilder =
    AiFeedbackCompanion Function({
      Value<int> streamId,
      Value<String> type,
      Value<String> action,
      Value<String?> feature,
      Value<DateTime> createdAt,
      Value<int> profileId,
      Value<int> rowid,
    });

class $$AiFeedbackTableFilterComposer
    extends Composer<_$AppDatabase, $AiFeedbackTable> {
  $$AiFeedbackTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feature => $composableBuilder(
    column: $table.feature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiFeedbackTableOrderingComposer
    extends Composer<_$AppDatabase, $AiFeedbackTable> {
  $$AiFeedbackTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feature => $composableBuilder(
    column: $table.feature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiFeedbackTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiFeedbackTable> {
  $$AiFeedbackTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get feature =>
      $composableBuilder(column: $table.feature, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);
}

class $$AiFeedbackTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiFeedbackTable,
          AiFeedbackData,
          $$AiFeedbackTableFilterComposer,
          $$AiFeedbackTableOrderingComposer,
          $$AiFeedbackTableAnnotationComposer,
          $$AiFeedbackTableCreateCompanionBuilder,
          $$AiFeedbackTableUpdateCompanionBuilder,
          (
            AiFeedbackData,
            BaseReferences<_$AppDatabase, $AiFeedbackTable, AiFeedbackData>,
          ),
          AiFeedbackData,
          PrefetchHooks Function()
        > {
  $$AiFeedbackTableTableManager(_$AppDatabase db, $AiFeedbackTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiFeedbackTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiFeedbackTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiFeedbackTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> streamId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String?> feature = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiFeedbackCompanion(
                streamId: streamId,
                type: type,
                action: action,
                feature: feature,
                createdAt: createdAt,
                profileId: profileId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int streamId,
                required String type,
                required String action,
                Value<String?> feature = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiFeedbackCompanion.insert(
                streamId: streamId,
                type: type,
                action: action,
                feature: feature,
                createdAt: createdAt,
                profileId: profileId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiFeedbackTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiFeedbackTable,
      AiFeedbackData,
      $$AiFeedbackTableFilterComposer,
      $$AiFeedbackTableOrderingComposer,
      $$AiFeedbackTableAnnotationComposer,
      $$AiFeedbackTableCreateCompanionBuilder,
      $$AiFeedbackTableUpdateCompanionBuilder,
      (
        AiFeedbackData,
        BaseReferences<_$AppDatabase, $AiFeedbackTable, AiFeedbackData>,
      ),
      AiFeedbackData,
      PrefetchHooks Function()
    >;
typedef $$SearchHistoryTableCreateCompanionBuilder =
    SearchHistoryCompanion Function({
      required String query,
      Value<DateTime> lastUsedAt,
      Value<int> useCount,
      Value<int> profileId,
      Value<int> rowid,
    });
typedef $$SearchHistoryTableUpdateCompanionBuilder =
    SearchHistoryCompanion Function({
      Value<String> query,
      Value<DateTime> lastUsedAt,
      Value<int> useCount,
      Value<int> profileId,
      Value<int> rowid,
    });

class $$SearchHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SearchHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SearchHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get query =>
      $composableBuilder(column: $table.query, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get useCount =>
      $composableBuilder(column: $table.useCount, builder: (column) => column);

  GeneratedColumn<int> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);
}

class $$SearchHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SearchHistoryTable,
          SearchHistoryData,
          $$SearchHistoryTableFilterComposer,
          $$SearchHistoryTableOrderingComposer,
          $$SearchHistoryTableAnnotationComposer,
          $$SearchHistoryTableCreateCompanionBuilder,
          $$SearchHistoryTableUpdateCompanionBuilder,
          (
            SearchHistoryData,
            BaseReferences<
              _$AppDatabase,
              $SearchHistoryTable,
              SearchHistoryData
            >,
          ),
          SearchHistoryData,
          PrefetchHooks Function()
        > {
  $$SearchHistoryTableTableManager(_$AppDatabase db, $SearchHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SearchHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SearchHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SearchHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> query = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchHistoryCompanion(
                query: query,
                lastUsedAt: lastUsedAt,
                useCount: useCount,
                profileId: profileId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String query,
                Value<DateTime> lastUsedAt = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<int> profileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchHistoryCompanion.insert(
                query: query,
                lastUsedAt: lastUsedAt,
                useCount: useCount,
                profileId: profileId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SearchHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SearchHistoryTable,
      SearchHistoryData,
      $$SearchHistoryTableFilterComposer,
      $$SearchHistoryTableOrderingComposer,
      $$SearchHistoryTableAnnotationComposer,
      $$SearchHistoryTableCreateCompanionBuilder,
      $$SearchHistoryTableUpdateCompanionBuilder,
      (
        SearchHistoryData,
        BaseReferences<_$AppDatabase, $SearchHistoryTable, SearchHistoryData>,
      ),
      SearchHistoryData,
      PrefetchHooks Function()
    >;
typedef $$AiSimilarCacheTableCreateCompanionBuilder =
    AiSimilarCacheCompanion Function({
      required int streamId,
      required String type,
      required String payloadJson,
      required String sourceHash,
      Value<DateTime> generatedAt,
      Value<int> rowid,
    });
typedef $$AiSimilarCacheTableUpdateCompanionBuilder =
    AiSimilarCacheCompanion Function({
      Value<int> streamId,
      Value<String> type,
      Value<String> payloadJson,
      Value<String> sourceHash,
      Value<DateTime> generatedAt,
      Value<int> rowid,
    });

class $$AiSimilarCacheTableFilterComposer
    extends Composer<_$AppDatabase, $AiSimilarCacheTable> {
  $$AiSimilarCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiSimilarCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $AiSimilarCacheTable> {
  $$AiSimilarCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiSimilarCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiSimilarCacheTable> {
  $$AiSimilarCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => column,
  );
}

class $$AiSimilarCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiSimilarCacheTable,
          AiSimilarCacheData,
          $$AiSimilarCacheTableFilterComposer,
          $$AiSimilarCacheTableOrderingComposer,
          $$AiSimilarCacheTableAnnotationComposer,
          $$AiSimilarCacheTableCreateCompanionBuilder,
          $$AiSimilarCacheTableUpdateCompanionBuilder,
          (
            AiSimilarCacheData,
            BaseReferences<
              _$AppDatabase,
              $AiSimilarCacheTable,
              AiSimilarCacheData
            >,
          ),
          AiSimilarCacheData,
          PrefetchHooks Function()
        > {
  $$AiSimilarCacheTableTableManager(
    _$AppDatabase db,
    $AiSimilarCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiSimilarCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiSimilarCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiSimilarCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> streamId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> sourceHash = const Value.absent(),
                Value<DateTime> generatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiSimilarCacheCompanion(
                streamId: streamId,
                type: type,
                payloadJson: payloadJson,
                sourceHash: sourceHash,
                generatedAt: generatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int streamId,
                required String type,
                required String payloadJson,
                required String sourceHash,
                Value<DateTime> generatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiSimilarCacheCompanion.insert(
                streamId: streamId,
                type: type,
                payloadJson: payloadJson,
                sourceHash: sourceHash,
                generatedAt: generatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiSimilarCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiSimilarCacheTable,
      AiSimilarCacheData,
      $$AiSimilarCacheTableFilterComposer,
      $$AiSimilarCacheTableOrderingComposer,
      $$AiSimilarCacheTableAnnotationComposer,
      $$AiSimilarCacheTableCreateCompanionBuilder,
      $$AiSimilarCacheTableUpdateCompanionBuilder,
      (
        AiSimilarCacheData,
        BaseReferences<_$AppDatabase, $AiSimilarCacheTable, AiSimilarCacheData>,
      ),
      AiSimilarCacheData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db, _db.channels);
  $$ProgramsTableTableManager get programs =>
      $$ProgramsTableTableManager(_db, _db.programs);
  $$PlaybackProgressTableTableManager get playbackProgress =>
      $$PlaybackProgressTableTableManager(_db, _db.playbackProgress);
  $$FavoritesTableTableManager get favorites =>
      $$FavoritesTableTableManager(_db, _db.favorites);
  $$WatchlistTableTableManager get watchlist =>
      $$WatchlistTableTableManager(_db, _db.watchlist);
  $$SeriesTrackingTableTableManager get seriesTracking =>
      $$SeriesTrackingTableTableManager(_db, _db.seriesTracking);
  $$IntroMarkersTableTableManager get introMarkers =>
      $$IntroMarkersTableTableManager(_db, _db.introMarkers);
  $$PlotAiCacheTableTableManager get plotAiCache =>
      $$PlotAiCacheTableTableManager(_db, _db.plotAiCache);
  $$PersonalizedPicksCacheTableTableManager get personalizedPicksCache =>
      $$PersonalizedPicksCacheTableTableManager(
        _db,
        _db.personalizedPicksCache,
      );
  $$AiCallLogsTableTableManager get aiCallLogs =>
      $$AiCallLogsTableTableManager(_db, _db.aiCallLogs);
  $$AiFeedbackTableTableManager get aiFeedback =>
      $$AiFeedbackTableTableManager(_db, _db.aiFeedback);
  $$SearchHistoryTableTableManager get searchHistory =>
      $$SearchHistoryTableTableManager(_db, _db.searchHistory);
  $$AiSimilarCacheTableTableManager get aiSimilarCache =>
      $$AiSimilarCacheTableTableManager(_db, _db.aiSimilarCache);
}

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

final class AppDatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$appDatabaseHash() => r'8c69eb46d45206533c176c88a926608e79ca927d';
