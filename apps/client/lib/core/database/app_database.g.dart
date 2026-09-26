// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ServersTable extends Servers with TableInfo<$ServersTable, Server> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
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
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    name,
    baseUrl,
    createdAt,
    lastUsedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'servers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Server> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastUsedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Server map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Server(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      )!,
    );
  }

  @override
  $ServersTable createAlias(String alias) {
    return $ServersTable(attachedDatabase, alias);
  }
}

class Server extends DataClass implements Insertable<Server> {
  final int id;

  /// The server's own UUID, learned from `GET /api/v1/server/info`.
  final String serverId;
  final String name;
  final String baseUrl;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  const Server({
    required this.id,
    required this.serverId,
    required this.name,
    required this.baseUrl,
    required this.createdAt,
    required this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server_id'] = Variable<String>(serverId);
    map['name'] = Variable<String>(name);
    map['base_url'] = Variable<String>(baseUrl);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    return map;
  }

  ServersCompanion toCompanion(bool nullToAbsent) {
    return ServersCompanion(
      id: Value(id),
      serverId: Value(serverId),
      name: Value(name),
      baseUrl: Value(baseUrl),
      createdAt: Value(createdAt),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory Server.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Server(
      id: serializer.fromJson<int>(json['id']),
      serverId: serializer.fromJson<String>(json['serverId']),
      name: serializer.fromJson<String>(json['name']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastUsedAt: serializer.fromJson<DateTime>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverId': serializer.toJson<String>(serverId),
      'name': serializer.toJson<String>(name),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastUsedAt': serializer.toJson<DateTime>(lastUsedAt),
    };
  }

  Server copyWith({
    int? id,
    String? serverId,
    String? name,
    String? baseUrl,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  }) => Server(
    id: id ?? this.id,
    serverId: serverId ?? this.serverId,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    createdAt: createdAt ?? this.createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
  Server copyWithCompanion(ServersCompanion data) {
    return Server(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      name: data.name.present ? data.name.value : this.name,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Server(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, serverId, name, baseUrl, createdAt, lastUsedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Server &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.name == this.name &&
          other.baseUrl == this.baseUrl &&
          other.createdAt == this.createdAt &&
          other.lastUsedAt == this.lastUsedAt);
}

class ServersCompanion extends UpdateCompanion<Server> {
  final Value<int> id;
  final Value<String> serverId;
  final Value<String> name;
  final Value<String> baseUrl;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastUsedAt;
  const ServersCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.name = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
  });
  ServersCompanion.insert({
    this.id = const Value.absent(),
    required String serverId,
    required String name,
    required String baseUrl,
    required DateTime createdAt,
    required DateTime lastUsedAt,
  }) : serverId = Value(serverId),
       name = Value(name),
       baseUrl = Value(baseUrl),
       createdAt = Value(createdAt),
       lastUsedAt = Value(lastUsedAt);
  static Insertable<Server> custom({
    Expression<int>? id,
    Expression<String>? serverId,
    Expression<String>? name,
    Expression<String>? baseUrl,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastUsedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (name != null) 'name': name,
      if (baseUrl != null) 'base_url': baseUrl,
      if (createdAt != null) 'created_at': createdAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
    });
  }

  ServersCompanion copyWith({
    Value<int>? id,
    Value<String>? serverId,
    Value<String>? name,
    Value<String>? baseUrl,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastUsedAt,
  }) {
    return ServersCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServersCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }
}

class $QuestionsTable extends Questions
    with TableInfo<$QuestionsTable, Question> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QuestionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _serverRefMeta = const VerificationMeta(
    'serverRef',
  );
  @override
  late final GeneratedColumn<int> serverRef = GeneratedColumn<int>(
    'server_ref',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servers (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ocrTextMeta = const VerificationMeta(
    'ocrText',
  );
  @override
  late final GeneratedColumn<String> ocrText = GeneratedColumn<String>(
    'ocr_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questionTextMeta = const VerificationMeta(
    'questionText',
  );
  @override
  late final GeneratedColumn<String> questionText = GeneratedColumn<String>(
    'question_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _optionsJsonMeta = const VerificationMeta(
    'optionsJson',
  );
  @override
  late final GeneratedColumn<String> optionsJson = GeneratedColumn<String>(
    'options_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _answerJsonMeta = const VerificationMeta(
    'answerJson',
  );
  @override
  late final GeneratedColumn<String> answerJson = GeneratedColumn<String>(
    'answer_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
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
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confidenceLevelMeta = const VerificationMeta(
    'confidenceLevel',
  );
  @override
  late final GeneratedColumn<String> confidenceLevel = GeneratedColumn<String>(
    'confidence_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverRef,
    imagePath,
    ocrText,
    questionText,
    optionsJson,
    answerJson,
    provider,
    model,
    confidence,
    confidenceLevel,
    requestId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'questions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Question> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_ref')) {
      context.handle(
        _serverRefMeta,
        serverRef.isAcceptableOrUnknown(data['server_ref']!, _serverRefMeta),
      );
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('ocr_text')) {
      context.handle(
        _ocrTextMeta,
        ocrText.isAcceptableOrUnknown(data['ocr_text']!, _ocrTextMeta),
      );
    } else if (isInserting) {
      context.missing(_ocrTextMeta);
    }
    if (data.containsKey('question_text')) {
      context.handle(
        _questionTextMeta,
        questionText.isAcceptableOrUnknown(
          data['question_text']!,
          _questionTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionTextMeta);
    }
    if (data.containsKey('options_json')) {
      context.handle(
        _optionsJsonMeta,
        optionsJson.isAcceptableOrUnknown(
          data['options_json']!,
          _optionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_optionsJsonMeta);
    }
    if (data.containsKey('answer_json')) {
      context.handle(
        _answerJsonMeta,
        answerJson.isAcceptableOrUnknown(data['answer_json']!, _answerJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_answerJsonMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_confidenceMeta);
    }
    if (data.containsKey('confidence_level')) {
      context.handle(
        _confidenceLevelMeta,
        confidenceLevel.isAcceptableOrUnknown(
          data['confidence_level']!,
          _confidenceLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_confidenceLevelMeta);
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Question map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Question(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      serverRef: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_ref'],
      ),
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      ocrText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_text'],
      )!,
      questionText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_text'],
      )!,
      optionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}options_json'],
      )!,
      answerJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_json'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
      confidenceLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}confidence_level'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $QuestionsTable createAlias(String alias) {
    return $QuestionsTable(attachedDatabase, alias);
  }
}

class Question extends DataClass implements Insertable<Question> {
  final int id;

  /// Entries outlive the server record: removing the server keeps the history.
  final int? serverRef;

  /// Path relative to the app-private image directory, or null.
  final String? imagePath;
  final String ocrText;
  final String questionText;
  final String optionsJson;
  final String answerJson;
  final String provider;
  final String model;
  final double confidence;
  final String confidenceLevel;
  final String? requestId;
  final DateTime createdAt;
  const Question({
    required this.id,
    this.serverRef,
    this.imagePath,
    required this.ocrText,
    required this.questionText,
    required this.optionsJson,
    required this.answerJson,
    required this.provider,
    required this.model,
    required this.confidence,
    required this.confidenceLevel,
    this.requestId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || serverRef != null) {
      map['server_ref'] = Variable<int>(serverRef);
    }
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    map['ocr_text'] = Variable<String>(ocrText);
    map['question_text'] = Variable<String>(questionText);
    map['options_json'] = Variable<String>(optionsJson);
    map['answer_json'] = Variable<String>(answerJson);
    map['provider'] = Variable<String>(provider);
    map['model'] = Variable<String>(model);
    map['confidence'] = Variable<double>(confidence);
    map['confidence_level'] = Variable<String>(confidenceLevel);
    if (!nullToAbsent || requestId != null) {
      map['request_id'] = Variable<String>(requestId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  QuestionsCompanion toCompanion(bool nullToAbsent) {
    return QuestionsCompanion(
      id: Value(id),
      serverRef: serverRef == null && nullToAbsent
          ? const Value.absent()
          : Value(serverRef),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      ocrText: Value(ocrText),
      questionText: Value(questionText),
      optionsJson: Value(optionsJson),
      answerJson: Value(answerJson),
      provider: Value(provider),
      model: Value(model),
      confidence: Value(confidence),
      confidenceLevel: Value(confidenceLevel),
      requestId: requestId == null && nullToAbsent
          ? const Value.absent()
          : Value(requestId),
      createdAt: Value(createdAt),
    );
  }

  factory Question.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Question(
      id: serializer.fromJson<int>(json['id']),
      serverRef: serializer.fromJson<int?>(json['serverRef']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      ocrText: serializer.fromJson<String>(json['ocrText']),
      questionText: serializer.fromJson<String>(json['questionText']),
      optionsJson: serializer.fromJson<String>(json['optionsJson']),
      answerJson: serializer.fromJson<String>(json['answerJson']),
      provider: serializer.fromJson<String>(json['provider']),
      model: serializer.fromJson<String>(json['model']),
      confidence: serializer.fromJson<double>(json['confidence']),
      confidenceLevel: serializer.fromJson<String>(json['confidenceLevel']),
      requestId: serializer.fromJson<String?>(json['requestId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverRef': serializer.toJson<int?>(serverRef),
      'imagePath': serializer.toJson<String?>(imagePath),
      'ocrText': serializer.toJson<String>(ocrText),
      'questionText': serializer.toJson<String>(questionText),
      'optionsJson': serializer.toJson<String>(optionsJson),
      'answerJson': serializer.toJson<String>(answerJson),
      'provider': serializer.toJson<String>(provider),
      'model': serializer.toJson<String>(model),
      'confidence': serializer.toJson<double>(confidence),
      'confidenceLevel': serializer.toJson<String>(confidenceLevel),
      'requestId': serializer.toJson<String?>(requestId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Question copyWith({
    int? id,
    Value<int?> serverRef = const Value.absent(),
    Value<String?> imagePath = const Value.absent(),
    String? ocrText,
    String? questionText,
    String? optionsJson,
    String? answerJson,
    String? provider,
    String? model,
    double? confidence,
    String? confidenceLevel,
    Value<String?> requestId = const Value.absent(),
    DateTime? createdAt,
  }) => Question(
    id: id ?? this.id,
    serverRef: serverRef.present ? serverRef.value : this.serverRef,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    ocrText: ocrText ?? this.ocrText,
    questionText: questionText ?? this.questionText,
    optionsJson: optionsJson ?? this.optionsJson,
    answerJson: answerJson ?? this.answerJson,
    provider: provider ?? this.provider,
    model: model ?? this.model,
    confidence: confidence ?? this.confidence,
    confidenceLevel: confidenceLevel ?? this.confidenceLevel,
    requestId: requestId.present ? requestId.value : this.requestId,
    createdAt: createdAt ?? this.createdAt,
  );
  Question copyWithCompanion(QuestionsCompanion data) {
    return Question(
      id: data.id.present ? data.id.value : this.id,
      serverRef: data.serverRef.present ? data.serverRef.value : this.serverRef,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      ocrText: data.ocrText.present ? data.ocrText.value : this.ocrText,
      questionText: data.questionText.present
          ? data.questionText.value
          : this.questionText,
      optionsJson: data.optionsJson.present
          ? data.optionsJson.value
          : this.optionsJson,
      answerJson: data.answerJson.present
          ? data.answerJson.value
          : this.answerJson,
      provider: data.provider.present ? data.provider.value : this.provider,
      model: data.model.present ? data.model.value : this.model,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      confidenceLevel: data.confidenceLevel.present
          ? data.confidenceLevel.value
          : this.confidenceLevel,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Question(')
          ..write('id: $id, ')
          ..write('serverRef: $serverRef, ')
          ..write('imagePath: $imagePath, ')
          ..write('ocrText: $ocrText, ')
          ..write('questionText: $questionText, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('answerJson: $answerJson, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('confidence: $confidence, ')
          ..write('confidenceLevel: $confidenceLevel, ')
          ..write('requestId: $requestId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverRef,
    imagePath,
    ocrText,
    questionText,
    optionsJson,
    answerJson,
    provider,
    model,
    confidence,
    confidenceLevel,
    requestId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Question &&
          other.id == this.id &&
          other.serverRef == this.serverRef &&
          other.imagePath == this.imagePath &&
          other.ocrText == this.ocrText &&
          other.questionText == this.questionText &&
          other.optionsJson == this.optionsJson &&
          other.answerJson == this.answerJson &&
          other.provider == this.provider &&
          other.model == this.model &&
          other.confidence == this.confidence &&
          other.confidenceLevel == this.confidenceLevel &&
          other.requestId == this.requestId &&
          other.createdAt == this.createdAt);
}

class QuestionsCompanion extends UpdateCompanion<Question> {
  final Value<int> id;
  final Value<int?> serverRef;
  final Value<String?> imagePath;
  final Value<String> ocrText;
  final Value<String> questionText;
  final Value<String> optionsJson;
  final Value<String> answerJson;
  final Value<String> provider;
  final Value<String> model;
  final Value<double> confidence;
  final Value<String> confidenceLevel;
  final Value<String?> requestId;
  final Value<DateTime> createdAt;
  const QuestionsCompanion({
    this.id = const Value.absent(),
    this.serverRef = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.ocrText = const Value.absent(),
    this.questionText = const Value.absent(),
    this.optionsJson = const Value.absent(),
    this.answerJson = const Value.absent(),
    this.provider = const Value.absent(),
    this.model = const Value.absent(),
    this.confidence = const Value.absent(),
    this.confidenceLevel = const Value.absent(),
    this.requestId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  QuestionsCompanion.insert({
    this.id = const Value.absent(),
    this.serverRef = const Value.absent(),
    this.imagePath = const Value.absent(),
    required String ocrText,
    required String questionText,
    required String optionsJson,
    required String answerJson,
    required String provider,
    required String model,
    required double confidence,
    required String confidenceLevel,
    this.requestId = const Value.absent(),
    required DateTime createdAt,
  }) : ocrText = Value(ocrText),
       questionText = Value(questionText),
       optionsJson = Value(optionsJson),
       answerJson = Value(answerJson),
       provider = Value(provider),
       model = Value(model),
       confidence = Value(confidence),
       confidenceLevel = Value(confidenceLevel),
       createdAt = Value(createdAt);
  static Insertable<Question> custom({
    Expression<int>? id,
    Expression<int>? serverRef,
    Expression<String>? imagePath,
    Expression<String>? ocrText,
    Expression<String>? questionText,
    Expression<String>? optionsJson,
    Expression<String>? answerJson,
    Expression<String>? provider,
    Expression<String>? model,
    Expression<double>? confidence,
    Expression<String>? confidenceLevel,
    Expression<String>? requestId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverRef != null) 'server_ref': serverRef,
      if (imagePath != null) 'image_path': imagePath,
      if (ocrText != null) 'ocr_text': ocrText,
      if (questionText != null) 'question_text': questionText,
      if (optionsJson != null) 'options_json': optionsJson,
      if (answerJson != null) 'answer_json': answerJson,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (confidence != null) 'confidence': confidence,
      if (confidenceLevel != null) 'confidence_level': confidenceLevel,
      if (requestId != null) 'request_id': requestId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  QuestionsCompanion copyWith({
    Value<int>? id,
    Value<int?>? serverRef,
    Value<String?>? imagePath,
    Value<String>? ocrText,
    Value<String>? questionText,
    Value<String>? optionsJson,
    Value<String>? answerJson,
    Value<String>? provider,
    Value<String>? model,
    Value<double>? confidence,
    Value<String>? confidenceLevel,
    Value<String?>? requestId,
    Value<DateTime>? createdAt,
  }) {
    return QuestionsCompanion(
      id: id ?? this.id,
      serverRef: serverRef ?? this.serverRef,
      imagePath: imagePath ?? this.imagePath,
      ocrText: ocrText ?? this.ocrText,
      questionText: questionText ?? this.questionText,
      optionsJson: optionsJson ?? this.optionsJson,
      answerJson: answerJson ?? this.answerJson,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      confidence: confidence ?? this.confidence,
      confidenceLevel: confidenceLevel ?? this.confidenceLevel,
      requestId: requestId ?? this.requestId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverRef.present) {
      map['server_ref'] = Variable<int>(serverRef.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (ocrText.present) {
      map['ocr_text'] = Variable<String>(ocrText.value);
    }
    if (questionText.present) {
      map['question_text'] = Variable<String>(questionText.value);
    }
    if (optionsJson.present) {
      map['options_json'] = Variable<String>(optionsJson.value);
    }
    if (answerJson.present) {
      map['answer_json'] = Variable<String>(answerJson.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (confidenceLevel.present) {
      map['confidence_level'] = Variable<String>(confidenceLevel.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QuestionsCompanion(')
          ..write('id: $id, ')
          ..write('serverRef: $serverRef, ')
          ..write('imagePath: $imagePath, ')
          ..write('ocrText: $ocrText, ')
          ..write('questionText: $questionText, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('answerJson: $answerJson, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('confidence: $confidence, ')
          ..write('confidenceLevel: $confidenceLevel, ')
          ..write('requestId: $requestId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DraftsTable extends Drafts with TableInfo<$DraftsTable, Draft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    check: () => id.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ocrTextMeta = const VerificationMeta(
    'ocrText',
  );
  @override
  late final GeneratedColumn<String> ocrText = GeneratedColumn<String>(
    'ocr_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questionTextMeta = const VerificationMeta(
    'questionText',
  );
  @override
  late final GeneratedColumn<String> questionText = GeneratedColumn<String>(
    'question_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _optionsJsonMeta = const VerificationMeta(
    'optionsJson',
  );
  @override
  late final GeneratedColumn<String> optionsJson = GeneratedColumn<String>(
    'options_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sendImageMeta = const VerificationMeta(
    'sendImage',
  );
  @override
  late final GeneratedColumn<bool> sendImage = GeneratedColumn<bool>(
    'send_image',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("send_image" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    imagePath,
    ocrText,
    questionText,
    optionsJson,
    sendImage,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Draft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('ocr_text')) {
      context.handle(
        _ocrTextMeta,
        ocrText.isAcceptableOrUnknown(data['ocr_text']!, _ocrTextMeta),
      );
    } else if (isInserting) {
      context.missing(_ocrTextMeta);
    }
    if (data.containsKey('question_text')) {
      context.handle(
        _questionTextMeta,
        questionText.isAcceptableOrUnknown(
          data['question_text']!,
          _questionTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionTextMeta);
    }
    if (data.containsKey('options_json')) {
      context.handle(
        _optionsJsonMeta,
        optionsJson.isAcceptableOrUnknown(
          data['options_json']!,
          _optionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_optionsJsonMeta);
    }
    if (data.containsKey('send_image')) {
      context.handle(
        _sendImageMeta,
        sendImage.isAcceptableOrUnknown(data['send_image']!, _sendImageMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Draft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Draft(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      ocrText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_text'],
      )!,
      questionText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_text'],
      )!,
      optionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}options_json'],
      )!,
      sendImage: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}send_image'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DraftsTable createAlias(String alias) {
    return $DraftsTable(attachedDatabase, alias);
  }
}

class Draft extends DataClass implements Insertable<Draft> {
  final int id;
  final String? imagePath;
  final String ocrText;
  final String questionText;
  final String optionsJson;
  final bool sendImage;
  final DateTime updatedAt;
  const Draft({
    required this.id,
    this.imagePath,
    required this.ocrText,
    required this.questionText,
    required this.optionsJson,
    required this.sendImage,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    map['ocr_text'] = Variable<String>(ocrText);
    map['question_text'] = Variable<String>(questionText);
    map['options_json'] = Variable<String>(optionsJson);
    map['send_image'] = Variable<bool>(sendImage);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DraftsCompanion toCompanion(bool nullToAbsent) {
    return DraftsCompanion(
      id: Value(id),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      ocrText: Value(ocrText),
      questionText: Value(questionText),
      optionsJson: Value(optionsJson),
      sendImage: Value(sendImage),
      updatedAt: Value(updatedAt),
    );
  }

  factory Draft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Draft(
      id: serializer.fromJson<int>(json['id']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      ocrText: serializer.fromJson<String>(json['ocrText']),
      questionText: serializer.fromJson<String>(json['questionText']),
      optionsJson: serializer.fromJson<String>(json['optionsJson']),
      sendImage: serializer.fromJson<bool>(json['sendImage']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'imagePath': serializer.toJson<String?>(imagePath),
      'ocrText': serializer.toJson<String>(ocrText),
      'questionText': serializer.toJson<String>(questionText),
      'optionsJson': serializer.toJson<String>(optionsJson),
      'sendImage': serializer.toJson<bool>(sendImage),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Draft copyWith({
    int? id,
    Value<String?> imagePath = const Value.absent(),
    String? ocrText,
    String? questionText,
    String? optionsJson,
    bool? sendImage,
    DateTime? updatedAt,
  }) => Draft(
    id: id ?? this.id,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    ocrText: ocrText ?? this.ocrText,
    questionText: questionText ?? this.questionText,
    optionsJson: optionsJson ?? this.optionsJson,
    sendImage: sendImage ?? this.sendImage,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Draft copyWithCompanion(DraftsCompanion data) {
    return Draft(
      id: data.id.present ? data.id.value : this.id,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      ocrText: data.ocrText.present ? data.ocrText.value : this.ocrText,
      questionText: data.questionText.present
          ? data.questionText.value
          : this.questionText,
      optionsJson: data.optionsJson.present
          ? data.optionsJson.value
          : this.optionsJson,
      sendImage: data.sendImage.present ? data.sendImage.value : this.sendImage,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Draft(')
          ..write('id: $id, ')
          ..write('imagePath: $imagePath, ')
          ..write('ocrText: $ocrText, ')
          ..write('questionText: $questionText, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('sendImage: $sendImage, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    imagePath,
    ocrText,
    questionText,
    optionsJson,
    sendImage,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Draft &&
          other.id == this.id &&
          other.imagePath == this.imagePath &&
          other.ocrText == this.ocrText &&
          other.questionText == this.questionText &&
          other.optionsJson == this.optionsJson &&
          other.sendImage == this.sendImage &&
          other.updatedAt == this.updatedAt);
}

class DraftsCompanion extends UpdateCompanion<Draft> {
  final Value<int> id;
  final Value<String?> imagePath;
  final Value<String> ocrText;
  final Value<String> questionText;
  final Value<String> optionsJson;
  final Value<bool> sendImage;
  final Value<DateTime> updatedAt;
  const DraftsCompanion({
    this.id = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.ocrText = const Value.absent(),
    this.questionText = const Value.absent(),
    this.optionsJson = const Value.absent(),
    this.sendImage = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DraftsCompanion.insert({
    this.id = const Value.absent(),
    this.imagePath = const Value.absent(),
    required String ocrText,
    required String questionText,
    required String optionsJson,
    this.sendImage = const Value.absent(),
    required DateTime updatedAt,
  }) : ocrText = Value(ocrText),
       questionText = Value(questionText),
       optionsJson = Value(optionsJson),
       updatedAt = Value(updatedAt);
  static Insertable<Draft> custom({
    Expression<int>? id,
    Expression<String>? imagePath,
    Expression<String>? ocrText,
    Expression<String>? questionText,
    Expression<String>? optionsJson,
    Expression<bool>? sendImage,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (imagePath != null) 'image_path': imagePath,
      if (ocrText != null) 'ocr_text': ocrText,
      if (questionText != null) 'question_text': questionText,
      if (optionsJson != null) 'options_json': optionsJson,
      if (sendImage != null) 'send_image': sendImage,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DraftsCompanion copyWith({
    Value<int>? id,
    Value<String?>? imagePath,
    Value<String>? ocrText,
    Value<String>? questionText,
    Value<String>? optionsJson,
    Value<bool>? sendImage,
    Value<DateTime>? updatedAt,
  }) {
    return DraftsCompanion(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      ocrText: ocrText ?? this.ocrText,
      questionText: questionText ?? this.questionText,
      optionsJson: optionsJson ?? this.optionsJson,
      sendImage: sendImage ?? this.sendImage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (ocrText.present) {
      map['ocr_text'] = Variable<String>(ocrText.value);
    }
    if (questionText.present) {
      map['question_text'] = Variable<String>(questionText.value);
    }
    if (optionsJson.present) {
      map['options_json'] = Variable<String>(optionsJson.value);
    }
    if (sendImage.present) {
      map['send_image'] = Variable<bool>(sendImage.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DraftsCompanion(')
          ..write('id: $id, ')
          ..write('imagePath: $imagePath, ')
          ..write('ocrText: $ocrText, ')
          ..write('questionText: $questionText, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('sendImage: $sendImage, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ServersTable servers = $ServersTable(this);
  late final $QuestionsTable questions = $QuestionsTable(this);
  late final $DraftsTable drafts = $DraftsTable(this);
  late final Index questionsCreatedAt = Index(
    'questions_created_at',
    'CREATE INDEX questions_created_at ON questions (created_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    servers,
    questions,
    drafts,
    questionsCreatedAt,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'servers',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('questions', kind: UpdateKind.update)],
    ),
  ]);
}

typedef $$ServersTableCreateCompanionBuilder = ServersCompanion Function({
  Value<int> id,
  required String serverId,
  required String name,
  required String baseUrl,
  required DateTime createdAt,
  required DateTime lastUsedAt,
});
typedef $$ServersTableUpdateCompanionBuilder = ServersCompanion Function({
  Value<int> id,
  Value<String> serverId,
  Value<String> name,
  Value<String> baseUrl,
  Value<DateTime> createdAt,
  Value<DateTime> lastUsedAt,
});

final class $$ServersTableReferences
    extends BaseReferences<_$AppDatabase, $ServersTable, Server> {
  $$ServersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$QuestionsTable, List<Question>>
  _questionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.questions,
    aliasName: 'servers__id__questions__server_ref',
  );

  $$QuestionsTableProcessedTableManager get questionsRefs {
    final manager = $$QuestionsTableTableManager(
      $_db,
      $_db.questions,
    ).filter((f) => f.serverRef.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_questionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ServersTableFilterComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableFilterComposer({
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

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> questionsRefs(
    Expression<bool> Function($$QuestionsTableFilterComposer f) f,
  ) {
    final $$QuestionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.questions,
      getReferencedColumn: (t) => t.serverRef,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$QuestionsTableFilterComposer(
            $db: $db,
            $table: $db.questions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ServersTableOrderingComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableOrderingComposer({
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

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );

  Expression<T> questionsRefs<T extends Object>(
    Expression<T> Function($$QuestionsTableAnnotationComposer a) f,
  ) {
    final $$QuestionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.questions,
      getReferencedColumn: (t) => t.serverRef,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$QuestionsTableAnnotationComposer(
            $db: $db,
            $table: $db.questions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ServersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ServersTable,
          Server,
          $$ServersTableFilterComposer,
          $$ServersTableOrderingComposer,
          $$ServersTableAnnotationComposer,
          $$ServersTableCreateCompanionBuilder,
          $$ServersTableUpdateCompanionBuilder,
          (Server, $$ServersTableReferences),
          Server,
          PrefetchHooks Function({bool questionsRefs})
        > {
  $$ServersTableTableManager(_$AppDatabase db, $ServersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> serverId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
              }) => ServersCompanion(
                id: id,
                serverId: serverId,
                name: name,
                baseUrl: baseUrl,
                createdAt: createdAt,
                lastUsedAt: lastUsedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String serverId,
                required String name,
                required String baseUrl,
                required DateTime createdAt,
                required DateTime lastUsedAt,
              }) => ServersCompanion.insert(
                id: id,
                serverId: serverId,
                name: name,
                baseUrl: baseUrl,
                createdAt: createdAt,
                lastUsedAt: lastUsedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ServersTable, Server>(table),
                  $$ServersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({questionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (questionsRefs) db.questions],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (questionsRefs)
                    await $_getPrefetchedData<Server, $ServersTable, Question>(
                      currentTable: table,
                      referencedTable: $$ServersTableReferences
                          ._questionsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ServersTableReferences(db, table, p0).questionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.serverRef == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ServersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ServersTable,
      Server,
      $$ServersTableFilterComposer,
      $$ServersTableOrderingComposer,
      $$ServersTableAnnotationComposer,
      $$ServersTableCreateCompanionBuilder,
      $$ServersTableUpdateCompanionBuilder,
      (Server, $$ServersTableReferences),
      Server,
      PrefetchHooks Function({bool questionsRefs})
    >;
typedef $$QuestionsTableCreateCompanionBuilder = QuestionsCompanion Function({
  Value<int> id,
  Value<int?> serverRef,
  Value<String?> imagePath,
  required String ocrText,
  required String questionText,
  required String optionsJson,
  required String answerJson,
  required String provider,
  required String model,
  required double confidence,
  required String confidenceLevel,
  Value<String?> requestId,
  required DateTime createdAt,
});
typedef $$QuestionsTableUpdateCompanionBuilder = QuestionsCompanion Function({
  Value<int> id,
  Value<int?> serverRef,
  Value<String?> imagePath,
  Value<String> ocrText,
  Value<String> questionText,
  Value<String> optionsJson,
  Value<String> answerJson,
  Value<String> provider,
  Value<String> model,
  Value<double> confidence,
  Value<String> confidenceLevel,
  Value<String?> requestId,
  Value<DateTime> createdAt,
});

final class $$QuestionsTableReferences
    extends BaseReferences<_$AppDatabase, $QuestionsTable, Question> {
  $$QuestionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ServersTable _serverRefTable(_$AppDatabase db) =>
      db.servers.createAlias('questions__server_ref__servers__id');

  $$ServersTableProcessedTableManager? get serverRef {
    final $_column = $_itemColumn<int>('server_ref');
    if ($_column == null) return null;
    final manager = $$ServersTableTableManager(
      $_db,
      $_db.servers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_serverRefTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$QuestionsTableFilterComposer
    extends Composer<_$AppDatabase, $QuestionsTable> {
  $$QuestionsTableFilterComposer({
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

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionText => $composableBuilder(
    column: $table.questionText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get answerJson => $composableBuilder(
    column: $table.answerJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get confidenceLevel => $composableBuilder(
    column: $table.confidenceLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ServersTableFilterComposer get serverRef {
    final $$ServersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.serverRef,
      referencedTable: $db.servers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServersTableFilterComposer(
            $db: $db,
            $table: $db.servers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QuestionsTableOrderingComposer
    extends Composer<_$AppDatabase, $QuestionsTable> {
  $$QuestionsTableOrderingComposer({
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

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionText => $composableBuilder(
    column: $table.questionText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get answerJson => $composableBuilder(
    column: $table.answerJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get confidenceLevel => $composableBuilder(
    column: $table.confidenceLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ServersTableOrderingComposer get serverRef {
    final $$ServersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.serverRef,
      referencedTable: $db.servers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServersTableOrderingComposer(
            $db: $db,
            $table: $db.servers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QuestionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $QuestionsTable> {
  $$QuestionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get ocrText =>
      $composableBuilder(column: $table.ocrText, builder: (column) => column);

  GeneratedColumn<String> get questionText => $composableBuilder(
    column: $table.questionText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get answerJson => $composableBuilder(
    column: $table.answerJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get confidenceLevel => $composableBuilder(
    column: $table.confidenceLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ServersTableAnnotationComposer get serverRef {
    final $$ServersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.serverRef,
      referencedTable: $db.servers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServersTableAnnotationComposer(
            $db: $db,
            $table: $db.servers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QuestionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QuestionsTable,
          Question,
          $$QuestionsTableFilterComposer,
          $$QuestionsTableOrderingComposer,
          $$QuestionsTableAnnotationComposer,
          $$QuestionsTableCreateCompanionBuilder,
          $$QuestionsTableUpdateCompanionBuilder,
          (Question, $$QuestionsTableReferences),
          Question,
          PrefetchHooks Function({bool serverRef})
        > {
  $$QuestionsTableTableManager(_$AppDatabase db, $QuestionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QuestionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QuestionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QuestionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> serverRef = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String> ocrText = const Value.absent(),
                Value<String> questionText = const Value.absent(),
                Value<String> optionsJson = const Value.absent(),
                Value<String> answerJson = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<String> confidenceLevel = const Value.absent(),
                Value<String?> requestId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => QuestionsCompanion(
                id: id,
                serverRef: serverRef,
                imagePath: imagePath,
                ocrText: ocrText,
                questionText: questionText,
                optionsJson: optionsJson,
                answerJson: answerJson,
                provider: provider,
                model: model,
                confidence: confidence,
                confidenceLevel: confidenceLevel,
                requestId: requestId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> serverRef = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                required String ocrText,
                required String questionText,
                required String optionsJson,
                required String answerJson,
                required String provider,
                required String model,
                required double confidence,
                required String confidenceLevel,
                Value<String?> requestId = const Value.absent(),
                required DateTime createdAt,
              }) => QuestionsCompanion.insert(
                id: id,
                serverRef: serverRef,
                imagePath: imagePath,
                ocrText: ocrText,
                questionText: questionText,
                optionsJson: optionsJson,
                answerJson: answerJson,
                provider: provider,
                model: model,
                confidence: confidence,
                confidenceLevel: confidenceLevel,
                requestId: requestId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QuestionsTable, Question>(table),
                  $$QuestionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({serverRef = false}) {
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
                    if (serverRef) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.serverRef,
                        referencedTable: $$QuestionsTableReferences
                            ._serverRefTable(db),
                        referencedColumn: $$QuestionsTableReferences
                            ._serverRefTable(db)
                            .id,
                      ) as T;
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

typedef $$QuestionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QuestionsTable,
      Question,
      $$QuestionsTableFilterComposer,
      $$QuestionsTableOrderingComposer,
      $$QuestionsTableAnnotationComposer,
      $$QuestionsTableCreateCompanionBuilder,
      $$QuestionsTableUpdateCompanionBuilder,
      (Question, $$QuestionsTableReferences),
      Question,
      PrefetchHooks Function({bool serverRef})
    >;
typedef $$DraftsTableCreateCompanionBuilder = DraftsCompanion Function({
  Value<int> id,
  Value<String?> imagePath,
  required String ocrText,
  required String questionText,
  required String optionsJson,
  Value<bool> sendImage,
  required DateTime updatedAt,
});
typedef $$DraftsTableUpdateCompanionBuilder = DraftsCompanion Function({
  Value<int> id,
  Value<String?> imagePath,
  Value<String> ocrText,
  Value<String> questionText,
  Value<String> optionsJson,
  Value<bool> sendImage,
  Value<DateTime> updatedAt,
});

class $$DraftsTableFilterComposer
    extends Composer<_$AppDatabase, $DraftsTable> {
  $$DraftsTableFilterComposer({
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

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionText => $composableBuilder(
    column: $table.questionText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sendImage => $composableBuilder(
    column: $table.sendImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DraftsTableOrderingComposer
    extends Composer<_$AppDatabase, $DraftsTable> {
  $$DraftsTableOrderingComposer({
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

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionText => $composableBuilder(
    column: $table.questionText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sendImage => $composableBuilder(
    column: $table.sendImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DraftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DraftsTable> {
  $$DraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get ocrText =>
      $composableBuilder(column: $table.ocrText, builder: (column) => column);

  GeneratedColumn<String> get questionText => $composableBuilder(
    column: $table.questionText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get sendImage =>
      $composableBuilder(column: $table.sendImage, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DraftsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DraftsTable,
          Draft,
          $$DraftsTableFilterComposer,
          $$DraftsTableOrderingComposer,
          $$DraftsTableAnnotationComposer,
          $$DraftsTableCreateCompanionBuilder,
          $$DraftsTableUpdateCompanionBuilder,
          (Draft, BaseReferences<_$AppDatabase, $DraftsTable, Draft>),
          Draft,
          PrefetchHooks Function()
        > {
  $$DraftsTableTableManager(_$AppDatabase db, $DraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String> ocrText = const Value.absent(),
                Value<String> questionText = const Value.absent(),
                Value<String> optionsJson = const Value.absent(),
                Value<bool> sendImage = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DraftsCompanion(
                id: id,
                imagePath: imagePath,
                ocrText: ocrText,
                questionText: questionText,
                optionsJson: optionsJson,
                sendImage: sendImage,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                required String ocrText,
                required String questionText,
                required String optionsJson,
                Value<bool> sendImage = const Value.absent(),
                required DateTime updatedAt,
              }) => DraftsCompanion.insert(
                id: id,
                imagePath: imagePath,
                ocrText: ocrText,
                questionText: questionText,
                optionsJson: optionsJson,
                sendImage: sendImage,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DraftsTable, Draft>(table),
                  BaseReferences<_$AppDatabase, $DraftsTable, Draft>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DraftsTable,
      Draft,
      $$DraftsTableFilterComposer,
      $$DraftsTableOrderingComposer,
      $$DraftsTableAnnotationComposer,
      $$DraftsTableCreateCompanionBuilder,
      $$DraftsTableUpdateCompanionBuilder,
      (Draft, BaseReferences<_$AppDatabase, $DraftsTable, Draft>),
      Draft,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ServersTableTableManager get servers =>
      $$ServersTableTableManager(_db, _db.servers);
  $$QuestionsTableTableManager get questions =>
      $$QuestionsTableTableManager(_db, _db.questions);
  $$DraftsTableTableManager get drafts =>
      $$DraftsTableTableManager(_db, _db.drafts);
}
