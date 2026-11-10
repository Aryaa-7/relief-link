import 'package:flutter_test/flutter_test.dart';
import 'package:relieflink_app/main.dart';
import 'package:relieflink_app/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ReliefLink app loads smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.init();

    await tester.pumpWidget(ReliefLinkApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('ReliefLink'), findsWidgets);

    state.dispose();
  });
}

