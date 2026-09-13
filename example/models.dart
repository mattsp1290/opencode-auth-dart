import 'dart:io';

import 'package:http/io_client.dart';
import 'package:opencode_auth/opencode_auth.dart';

Future<void> main() async {
  final userAgent = Platform.environment['OPENCODE_USER_AGENT'];
  if (userAgent == null) {
    stderr.writeln('Set OPENCODE_USER_AGENT to the host application identity.');
    exitCode = 64;
    return;
  }

  // listModels is unauthenticated, but options still define the inference
  // client contract. This placeholder is never sent by listModels.
  final httpClient = IOClient(HttpClient());
  final auth = OpenCodeAuthClient(
    OpenCodeAuthOptions(
      apiKey: 'unused-for-model-catalog',
      client: httpClient,
      userAgent: userAgent,
    ),
  );
  try {
    final models = await auth.listModels();
    for (final model in models) {
      stdout.writeln(model.id);
    }
  } on OpenCodeAuthException catch (error) {
    stderr.writeln('Model catalog failed: ${error.code}.');
    exitCode = 1;
  } finally {
    await auth.close();
    httpClient.close();
  }
}
