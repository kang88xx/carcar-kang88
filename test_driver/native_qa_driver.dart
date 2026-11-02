import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['CARCAR_QA_ARTIFACT_DIR'] ?? 'build/native-qa',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name) ||
          bytes.length < 8 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        return false;
      }
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? <String, dynamic>{});
      final screenshots = report.remove('screenshots') as List<dynamic>?;
      report['screenshotFiles'] = [
        for (final screenshot in screenshots ?? <dynamic>[])
          '${(screenshot as Map<String, dynamic>)['screenshotName']}.png',
      ];
      await File(
        '${output.path}/observations.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    },
  );
}
