import 'package:flutter/widgets.dart';

void main() => runApp(const _SmokeApp());

final class _SmokeApp extends StatelessWidget {
  const _SmokeApp();

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: Text('opencode_auth mobile smoke')),
  );
}
