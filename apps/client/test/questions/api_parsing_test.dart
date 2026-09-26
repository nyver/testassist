import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/core/errors/app_failure.dart';
import 'package:test_assistant/core/network/pinned_dio.dart';
import 'package:test_assistant/features/questions/data/dio_questions_api.dart';
import 'package:test_assistant/features/questions/domain/models.dart';
import 'package:test_assistant/features/servers/data/dio_server_info_api.dart';
import 'package:test_assistant/l10n/generated/app_localizations_en.dart';
import 'package:test_assistant/l10n/generated/app_localizations_ru.dart';
import 'package:test_assistant/shared/failure_messages.dart';

const _fixtures = '../../protocol/fixtures/api';

String _fixture(String name) => File('$_fixtures/$name').readAsStringSync();

/// Serves fixture files instead of using the network.
class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.respond);

  final ({int status, String body}) Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final r = respond(options);
    return ResponseBody.fromString(
      r.body,
      r.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiConnection _connection(_FixtureAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://server.test'))
    ..httpClientAdapter = adapter;
  return ApiConnection(dio: dio, recorder: PinRecorder());
}

AnalyzeRequest _request() => const AnalyzeRequest(
  question: 'Which protocol encrypts web traffic?',
  options: [
    OptionItem(id: 'A', text: 'HTTP'),
    OptionItem(id: 'B', text: 'HTTPS'),
  ],
  language: 'en',
  provider: 'openrouter',
  model: 'openai/gpt-4o-mini',
);

void main() {
  group('responses match the shared fixtures', () {
    test('server info', () async {
      final api = DioServerInfoApi(
        _connection(
          _FixtureAdapter(
            (_) => (status: 200, body: _fixture('server_info.json')),
          ),
        ),
      );
      final info = await api.fetch();
      expect(info.serverId, '019d2f6e-8a3c-7c1e-9b41-5d2a6f0e1c77');
      expect(info.name, 'Home Assistant Server');
      expect(info.version, '0.1.0');
    });

    test('providers', () async {
      final api = DioQuestionsApi(
        _connection(
          _FixtureAdapter(
            (_) => (status: 200, body: _fixture('providers.json')),
          ),
        ),
      );
      final providers = await api.providers();
      expect(providers.map((p) => p.id), ['openrouter', 'routerai']);
      expect(providers.where((p) => p.isDefault), hasLength(1));
      expect(providers.first.name, 'OpenRouter');
    });

    test('models with capabilities, for the requested provider', () async {
      final adapter = _FixtureAdapter(
        (_) => (status: 200, body: _fixture('models.json')),
      );
      final models = await DioQuestionsApi(_connection(adapter))
          .models('openrouter');

      expect(adapter.requests.single.queryParameters, {
        'provider': 'openrouter',
      });
      expect(models, hasLength(2));
      expect(models[0].id, 'openai/gpt-4o-mini');
      expect(models[0].supportsVision, isTrue);
      expect(models[0].supportsText, isTrue);
      expect(models[0].isDefault, isTrue);
      expect(models[1].supportsVision, isFalse);
    });

    test('an answered result', () async {
      final api = DioQuestionsApi(
        _connection(
          _FixtureAdapter(
            (_) => (status: 200, body: _fixture('analyze_answered.json')),
          ),
        ),
      );
      final r = await api.analyze(_request());

      expect(r.status, AnswerStatus.answered);
      expect(r.correctOptionIds, ['B']);
      expect(r.answerText, 'HTTPS');
      expect(r.explanation, contains('TLS'));
      expect(r.details, isNotNull);
      expect(r.confidence, 0.96);
      expect(r.confidenceLevel, ConfidenceLevel.high);
      expect(r.warnings, isEmpty);
      expect(r.provider, 'openrouter');
      expect(r.model, 'openai/gpt-4o-mini');
      expect(r.requestId, 'req-example-1');
    });

    test('several correct options', () async {
      final api = DioQuestionsApi(
        _connection(
          _FixtureAdapter(
            (_) => (status: 200, body: _fixture('analyze_multi.json')),
          ),
        ),
      );
      final r = await api.analyze(_request());
      expect(r.correctOptionIds, ['A', 'C']);
      expect(r.answerText, 'HTTP; TLS');
      expect(r.details, isNull);
      expect(r.confidenceLevel, ConfidenceLevel.medium);
    });

    test('an uncertain result', () async {
      final api = DioQuestionsApi(
        _connection(
          _FixtureAdapter(
            (_) => (status: 200, body: _fixture('analyze_uncertain.json')),
          ),
        ),
      );
      final r = await api.analyze(_request());
      expect(r.isUncertain, isTrue);
      expect(r.correctOptionIds, isEmpty);
      expect(r.answerText, isNull);
      expect(r.explanation, isNull);
      expect(r.warnings, ['Option C is not readable']);
      expect(r.confidenceLevel, ConfidenceLevel.low);
    });
  });

  group('the analyze request', () {
    test(
      'is multipart with question, options, language, provider and model',
      () async {
        final adapter = _FixtureAdapter(
          (_) => (status: 200, body: _fixture('analyze_answered.json')),
        );
        await DioQuestionsApi(_connection(adapter)).analyze(_request());

        final options = adapter.requests.single;
        expect(options.method, 'POST');
        expect(options.path, '/api/v1/questions/analyze');
        final form = options.data as FormData;
        final fields = {for (final f in form.fields) f.key: f.value};
        expect(fields['question'], 'Which protocol encrypts web traffic?');
        expect(fields['language'], 'en');
        expect(fields['provider'], 'openrouter');
        expect(fields['model'], 'openai/gpt-4o-mini');
        expect(jsonDecode(fields['options']!), [
          {'id': 'A', 'text': 'HTTP'},
          {'id': 'B', 'text': 'HTTPS'},
        ]);
        expect(form.files, isEmpty, reason: 'no image was attached');
      },
    );

    test('attaches the image only when a path is given', () async {
      final dir = Directory.systemTemp.createTempSync('api_test_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows can keep the file open a moment longer; it is a temp dir.
        }
      });
      final file = File('${dir.path}/q.jpg')..writeAsBytesSync([1, 2, 3]);
      final adapter = _FixtureAdapter(
        (_) => (status: 200, body: _fixture('analyze_answered.json')),
      );

      await DioQuestionsApi(_connection(adapter)).analyze(
        AnalyzeRequest(
          question: 'Q',
          options: const [
            OptionItem(id: 'A', text: 'a'),
            OptionItem(id: 'B', text: 'b'),
          ],
          language: 'ru',
          provider: 'p',
          model: 'm',
          imagePath: file.path,
        ),
      );

      final form = adapter.requests.single.data as FormData;
      expect(form.files, hasLength(1));
      expect(form.files.single.key, 'image');
      expect(form.files.single.value.contentType?.mimeType, 'image/jpeg');
    });

    test('an image-only request carries no question and no options', () async {
      final dir = Directory.systemTemp.createTempSync('api_test_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows can keep the file open a moment longer; it is a temp dir.
        }
      });
      final file = File('${dir.path}/q.jpg')..writeAsBytesSync([1, 2, 3]);
      final adapter = _FixtureAdapter(
        (_) => (status: 200, body: _fixture('analyze_image_only.json')),
      );

      final result = await DioQuestionsApi(_connection(adapter)).analyze(
        AnalyzeRequest(
          question: '',
          options: const [],
          language: 'ru',
          provider: 'p',
          model: 'm',
          imagePath: file.path,
          imageOnly: true,
        ),
      );

      final form = adapter.requests.single.data as FormData;
      final keys = form.fields.map((f) => f.key).toSet();
      expect(keys, {'language', 'provider', 'model'});
      expect(form.files.single.key, 'image');

      expect(result.recognizedQuestion, 'Что такое ООП?');
      expect(result.recognizedOptions, hasLength(2));
      expect(result.recognizedOptions!.first.id, 'A');
      expect(result.correctOptionIds, ['A']);
    });

    test(
      'a response to a request with text has no recognized fields',
      () async {
        final adapter = _FixtureAdapter(
          (_) => (status: 200, body: _fixture('analyze_answered.json')),
        );
        final result = await DioQuestionsApi(_connection(adapter))
            .analyze(_request());

        expect(result.recognizedQuestion, isNull);
        expect(result.recognizedOptions, isNull);
      },
    );

    test('trims the question and option ids and texts', () async {
      final adapter = _FixtureAdapter(
        (_) => (status: 200, body: _fixture('analyze_answered.json')),
      );
      await DioQuestionsApi(_connection(adapter)).analyze(
        const AnalyzeRequest(
          question: '  Q?  ',
          options: [
            OptionItem(id: ' A ', text: ' one '),
            OptionItem(id: 'B', text: 'two'),
          ],
          language: 'en',
          provider: 'p',
          model: 'm',
        ),
      );
      final fields = {
        for (final f in (adapter.requests.single.data as FormData).fields)
          f.key: f.value,
      };
      expect(fields['question'], 'Q?');
      expect((jsonDecode(fields['options']!) as List<Object?>)[0], {
        'id': 'A',
        'text': 'one',
      });
    });
  });

  group('error responses become typed failures', () {
    const cases = {
      'error_invalid_request.json': ('INVALID_REQUEST', 400),
      'error_unauthorized.json': ('UNAUTHORIZED', 401),
      'error_provider_not_found.json': ('PROVIDER_NOT_FOUND', 404),
      'error_model_not_found.json': ('MODEL_NOT_FOUND', 404),
      'error_image_too_large.json': ('IMAGE_TOO_LARGE', 413),
      'error_unsupported_image_type.json': ('UNSUPPORTED_IMAGE_TYPE', 415),
      'error_model_no_vision.json': ('MODEL_DOES_NOT_SUPPORT_VISION', 422),
      'error_rate_limited.json': ('RATE_LIMITED', 429),
      'error_internal_error.json': ('INTERNAL_ERROR', 500),
      'error_llm_unavailable.json': ('LLM_PROVIDER_UNAVAILABLE', 502),
      'error_llm_invalid_response.json': ('LLM_INVALID_RESPONSE', 502),
      'error_llm_timeout.json': ('LLM_TIMEOUT', 504),
    };

    cases.forEach((file, expected) {
      test('$file is ${expected.$1}', () async {
        final api = DioQuestionsApi(
          _connection(
            _FixtureAdapter((_) => (status: expected.$2, body: _fixture(file))),
          ),
        );
        await expectLater(
          api.analyze(_request()),
          throwsA(
            isA<ApiFailure>()
                .having((f) => f.code, 'code', expected.$1)
                .having((f) => f.statusCode, 'status', expected.$2)
                .having((f) => f.requestId, 'requestId', 'req-example-err'),
          ),
        );
      });
    });

    test('a malformed success body is unexpected, not a crash', () async {
      final api = DioQuestionsApi(
        _connection(
          _FixtureAdapter((_) => (status: 200, body: '{"status":"weird"}')),
        ),
      );
      await expectLater(
        api.analyze(_request()),
        throwsA(isA<UnexpectedFailure>()),
      );
    });

    test('an HTML error page is not shown as raw text', () async {
      final api = DioQuestionsApi(
        _connection(
          _FixtureAdapter((_) => (status: 502, body: '<html>bad</html>')),
        ),
      );
      await expectLater(api.providers(), throwsA(isA<UnexpectedFailure>()));
    });
  });

  group('user-facing messages', () {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();

    ApiFailure api(String code, {String? id}) =>
        ApiFailure(code: code, message: 'server text', requestId: id);

    test('the specification list', () {
      expect(
        failureMessage(en, const NetworkFailure()),
        'Could not connect to the server. Check the network and server address.',
      );
      expect(
        failureMessage(en, const CertificateChangedFailure()),
        'Server certificate has changed. Connection blocked.',
      );
      expect(
        failureMessage(en, api('LLM_TIMEOUT')),
        'The model did not respond in time. Try again.',
      );
      expect(
        failureMessage(en, api('UNAUTHORIZED')),
        contains('server settings'),
      );
      expect(failureMessage(en, api('RATE_LIMITED')), contains('Wait'));
      expect(
        failureMessage(en, api('MODEL_DOES_NOT_SUPPORT_VISION')),
        'The selected model does not support images. Only the recognized text will be sent.',
      );
    });

    test('an unknown server error shows the request id and no raw text', () {
      final message = failureMessage(en, api('INTERNAL_ERROR', id: 'abc'));
      expect(message, contains('abc'));
      expect(message, isNot(contains('server text')));
      expect(message, isNot(contains('Exception')));
    });

    test('unexpected failures never expose exception text', () {
      final message = failureMessage(en, const UnexpectedFailure('StateError'));
      expect(message, isNot(contains('StateError')));
    });

    test('every failure has a Russian message too', () {
      for (final f in <AppFailure>[
        const NetworkFailure(),
        const CertificateChangedFailure(),
        const ServerMismatchFailure(),
        const CancelledFailure(),
        const UnexpectedFailure(),
        api('LLM_TIMEOUT'),
        api('INTERNAL_ERROR', id: 'x'),
      ]) {
        final message = failureMessage(ru, f);
        expect(message, isNotEmpty);
        expect(message, isNot(failureMessage(en, f)));
      }
    });

    test('which failures are worth retrying', () {
      expect(failureIsRetryable(const NetworkFailure()), isTrue);
      expect(failureIsRetryable(api('LLM_TIMEOUT')), isTrue);
      expect(failureIsRetryable(api('RATE_LIMITED')), isTrue);
      expect(failureIsRetryable(const CertificateChangedFailure()), isFalse);
      expect(failureIsRetryable(api('UNAUTHORIZED')), isFalse);
    });
  });
}
