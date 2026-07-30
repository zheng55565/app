import '../ai/image_history_store.dart';
import 'preview_session.dart';

class PreviewData {
  PreviewData._();

  static const chatModels = <String>[
    'deepseek-v3.2',
    'gpt-5.4',
    'claude-sonnet-4.6',
    'gemini-3.1-pro',
  ];

  static const imageModels = <String>['gpt-image-1.5', 'flux-2-pro'];

  static Map<String, dynamic> wallet() => {
    'station_balance_usd': 12.80,
    'today_earned_usd': 0.60,
    'total_earned_usd': 18.40,
  };

  static Map<String, dynamic> adTask() => {
    'watched_count': 2,
    'remaining_count': 4,
    'max_count': 6,
    'reward_usd': 0.0028,
  };

  static Map<String, dynamic> profile() => {
    'id': 10086,
    'linuxdo_username': PreviewSession.username,
    'station_user_id': 9527,
  };

  static List<ImageHistoryRecord> imageHistory() => [
    ImageHistoryRecord(
      id: 'preview-history-1',
      prompt: '未来感城市中的公益 AI 服务站，清晨自然光',
      renderedPrompt: '未来感城市中的公益 AI 服务站，清晨自然光 --ar 16:9 --style raw',
      model: 'gpt-image-1.5',
      ratio: '16:9',
      createdAt: DateTime(2026, 7, 28, 17, 30),
    ),
    ImageHistoryRecord(
      id: 'preview-history-2',
      prompt: '简洁的移动端 AI 助手界面，柔和自然光',
      renderedPrompt: '简洁的移动端 AI 助手界面，柔和自然光 --ar 3:4 --style raw',
      model: 'flux-2-pro',
      ratio: '3:4',
      createdAt: DateTime(2026, 7, 28, 15, 10),
    ),
  ];

  static List<Map<String, dynamic>> quotaRecords() => [
    {
      'id': 5,
      'amount_usd': 0.30,
      'balance_after_usd': 12.80,
      'type': 'ad_reward',
      'source': 'ad_callback',
      'remark': '完成激励广告任务',
      'created_at': '2026-07-28T17:42:00+08:00',
    },
    {
      'id': 4,
      'amount_usd': -0.08,
      'balance_after_usd': 12.50,
      'type': 'image_generation',
      'source': 'app_image',
      'remark': '图片生成 · gpt-image-1.5',
      'created_at': '2026-07-28T16:18:00+08:00',
    },
    {
      'id': 3,
      'amount_usd': -0.03,
      'balance_after_usd': 12.58,
      'type': 'api_consume',
      'source': 'app_chat',
      'remark': 'AI 工作台 · claude-sonnet-4.6',
      'created_at': '2026-07-28T15:06:00+08:00',
    },
    {
      'id': 2,
      'amount_usd': 0.30,
      'balance_after_usd': 12.61,
      'type': 'ad_reward',
      'source': 'ad_callback',
      'remark': '完成激励广告任务',
      'created_at': '2026-07-28T12:35:00+08:00',
    },
    {
      'id': 1,
      'amount_usd': -0.10,
      'balance_after_usd': 12.31,
      'type': 'game_consume',
      'source': 'mini_game',
      'remark': '石头剪刀布投入',
      'created_at': '2026-07-28T11:20:00+08:00',
    },
  ];

  static String chatReply(String prompt) {
    return '这是本地预览回复。正式接入后，任务“$prompt”将通过本站 New API '
        '调用所选模型，额度由服务端统一扣减。';
  }
}
