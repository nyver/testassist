import 'dart:async';

import 'package:dio/dio.dart';
import 'package:test_assistant/core/errors/app_failure.dart';
import 'package:test_assistant/core/security/certificate_probe.dart';
import 'package:test_assistant/core/security/secret_storage.dart';
import 'package:test_assistant/features/history/domain/history_entry.dart';
import 'package:test_assistant/features/questions/domain/draft_repository.dart';
import 'package:test_assistant/features/questions/domain/models.dart';
import 'package:test_assistant/features/questions/domain/questions_api.dart';
import 'package:test_assistant/features/servers/domain/server_info_api.dart';
import 'package:test_assistant/features/servers/domain/server_record.dart';

/// In-memory [SecretStorage] for tests.
class InMemorySecretStorage implements SecretStorage {
  final Map<String, String> values = {};

  /// Makes every write throw, like a broken keystore.
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('keystore unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A probe with a scripted result.
class FakeCertificateProbe implements CertificateProbe {
  FakeCertificateProbe(this.result);

  /// A [ProbeResult], or an [AppFailure] or [Error] to throw.
  Object result;
  final List<Uri> probed = [];

  @override
  Future<ProbeResult> probe(Uri url) async {
    probed.add(url);
    final r = result;
    if (r is AppFailure) throw r;
    if (r is Error) throw r;
    return r as ProbeResult;
  }
}

/// A server-info client with a scripted answer.
class FakeServerInfoApi implements ServerInfoApi {
  FakeServerInfoApi({required this.info});

  ServerInfo info;
  AppFailure? failure;
  int calls = 0;

  @override
  Future<ServerInfo> fetch() async {
    calls++;
    final f = failure;
    if (f != null) throw f;
    return info;
  }
}

class InMemoryServerRepository implements ServerRepository {
  final _controller = StreamController<ServerRecord?>.broadcast();
  ServerRecord? _record;
  var _nextId = 1;

  @override
  Future<ServerRecord?> current() async => _record;

  @override
  Stream<ServerRecord?> watchCurrent() => _controller.stream;

  @override
  Future<ServerRecord> add({
    required String serverId,
    required String name,
    required Uri baseUrl,
  }) async {
    final now = DateTime.utc(2026, 1, 1);
    final record = ServerRecord(
      id: _nextId++,
      serverId: serverId,
      name: name,
      baseUrl: baseUrl,
      createdAt: now,
      lastUsedAt: now,
    );
    _record = record;
    _controller.add(record);
    return record;
  }

  @override
  Future<void> rename(int id, String name) async {
    final r = _record;
    if (r == null || r.id != id) return;
    _record = ServerRecord(
      id: r.id,
      serverId: r.serverId,
      name: name,
      baseUrl: r.baseUrl,
      createdAt: r.createdAt,
      lastUsedAt: r.lastUsedAt,
    );
  }

  @override
  Future<void> touch(int id) async {}

  @override
  Future<void> remove(int id) async {
    if (_record?.id == id) _record = null;
    _controller.add(null);
  }
}

class InMemoryHistoryRepository implements HistoryRepository {
  final List<HistoryEntry> _entries = [];
  final _controller = StreamController<List<HistoryEntry>>.broadcast();
  var _nextId = 1;
  var _clock = DateTime.utc(2026, 1, 1);

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  List<HistoryEntry> get _newestFirst =>
      [..._entries]..sort((a, b) => b.id.compareTo(a.id));

  @override
  Future<HistoryEntry> insert(NewHistoryEntry entry) async {
    _clock = _clock.add(const Duration(minutes: 1));
    final saved = HistoryEntry(
      id: _nextId++,
      createdAt: _clock,
      imagePath: entry.imagePath,
      ocrText: entry.ocrText,
      questionText: entry.questionText,
      options: entry.options,
      result: entry.result,
      serverRef: entry.serverRef,
    );
    _entries.add(saved);
    _controller.add(_newestFirst);
    return saved;
  }

  @override
  Stream<List<HistoryEntry>> watchAll() async* {
    yield _newestFirst;
    yield* _controller.stream;
  }

  @override
  Future<List<HistoryEntry>> list() async => _newestFirst;

  @override
  Future<HistoryEntry?> get(int id) async {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Future<void> delete(int id) async {
    _entries.removeWhere((e) => e.id == id);
    _controller.add(_newestFirst);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
    _controller.add(_newestFirst);
  }
}

class InMemoryDraftRepository implements DraftRepository {
  QuestionDraft? draft;
  int saves = 0;

  @override
  Future<QuestionDraft?> load() async => draft;

  @override
  Future<void> save(QuestionDraft value) async {
    saves++;
    draft = value;
  }

  @override
  Future<void> clear() async => draft = null;
}

/// A questions API that records requests and answers from a script.
class FakeQuestionsApi implements QuestionsApi {
  FakeQuestionsApi({
    List<ProviderInfo>? providers,
    Map<String, List<ModelInfo>>? models,
  }) : providerList =
           providers ??
           const [
             ProviderInfo(
               id: 'openrouter',
               name: 'OpenRouter',
               isDefault: true,
             ),
             ProviderInfo(id: 'routerai', name: 'RouterAI', isDefault: false),
           ],
       modelMap =
           models ??
           const {
             'openrouter': [
               ModelInfo(
                 id: 'vision-model',
                 name: 'Vision model',
                 supportsText: true,
                 supportsVision: true,
                 isDefault: true,
               ),
               ModelInfo(
                 id: 'text-model',
                 name: 'Text model',
                 supportsText: true,
                 supportsVision: false,
                 isDefault: false,
               ),
             ],
             'routerai': [
               ModelInfo(
                 id: 'router-model',
                 name: 'Router model',
                 supportsText: true,
                 supportsVision: false,
                 isDefault: true,
               ),
             ],
           };

  final List<ProviderInfo> providerList;
  final Map<String, List<ModelInfo>> modelMap;

  /// Every analyze request, in order.
  final List<AnalyzeRequest> requests = [];

  /// Produces the answer, or throws an [AppFailure]. May be replaced per test.
  FutureOr<AnalysisResult> Function(AnalyzeRequest request, CancelToken? token)
  onAnalyze = (request, token) => AnalysisResult(
    status: AnswerStatus.answered,
    correctOptionIds: const ['B'],
    answerText: 'HTTPS',
    explanation: 'Because TLS.',
    details: 'More about TLS.',
    confidence: 0.9,
    confidenceLevel: ConfidenceLevel.high,
    warnings: const [],
    provider: request.provider,
    model: request.model,
    requestId: 'req-1',
  );

  @override
  Future<List<ProviderInfo>> providers() async => providerList;

  @override
  Future<List<ModelInfo>> models(String providerId) async =>
      modelMap[providerId] ?? const [];

  @override
  Future<AnalysisResult> analyze(
    AnalyzeRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    return onAnalyze(request, cancelToken);
  }
}
