// A tiny OpenAI-compatible LLM for end-to-end checks. It answers every
// question with a fixed, valid JSON answer, so the whole chain (phone, server,
// provider adapter, answer validation) can be exercised without an API key.
//
//   dart run tool/fake_llm.dart [port]      (default 9999)
//
// Endpoints:
//   GET  /v1/models            one text-only and one vision model
//   POST /v1/chat/completions  answers option "HTTPS" (or "B"); a question that
//                              contains TIMEOUT is answered only after 20 s
//   GET  /__stats              the requests seen so far, as JSON
//   POST /__reset              clears the recorded requests
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args.first) : 9999;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('fake LLM on http://127.0.0.1:$port/v1');

  final seen = <Map<String, Object?>>[];

  await for (final request in server) {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/v1/models') {
      _json(request, {
        'data': [
          {
            'id': 'fake/text-model',
            'name': 'Fake text model',
            'architecture': {
              'input_modalities': ['text'],
            },
          },
          {
            'id': 'fake/vision-model',
            'name': 'Fake vision model',
            'architecture': {
              'input_modalities': ['text', 'image'],
            },
          },
        ],
      });
    } else if (request.method == 'GET' && path == '/__stats') {
      _json(request, seen);
    } else if (request.method == 'POST' && path == '/__reset') {
      seen.clear();
      _json(request, {'ok': true});
    } else if (request.method == 'POST' && path == '/v1/chat/completions') {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      final messages = body['messages']! as List<Object?>;
      final user = (messages.last! as Map<String, Object?>)['content'];
      var text = '';
      var hasImage = false;
      if (user is String) {
        text = user;
      } else if (user is List<Object?>) {
        for (final part in user.whereType<Map<String, Object?>>()) {
          if (part['type'] == 'image_url') hasImage = true;
          if (part['type'] == 'text') text = part['text']! as String;
        }
      }
      seen.add({
        'model': body['model'],
        'hasImage': hasImage,
        'question': text.split('\n').skip(1).take(1).join(),
      });
      if (text.contains('TIMEOUT')) {
        await Future<void>.delayed(const Duration(seconds: 20));
      }
      final match = RegExp(
        r'^(\S+): .*HTTPS',
        multiLine: true,
      ).firstMatch(text);
      final answerId = match?.group(1) ?? 'B';
      _json(request, {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': jsonEncode({
                'status': 'answered',
                'correctOptionIds': [answerId],
                'explanation': 'HTTPS is HTTP inside TLS.',
                'details': 'TLS encrypts and authenticates the connection.',
                'confidence': 0.95,
                'warnings': <String>[],
              }),
            },
          },
        ],
      });
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  }
}

void _json(HttpRequest request, Object body) {
  request.response
    ..statusCode = 200
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  request.response.close();
}
