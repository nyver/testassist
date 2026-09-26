import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_assistant/core/database/app_database.dart';
import 'package:test_assistant/core/storage/image_store.dart';
import 'package:test_assistant/features/history/data/drift_history_repository.dart';
import 'package:test_assistant/features/history/domain/history_entry.dart';
import 'package:test_assistant/features/history/domain/history_service.dart';
import 'package:test_assistant/features/questions/data/drift_draft_repository.dart';
import 'package:test_assistant/features/questions/data/question_json.dart';
import 'package:test_assistant/features/questions/domain/models.dart';
import 'package:test_assistant/features/servers/data/drift_server_repository.dart';
import 'package:test_assistant/features/settings/data/settings_repository.dart';

import '../support/test_data.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory tmp;
  late ImageStore images;

  setUp(() async {
    db = openTestDatabase();
    tmp = await Directory.systemTemp.createTemp('repo_test_');
    images = ImageStore(tmp);
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  group('servers', () {
    test('add, read, rename, touch and remove', () async {
      var now = DateTime.utc(2026, 1, 1);
      final repo = DriftServerRepository(db, clock: () => now);
      expect(await repo.current(), isNull);

      final added = await repo.add(
        serverId: '019d2f6e-8a3c-7c1e-9b41-5d2a6f0e1c77',
        name: 'Home',
        baseUrl: Uri.parse('https://192.168.1.10:8443'),
      );
      expect(added.name, 'Home');
      expect(added.baseUrl.toString(), 'https://192.168.1.10:8443');
      expect(added.createdAt.toUtc(), now);

      await repo.rename(added.id, 'Office');
      now = DateTime.utc(2026, 1, 2);
      await repo.touch(added.id);

      final current = (await repo.current())!;
      expect(current.name, 'Office');
      expect(current.lastUsedAt.toUtc(), now);
      expect(current.createdAt.toUtc(), DateTime.utc(2026, 1, 1));

      await repo.remove(added.id);
      expect(await repo.current(), isNull);
    });

    test('the server id is unique', () async {
      final repo = DriftServerRepository(db);
      await repo.add(serverId: 's', name: 'a', baseUrl: Uri.parse('https://a'));
      expect(
        repo.add(serverId: 's', name: 'b', baseUrl: Uri.parse('https://b')),
        throwsA(anything),
      );
    });

    test('the database has no column that could hold a secret', () async {
      final columns = await db
          .customSelect("SELECT name FROM pragma_table_info('servers')")
          .get();
      final names = columns.map((r) => r.read<String>('name')).toSet();
      expect(names, {
        'id',
        'server_id',
        'name',
        'base_url',
        'created_at',
        'last_used_at',
      });
    });
  });

  group('history', () {
    Future<DriftHistoryRepository> repoAt(List<DateTime> times) async {
      var i = 0;
      return DriftHistoryRepository(db, clock: () => times[i++]);
    }

    NewHistoryEntry entry({
      String question = 'Q?',
      String? imagePath,
      AnalysisResult? result,
      int? serverRef,
    }) => NewHistoryEntry(
      imagePath: imagePath,
      ocrText: 'raw ocr',
      questionText: question,
      options: optionsAbcd,
      result: result ?? answeredResult(),
      serverRef: serverRef,
    );

    test('a saved entry keeps every field', () async {
      final repo = await repoAt([DateTime.utc(2026, 2, 3, 4, 5)]);
      final saved = await repo.insert(
        entry(
          imagePath: 'images/a.jpg',
          result: answeredResult(details: 'More text', warnings: ['careful']),
        ),
      );

      final loaded = (await repo.get(saved.id))!;
      expect(loaded.createdAt.toUtc(), DateTime.utc(2026, 2, 3, 4, 5));
      expect(loaded.imagePath, 'images/a.jpg');
      expect(loaded.ocrText, 'raw ocr');
      expect(loaded.questionText, 'Q?');
      expect(loaded.options, optionsAbcd);
      final r = loaded.result;
      expect(r.status, AnswerStatus.answered);
      expect(r.correctOptionIds, ['B']);
      expect(r.answerText, 'HTTPS');
      expect(r.explanation, 'HTTPS wraps HTTP in TLS.');
      expect(r.details, 'More text');
      expect(r.warnings, ['careful']);
      expect(r.confidence, 0.96);
      expect(r.confidenceLevel, ConfidenceLevel.high);
      expect(r.provider, 'openrouter');
      expect(r.model, 'openai/gpt-4o-mini');
      expect(r.requestId, 'req-1');
    });

    test('uncertain results round-trip', () async {
      final repo = DriftHistoryRepository(db);
      final saved = await repo.insert(entry(result: uncertainResult()));
      final r = (await repo.get(saved.id))!.result;
      expect(r.isUncertain, isTrue);
      expect(r.correctOptionIds, isEmpty);
      expect(r.answerText, isNull);
      expect(r.warnings, ['Option C is not readable']);
      expect(r.confidenceLevel, ConfidenceLevel.low);
    });

    test('the list is newest first', () async {
      final repo = await repoAt([
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3),
        DateTime.utc(2026, 1, 2),
      ]);
      await repo.insert(entry(question: 'oldest'));
      await repo.insert(entry(question: 'newest'));
      await repo.insert(entry(question: 'middle'));

      final list = await repo.list();
      expect(list.map((e) => e.questionText), ['newest', 'middle', 'oldest']);
      final watched = await repo.watchAll().first;
      expect(watched.map((e) => e.questionText), [
        'newest',
        'middle',
        'oldest',
      ]);
    });

    test('delete and clear', () async {
      final repo = DriftHistoryRepository(db);
      final a = await repo.insert(entry(question: 'a'));
      await repo.insert(entry(question: 'b'));

      await repo.delete(a.id);
      expect((await repo.list()).map((e) => e.questionText), ['b']);
      expect(await repo.get(a.id), isNull);

      await repo.clear();
      expect(await repo.list(), isEmpty);
    });

    test('removing the server keeps its history', () async {
      final servers = DriftServerRepository(db);
      final server = await servers.add(
        serverId: 's',
        name: 'n',
        baseUrl: Uri.parse('https://x'),
      );
      final repo = DriftHistoryRepository(db);
      final saved = await repo.insert(entry(serverRef: server.id));

      await servers.remove(server.id);

      final loaded = (await repo.get(saved.id))!;
      expect(loaded.serverRef, isNull);
      expect(loaded.questionText, 'Q?');
    });

    test('unsupported stored JSON versions are refused, not misread', () {
      expect(
        () => decodeOptions('{"v":2,"options":[]}'),
        throwsFormatException,
      );
      expect(() => decodeOptions('[]'), throwsFormatException);
    });
  });

  group('drafts', () {
    test('save, load, overwrite and clear a single draft', () async {
      final repo = DriftDraftRepository(db);
      expect(await repo.load(), isNull);

      await repo.save(
        const QuestionDraft(
          imagePath: 'images/x.jpg',
          ocrText: 'raw',
          questionText: 'Question',
          options: optionsAbcd,
          sendImage: true,
        ),
      );
      final first = (await repo.load())!;
      expect(first.imagePath, 'images/x.jpg');
      expect(first.ocrText, 'raw');
      expect(first.questionText, 'Question');
      expect(first.options, optionsAbcd);
      expect(first.sendImage, isTrue);

      await repo.save(first.copyWith(questionText: 'Edited', sendImage: false));
      final second = (await repo.load())!;
      expect(second.questionText, 'Edited');
      expect(second.sendImage, isFalse);
      expect(await db.select(db.drafts).get(), hasLength(1));

      await repo.clear();
      expect(await repo.load(), isNull);
    });

    test('a draft without an image is allowed', () async {
      final repo = DriftDraftRepository(db);
      await repo.save(
        const QuestionDraft(
          imagePath: null,
          ocrText: '',
          questionText: '',
          options: [],
          sendImage: false,
        ),
      );
      expect((await repo.load())!.imagePath, isNull);
    });
  });

  group('image store', () {
    Future<StoredImage> writeImage(List<int> bytes) async {
      final stored = await images.create();
      await stored.file.writeAsBytes(bytes);
      return stored;
    }

    test(
      'images live in the private images directory under a relative path',
      () async {
        final stored = await writeImage([1, 2, 3]);
        expect(
          stored.relativePath,
          matches(RegExp(r'^images/[0-9a-f]{32}\.jpg$')),
        );
        expect(stored.file.path, startsWith(tmp.path));
        expect(images.resolve(stored.relativePath)!.path, stored.file.path);
        expect(await images.exists(stored.relativePath), isTrue);
      },
    );

    test('paths that leave the image directory are not resolved', () {
      for (final bad in [
        '../secret.txt',
        'images/../secret.txt',
        '/etc/passwd',
        'images/sub/x.jpg',
        'images/',
        'other/x.jpg',
        r'images/..\secret',
        '',
      ]) {
        expect(images.resolve(bad), isNull, reason: bad);
      }
      expect(images.resolve(null), isNull);
    });

    test('delete tolerates missing files and tampered paths', () async {
      final stored = await writeImage([1]);
      await images.delete(stored.relativePath);
      expect(await stored.file.exists(), isFalse);
      await images.delete(stored.relativePath); // already gone
      await images.delete('../elsewhere'); // ignored
      await images.delete(null);
    });

    test('orphan sweep keeps referenced files only', () async {
      final kept = await writeImage([1]);
      final orphan = await writeImage([2]);

      final removed = await images.sweepOrphans({kept.relativePath});

      expect(removed, 1);
      expect(await kept.file.exists(), isTrue);
      expect(await orphan.file.exists(), isFalse);
    });

    test('the sweep on a missing directory is a no-op', () async {
      expect(await images.sweepOrphans({}), 0);
    });
  });

  group('history service', () {
    test('deleting an entry deletes its image file', () async {
      final history = DriftHistoryRepository(db);
      final service = HistoryService(history, images);
      final stored = await images.create();
      await stored.file.writeAsBytes([1]);
      final saved = await history.insert(
        NewHistoryEntry(
          imagePath: stored.relativePath,
          ocrText: '',
          questionText: 'Q',
          options: optionsAbcd,
          result: answeredResult(),
          serverRef: null,
        ),
      );

      await service.deleteEntry(saved.id);

      expect(await history.get(saved.id), isNull);
      expect(await stored.file.exists(), isFalse);
    });

    test('an entry whose image is already gone deletes cleanly', () async {
      final history = DriftHistoryRepository(db);
      final saved = await history.insert(
        NewHistoryEntry(
          imagePath: 'images/gone.jpg',
          ocrText: '',
          questionText: 'Q',
          options: optionsAbcd,
          result: answeredResult(),
          serverRef: null,
        ),
      );
      await HistoryService(history, images).deleteEntry(saved.id);
      expect(await history.get(saved.id), isNull);
    });

    test('clear all removes every entry and image', () async {
      final history = DriftHistoryRepository(db);
      final files = <File>[];
      for (var i = 0; i < 3; i++) {
        final stored = await images.create();
        await stored.file.writeAsBytes([i]);
        files.add(stored.file);
        await history.insert(
          NewHistoryEntry(
            imagePath: stored.relativePath,
            ocrText: '',
            questionText: 'Q$i',
            options: optionsAbcd,
            result: answeredResult(),
            serverRef: null,
          ),
        );
      }

      await HistoryService(history, images).clearAll();

      expect(await history.list(), isEmpty);
      for (final f in files) {
        expect(await f.exists(), isFalse);
      }
    });

    test('the startup sweep keeps history and draft images', () async {
      final history = DriftHistoryRepository(db);
      final drafts = DriftDraftRepository(db);
      final inHistory = await images.create();
      final inDraft = await images.create();
      final orphan = await images.create();
      for (final s in [inHistory, inDraft, orphan]) {
        await s.file.writeAsBytes([1]);
      }
      await history.insert(
        NewHistoryEntry(
          imagePath: inHistory.relativePath,
          ocrText: '',
          questionText: 'Q',
          options: optionsAbcd,
          result: answeredResult(),
          serverRef: null,
        ),
      );
      await drafts.save(
        QuestionDraft(
          imagePath: inDraft.relativePath,
          ocrText: '',
          questionText: '',
          options: const [],
          sendImage: false,
        ),
      );

      final removed = await sweepOrphanImages(
        history: history,
        drafts: drafts,
        images: images,
      );

      expect(removed, 1);
      expect(await inHistory.file.exists(), isTrue);
      expect(await inDraft.file.exists(), isTrue);
      expect(await orphan.file.exists(), isFalse);
    });
  });

  group('settings', () {
    test('defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SettingsRepository(await SharedPreferences.getInstance());
      final s = repo.load();
      expect(s.displayMode, AnswerDisplayMode.short);
      expect(s.deleteImagesAfterAnalysis, isFalse);
      expect(s.lastProvider, isNull);
      expect(s.lastModel, isNull);
    });

    test('values persist', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepository(prefs);
      await repo.setDisplayMode(AnswerDisplayMode.detailed);
      await repo.setDeleteImagesAfterAnalysis(value: true);
      await repo.setLastSelection(provider: 'routerai', model: 'x/y');

      final s = SettingsRepository(prefs).load();
      expect(s.displayMode, AnswerDisplayMode.detailed);
      expect(s.deleteImagesAfterAnalysis, isTrue);
      expect(s.lastProvider, 'routerai');
      expect(s.lastModel, 'x/y');
    });

    test('an unknown stored mode falls back to the default', () async {
      SharedPreferences.setMockInitialValues({
        SettingsRepository.displayModeKey: 'from-the-future',
      });
      final repo = SettingsRepository(await SharedPreferences.getInstance());
      expect(repo.load().displayMode, AnswerDisplayMode.short);
    });
  });

  group('draft validation', () {
    test('a valid draft can be sent', () {
      expect(DraftValidation.of('Q?', optionsAbcd).canSend, isTrue);
    });

    test('empty question, too few options, empty or duplicate ids', () {
      expect(DraftValidation.of('  ', optionsAbcd).canSend, isFalse);
      expect(DraftValidation.of('Q', [optionsAbcd.first]).canSend, isFalse);

      final duplicate = DraftValidation.of('Q', const [
        OptionItem(id: 'A', text: 'x'),
        OptionItem(id: 'B', text: 'y'),
        OptionItem(id: 'B', text: 'z'),
      ]);
      expect(duplicate.canSend, isFalse);
      expect(duplicate.duplicateIdIndexes, {1, 2});

      final emptyId = DraftValidation.of('Q', const [
        OptionItem(id: '', text: 'x'),
        OptionItem(id: 'B', text: 'y'),
      ]);
      expect(emptyId.canSend, isFalse);
      expect(emptyId.emptyIdIndexes, {0});

      final emptyText = DraftValidation.of('Q', const [
        OptionItem(id: 'A', text: ' '),
        OptionItem(id: 'B', text: 'y'),
      ]);
      expect(emptyText.canSend, isFalse);
    });
  });
}
