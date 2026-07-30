import '../api/api_client.dart';

class GameService {
  GameService._();
  static final GameService instance = GameService._();

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  Future<Map<String, dynamic>> execute(
    String action,
    Map<String, dynamic> payload,
  ) {
    return switch (action) {
      'dashboard' => _get('/api/games/dashboard'),
      'wallet' => _get('/api/games/wallet'),
      'convert' => _post('/api/games/convert', {
        'direction': payload['direction'] ?? 'ai_to_game',
        'amount': payload['amount'],
        'request_id': payload['action_request_id'],
      }),
      'rps_play' => _post('/api/games/rps/play', {
        'choice': payload['choice'],
        'stake': payload['stake'],
        'request_id': payload['action_request_id'],
      }),
      'mine_list' => _get('/api/games/mines'),
      'mine_create' => _post('/api/games/mines', {
        'mine_digit': payload['mine_digit'],
        'total': payload['total'],
        'request_id': payload['action_request_id'],
      }),
      'mine_grab' => _post(
        '/api/games/mines/${_safeId(payload['packet_id'])}/grab',
        {'request_id': payload['action_request_id']},
      ),
      'battle_state' => _get('/api/games/battle/current'),
      'battle_join' =>
        _post('/api/games/battle/${_safeId(payload['round_id'])}/join', {
          'room_no': payload['room_no'],
          'stake': payload['stake'],
          'request_id': payload['action_request_id'],
        }),
      'match3_state' => _get('/api/games/match3'),
      'match3_start' => _post('/api/games/match3/start', {
        'level_no': payload['level_no'],
      }),
      'match3_move' =>
        _post('/api/games/match3/${_safeId(payload['session_id'])}/move', {
          'from_x': payload['from_x'],
          'from_y': payload['from_y'],
          'to_x': payload['to_x'],
          'to_y': payload['to_y'],
          'request_id': payload['action_request_id'],
        }),
      'match3_chest_open' => _post(
        '/api/games/match3/chests/${_safeLevel(payload['level_no'])}/open',
        const {},
      ),
      'match3_recovery_start' => _post(
        '/api/games/match3/${_safeId(payload['session_id'])}/recovery/start',
        const {},
      ),
      'match3_recovery_status' => _get(
        '/api/games/match3/recovery/${_safeTaskToken(payload['task_token'])}',
      ),
      'match3_recovery_consume' => _post(
        '/api/games/match3/recovery/${_safeTaskToken(payload['task_token'])}/consume',
        const {},
      ),
      'history' => _get(_historyPath(payload['game_type'])),
      'leaderboard' => _get('/api/games/leaderboard/today?limit=50'),
      _ => throw ApiException('GAME_ACTION_NOT_ALLOWED', '不支持的游戏操作'),
    };
  }

  String _safeId(Object? value) {
    final id = value?.toString() ?? '';
    if (!_uuid.hasMatch(id)) throw ApiException('INVALID_GAME_ID', '对局编号无效');
    return id;
  }

  String _safeTaskToken(Object? value) {
    final token = value?.toString() ?? '';
    if (!RegExp(r'^game_ad_[A-Za-z0-9]{24,64}$').hasMatch(token)) {
      throw ApiException('INVALID_GAME_AD_TASK', '复活任务编号无效');
    }
    return token;
  }

  int _safeLevel(Object? value) {
    final level = int.tryParse(value?.toString() ?? '');
    if (level == null || level < 1 || level > 100000) {
      throw ApiException('INVALID_MATCH3_LEVEL', '关卡编号无效');
    }
    return level;
  }

  String _historyPath(Object? value) {
    final gameType = value?.toString() ?? '';
    const allowed = {'rps', 'mine', 'battle', 'match3'};
    if (!allowed.contains(gameType)) return '/api/games/history?limit=20';
    return '/api/games/history?limit=20&game_type=$gameType';
  }

  Future<Map<String, dynamic>> _get(String path) {
    return ApiClient.instance.requestLegacy('GET', path);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) {
    return ApiClient.instance.requestLegacy('POST', path, body: body);
  }
}
