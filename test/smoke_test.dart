import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/main.dart';

void main() {
  testWidgets('app 能启动并渲染标题', (WidgetTester tester) async {
    await tester.pumpWidget(const EpdControllerApp());
    expect(find.text('EPD Controller'), findsOneWidget);
  });
}
