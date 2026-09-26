import 'package:dio/dio.dart';

import 'models.dart';

/// The question-related endpoints of the server.
abstract interface class QuestionsApi {
  Future<List<ProviderInfo>> providers();

  Future<List<ModelInfo>> models(String providerId);

  /// Sends the question. Cancelling [cancelToken] aborts the HTTP request.
  Future<AnalysisResult> analyze(
    AnalyzeRequest request, {
    CancelToken? cancelToken,
  });
}
