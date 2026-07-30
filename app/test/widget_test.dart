import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gongyi_app/main.dart';
import 'package:gongyi_app/config.dart';
import 'package:gongyi_app/pages/game_preview_page.dart';

Future<void> _enterPreviewApp(WidgetTester tester) async {
  await tester.pumpWidget(const GongyiApp());
  await tester.pumpAndSettle();
  expect(find.text('无需 L 站授权检查版'), findsOneWidget);
  expect(find.text('使用 Linux.do 登录'), findsNothing);
  await tester.tap(find.byKey(const ValueKey('preview-login')));
  await tester.pumpAndSettle();
  expect(find.text('工作台'), findsOneWidget);
}

void main() {
  testWidgets('App 启动显示加载页', (WidgetTester tester) async {
    await tester.pumpWidget(const GongyiApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  }, skip: AppConfig.previewMode);

  testWidgets('预览模式可查看并筛选额度收支明细', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _enterPreviewApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('额度收支明细'), findsOneWidget);

    await tester.tap(find.text('额度收支明细'));
    await tester.pumpAndSettle();
    expect(find.text('本页收入'), findsOneWidget);
    expect(find.text('完成激励广告任务'), findsNWidgets(2));

    await tester.tap(find.text('支出'));
    await tester.pumpAndSettle();
    expect(find.text('图片生成 · gpt-image-1.5'), findsOneWidget);
    expect(find.text('完成激励广告任务'), findsNothing);
  }, skip: !AppConfig.previewMode);

  testWidgets('检查版点击广告不播放也不增加额度', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _enterPreviewApp(tester);
    await tester.tap(find.text('额度'));
    await tester.pumpAndSettle();
    expect(find.text(r'$12.80'), findsOneWidget);
    expect(find.text('观看广告（剩余 4 次）'), findsOneWidget);

    await tester.tap(find.text('观看广告（剩余 4 次）'));
    await tester.pumpAndSettle();
    expect(find.text('检查版未连接真实广告，不播放广告，也不会发放额度'), findsOneWidget);
    expect(find.text(r'$12.80'), findsOneWidget);
    expect(find.text('观看广告（剩余 4 次）'), findsOneWidget);
  }, skip: !AppConfig.previewMode);

  testWidgets('预览模式可打开历史对话并新建对话', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _enterPreviewApp(tester);

    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pumpAndSettle();
    expect(find.text('Flutter 客户端并发设计'), findsOneWidget);

    await tester.tap(find.text('Flutter 客户端并发设计'));
    await tester.pumpAndSettle();
    expect(find.text('Flutter 桌面端多人并发时应该怎样控制任务数量？'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-turn-marker-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conversation-turn-marker-6')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('conversation-turn-marker-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新对话'));
    await tester.pumpAndSettle();
    expect(find.text('今天想解决什么问题？'), findsOneWidget);
  }, skip: !AppConfig.previewMode);

  testWidgets('预览模式支持生图比例与提示词历史', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _enterPreviewApp(tester);
    await tester.tap(find.text('生图'));
    await tester.pumpAndSettle();

    expect(find.text('1:1'), findsOneWidget);
    expect(find.text('16:9'), findsOneWidget);
    expect(find.text('3:4'), findsOneWidget);
    await tester.tap(find.text('16:9'));
    await tester.enterText(
      find.widgetWithText(TextField, '提示词'),
      '夏日湖边的 AI 工作站',
    );
    await tester.tap(find.text('生成图片'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.text('夏日湖边的 AI 工作站'), findsOneWidget);
    expect(find.textContaining('gpt-image-1.5 · 16:9'), findsWidgets);
  }, skip: !AppConfig.previewMode);

  testWidgets('预览模式可同步本站 Key 并查看模型中心', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _enterPreviewApp(tester);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('获取本站Key'), findsOneWidget);
    await tester.tap(find.text('获取本站Key'));
    await tester.pumpAndSettle();
    expect(find.text('已从本站同步 Key'), findsOneWidget);

    await tester.tap(find.text('模型中心'));
    await tester.pumpAndSettle();
    expect(find.text('deepseek-v3.2'), findsOneWidget);
    expect(find.text('gpt-5.4'), findsOneWidget);
    expect(find.text('claude-sonnet-4.6'), findsOneWidget);
  }, skip: !AppConfig.previewMode);

  testWidgets('预览模式可从工作台创建Word任务', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _enterPreviewApp(tester);
    expect(find.text('AI工具APP开发说明'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workbench-tool-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-tool-word')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '整理一份MES实施计划');
    await tester.tap(find.byKey(const ValueKey('workbench-submit')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Word 生成任务'), findsOneWidget);
    expect(find.text('已提交 Word 文档生成任务。'), findsOneWidget);
  }, skip: !AppConfig.previewMode);

  testWidgets('工作台不展示额外联网与Skill入口', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _enterPreviewApp(tester);
    expect(find.byKey(const ValueKey('workbench-search-menu')), findsNothing);
    expect(find.text('联网搜索'), findsNothing);
    expect(find.text('深度研究'), findsNothing);
    expect(find.text('代码审查'), findsNothing);
  }, skip: !AppConfig.previewMode);

  testWidgets('无需L站检查版可登录并打开四款游戏', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _enterPreviewApp(tester);
    await tester.tap(find.text('额度'));
    await tester.pumpAndSettle();
    expect(find.text('游戏大厅'), findsOneWidget);

    await tester.tap(find.text('游戏大厅'));
    await tester.pumpAndSettle();
    expect(find.text('大逃杀'), findsOneWidget);
    expect(find.text('石头剪刀布'), findsOneWidget);
    expect(find.text('扫雷'), findsOneWidget);

    await tester.tap(find.text('游戏大厅'));
    await tester.pumpAndSettle();
    expect(find.text('八房生存局'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('宝石消消乐'), findsOneWidget);
  }, skip: !AppConfig.previewMode);

  testWidgets('检查账号退出后返回无需L站登录页', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _enterPreviewApp(tester);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('本机检查账号 · 无需 L 站授权'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出'));
    await tester.pumpAndSettle();

    expect(find.text('无需 L 站授权检查版'), findsOneWidget);
    expect(find.text('使用 Linux.do 登录'), findsNothing);
  }, skip: !AppConfig.previewMode);

  testWidgets('游戏大厅可选拳并生成对局记录', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const GamePreviewPage(
          rpsRevealDuration: Duration(milliseconds: 300),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('石头剪刀布'), findsOneWidget);
    expect(find.text('扫雷'), findsOneWidget);
    expect(find.text('大逃杀'), findsOneWidget);
    await tester.tap(find.text('石头剪刀布'));
    await tester.pumpAndSettle();
    expect(find.text('本局规则'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game-enter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('剪刀'));
    await tester.tap(find.text('投入10积分并出拳'));
    await tester.pump();
    expect(find.text('等待对手出拳'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pumpAndSettle();

    expect(find.textContaining('对手出'), findsWidgets);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('额度兑换'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('conversion-game-to-ai')));
    await tester.pumpAndSettle();
    expect(find.text('可兑回游戏积分：70'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.previewMode);

  testWidgets('AI额度与游戏积分支持受限双向兑换', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const GamePreviewPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('额度兑换'));
    await tester.pumpAndSettle();
    expect(find.text('可用AI额度：320'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('conversion-game-to-ai')));
    await tester.pumpAndSettle();
    expect(find.text('可兑回游戏积分：80'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('conversion-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('已将10游戏积分兑回AI额度'), findsOneWidget);

    await tester.tap(find.text('额度兑换'));
    await tester.pumpAndSettle();
    expect(find.text('可用AI额度：330'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('conversion-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('已将10 AI额度兑换为游戏积分'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.previewMode);

  testWidgets('扫雷红包先展示开包状态再揭晓结果', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const GamePreviewPage(
          mineOpenDuration: Duration(milliseconds: 120),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫雷'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('game-enter-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('青禾 0.68'), findsOneWidget);
    await tester.tap(find.text('拆红包').first);
    await tester.pump();

    expect(find.text('正在拆红包'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    final revealed =
        find.text('安全').evaluate().isNotEmpty ||
        find.text('中雷').evaluate().isNotEmpty;
    expect(revealed, isTrue);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('查看详情'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('星河的红包'), findsOneWidget);
    expect(find.textContaining('7个红包共10积分'), findsOneWidget);
    expect(find.text('中雷'), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    final claimedLabel = find.descendant(
      of: find.byType(FilledButton),
      matching: find.text('查看详情'),
    );
    expect(claimedLabel, findsOneWidget);
    final claimedButton = tester.widget<FilledButton>(
      find.ancestor(of: claimedLabel, matching: find.byType(FilledButton)),
    );
    expect(claimedButton.onPressed, isNotNull);
    expect(find.textContaining('我 '), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.previewMode);

  testWidgets('游戏记录可按游戏查看最近二十局完整结果', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const GamePreviewPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的记录'));
    await tester.pumpAndSettle();

    expect(find.text('最近20局'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '八房生存局'));
    await tester.pumpAndSettle();
    expect(find.textContaining('淘汰1、6号房'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '石头剪刀布'));
    await tester.pumpAndSettle();
    expect(find.textContaining('双方均出石头'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.previewMode);

  testWidgets('八房前20秒可切换并在封盘后结算', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const GamePreviewPage(
          battleRoundDuration: Duration(milliseconds: 600),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('大逃杀'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('game-enter-button')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const ValueKey('battle-room-1')));
    await tester.tap(find.text('确认加入'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('battle-room-2')));
    await tester.pump();
    expect(find.text('已切换到2号房，原投入未重复扣除'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('本轮已结算'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.textContaining('淘汰房间'), findsOneWidget);
    expect(find.text('进入下一轮'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.previewMode);

  testWidgets('Nord游戏首页在320宽度下无布局溢出', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const GamePreviewPage(),
      ),
    );
    await tester.pump();

    expect(find.text('大逃杀'), findsOneWidget);
    expect(find.text('石头剪刀布'), findsOneWidget);
    expect(find.text('扫雷'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('游戏大厅'), findsOneWidget);
    expect(find.text('我的记录'), findsOneWidget);
    expect(find.text('个人中心'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.previewMode);
}
