import 'dart:math';

class BackendTurnResponse {
  final String transcript;
  final String nbq;

  BackendTurnResponse({required this.transcript, required this.nbq});
}

class BackendSimulator {
  BackendSimulator._();
  static final BackendSimulator instance = BackendSimulator._();

  Future<BackendTurnResponse> processAudioPlaceholder({
    required String audioId,
  }) async {
    // 1) Simulate sending audio to AWS Lambda
    // TODO: Replace with actual API Gateway endpoint.
    // - Send audio file/bytes to Lambda
    // - Return a job id or response payload
    await Future.delayed(const Duration(milliseconds: 800));

    // 2) Simulate fetching transcript from S3 `/transcripts`
    // TODO: Implement real S3 fetch logic if you wire backend in future.
    await Future.delayed(const Duration(milliseconds: 700));

    // 3) Simulate fetching next best question from S3 `/NBQ`
    await Future.delayed(const Duration(milliseconds: 450));

    final seed = audioId.hashCode ^ DateTime.now().millisecondsSinceEpoch;
    final rng = Random(seed);

    const transcripts = [
      'I am feeling good today.',
      'My day was okay, but I was a little tired.',
      'I miss my family and friends.',
      'I went for a walk and enjoyed the weather.',
      'I want to learn more about staying healthy.',
    ];

    const nbq = [
      'How was your day today?',
      'What made you feel that way?',
      'Would you like to talk about your family?',
      'What did you enjoy most during your walk?',
      'What health habit would you like to try this week?',
    ];

    return BackendTurnResponse(
      transcript: transcripts[rng.nextInt(transcripts.length)],
      nbq: nbq[rng.nextInt(nbq.length)],
    );
  }
}
