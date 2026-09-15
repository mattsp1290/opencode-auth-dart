import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_auth_mobile_smoke/main.dart' as app;

void main() {
  testWidgets('renders the mobile smoke fixture', (tester) async {
    app.main();
    await tester.pump();

    expect(find.text('opencode_auth mobile smoke'), findsOneWidget);
  });
}
