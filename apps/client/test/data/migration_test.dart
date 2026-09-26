import 'dart:io';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/core/database/app_database.dart';

import '../generated_migrations/schema.dart';

/// Schema tests. Every released schema version needs its snapshot in
/// `drift_schemas/` and a test here that upgrades from it to the current one
/// with fixture data. Version 1 is the first schema, so it is verified against
/// its snapshot.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the current schema version has a snapshot', () {
    expect(AppDatabase.currentSchemaVersion, 1);
    expect(
      File('drift_schemas/drift_schema_v1.json').existsSync(),
      isTrue,
      reason: 'run `dart run drift_dev schema dump` after a schema change',
    );
  });

  test('a database created at version 1 matches the exported v1 snapshot', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    // Opening the database creates it with the app's own onCreate. The verifier
    // then compares every table, column, constraint and index with the snapshot.
    await verifier.migrateAndValidate(db, 1);
  });

  test('version 1 data survives opening with the current code', () async {
    final schema = await verifier.schemaAt(1);
    final oldDb = schema.rawDatabase;
    oldDb.execute(
      'INSERT INTO servers (server_id, name, base_url, created_at, last_used_at) '
      "VALUES ('sid', 'Home', 'https://h:8443', 1767225600, 1767225600)",
    );
    oldDb.execute(
      'INSERT INTO questions (server_ref, image_path, ocr_text, question_text, '
      'options_json, answer_json, provider, model, confidence, '
      "confidence_level, request_id, created_at) VALUES (1, 'images/a.jpg', "
      "'raw', 'Q', '{\"v\":1,\"options\":[]}', '{\"v\":1}', 'p', 'm', 0.9, "
      "'high', 'r', 1767225600)",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    final servers = await db.select(db.servers).get();
    final questions = await db.select(db.questions).get();
    expect(servers.single.name, 'Home');
    expect(questions.single.questionText, 'Q');
    expect(questions.single.imagePath, 'images/a.jpg');
  });

  test(
    'the schema declares the created_at index and the draft check',
    () async {
      final db = AppDatabase((await verifier.schemaAt(1)).newConnection());
      addTearDown(db.close);

      final indexes = await db
          .customSelect("SELECT name FROM pragma_index_list('questions')")
          .get();
      expect(
        indexes.map((r) => r.read<String>('name')),
        contains('questions_created_at'),
      );

      // The single-row constraint of the drafts table.
      await expectLater(
        db.customStatement(
          'INSERT INTO drafts (id, ocr_text, question_text, options_json, '
          "send_image, updated_at) VALUES (2, '', '', '{}', 0, 0)",
        ),
        throwsA(anything),
      );
    },
  );
}
