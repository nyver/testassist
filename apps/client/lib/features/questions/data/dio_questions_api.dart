import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/network/pinned_dio.dart';
import '../domain/models.dart';
import '../domain/questions_api.dart';
import 'question_json.dart';

class DioQuestionsApi implements QuestionsApi {
  DioQuestionsApi(this._connection);

  final ApiConnection _connection;

  @override
  Future<List<ProviderInfo>> providers() => _connection.guard((dio) async {
    final response = await dio.get<List<Object?>>('/api/v1/llm/providers');
    return [
      for (final item in _objects(response.data))
        ProviderInfo(
          id: item['id']! as String,
          name: item['name']! as String,
          isDefault: item['isDefault']! as bool,
        ),
    ];
  });

  @override
  Future<List<ModelInfo>> models(String providerId) => _connection.guard((
    dio,
  ) async {
    final response = await dio.get<List<Object?>>(
      '/api/v1/llm/models',
      queryParameters: {'provider': providerId},
    );
    return [
      for (final item in _objects(response.data))
        ModelInfo(
          id: item['id']! as String,
          name: item['name']! as String,
          supportsText:
              (item['capabilities']! as Map<String, Object?>)['text']! as bool,
          supportsVision:
              (item['capabilities']! as Map<String, Object?>)['vision']!
                  as bool,
          isDefault: item['isDefault']! as bool,
        ),
    ];
  });

  @override
  Future<AnalysisResult> analyze(
    AnalyzeRequest request, {
    CancelToken? cancelToken,
  }) => _connection.guard((dio) async {
    final form = FormData.fromMap({
      if (!request.imageOnly) ...{
        'question': request.question.trim(),
        'options': jsonEncode([
          for (final o in request.options)
            {'id': o.id.trim(), 'text': o.text.trim()},
        ]),
      },
      'language': request.language,
      'provider': request.provider,
      'model': request.model,
      if (request.imagePath != null)
        'image': await MultipartFile.fromFile(
          request.imagePath!,
          filename: 'question.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
    });
    final response = await dio.post<Map<String, Object?>>(
      '/api/v1/questions/analyze',
      data: form,
      cancelToken: cancelToken,
    );
    final body = response.data;
    if (body == null) {
      throw const UnexpectedFailure('empty analyze response');
    }
    return analysisResultFromApi(body);
  });

  Iterable<Map<String, Object?>> _objects(List<Object?>? list) {
    if (list == null) throw const UnexpectedFailure('expected a JSON array');
    return list.whereType<Map<String, Object?>>();
  }
}
