import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

enum _GameView { home, games, history, profile }

enum _GameKind { rps, mine, battle, match3 }

enum _ConversionDirection { aiToGame, gameToAi }

class GamePreviewPage extends StatefulWidget {
  const GamePreviewPage({
    super.key,
    this.battleRoundDuration = const Duration(seconds: 60),
    this.rpsRevealDuration = const Duration(seconds: 3),
    this.mineOpenDuration = const Duration(milliseconds: 1400),
  });

  final Duration battleRoundDuration;
  final Duration rpsRevealDuration;
  final Duration mineOpenDuration;

  @override
  State<GamePreviewPage> createState() => _GamePreviewPageState();
}

class _GamePreviewPageState extends State<GamePreviewPage>
    with TickerProviderStateMixin {
  static const Color _nordDark = Color(0xFF2E3440);
  static const Color _nordMid = Color(0xFF4C566A);
  static const Color _nordBlue = Color(0xFF5E81AC);
  static const Color _nordLightBlue = Color(0xFF88C0D0);
  static const Color _nordRed = Color(0xFFBF616A);
  static const Color _nordGreen = Color(0xFFA3BE8C);
  final Random _random = Random();
  final TextEditingController _battleStakeController = TextEditingController(
    text: '10',
  );

  _GameView _view = _GameView.home;
  _GameKind? _activeGame;
  bool _gameStarted = false;
  String _historyFilter = 'all';
  String _rpsChoice = 'rock';
  String? _rpsUserChoice;
  String? _rpsBotChoice;
  String? _rpsResult;
  String? _rpsOutcome;
  bool _rpsWaiting = false;
  int _rpsCountdown = 3;
  String? _openingMinePacketId;
  final Set<String> _claimedMinePacketIds = <String>{};
  int _mineDigit = 6;
  int _mineTotal = 10;
  int _rpsStake = 10;
  double _gamePoints = 126;
  double _convertibleGamePoints = 80;
  int _aiQuota = 320;
  int? _selectedRoom;
  bool _battleJoined = false;
  bool _battleSettled = false;
  double _joinedStake = 0;
  Set<int> _eliminatedRooms = <int>{};
  Timer? _battleTimer;
  Timer? _battleSettleTimer;
  late int _battleSeconds;
  DateTime? _battleClosesAt;
  late List<int> _match3Board;
  int _match3Level = 1;
  int _match3Score = 0;
  int _match3Moves = 15;
  int? _match3Selected;
  late final AnimationController _ambientController;
  late final AnimationController _rpsShakeController;

  final List<int> _roomPlayers = <int>[3, 2, 4, 2, 3, 2, 2, 3];
  final List<double> _roomStakes = <double>[31, 18, 46, 24, 37, 20, 25, 34];
  final List<_MinePacket> _minePackets = <_MinePacket>[
    _MinePacket(
      id: 'preview-mine-1',
      owner: '星河',
      mineDigit: 3,
      claimed: 3,
      claims: const [
        _MineClaim(owner: '青禾', amount: 0.68),
        _MineClaim(owner: '北辰', amount: 1.23, hit: true),
        _MineClaim(owner: '微光', amount: 1.57),
      ],
    ),
    _MinePacket(
      id: 'preview-mine-2',
      owner: '云帆',
      mineDigit: 7,
      claimed: 5,
      claims: const [
        _MineClaim(owner: '远山', amount: 0.92),
        _MineClaim(owner: '星河', amount: 1.81),
        _MineClaim(owner: '青禾', amount: 1.57, hit: true),
        _MineClaim(owner: '北辰', amount: 2.10),
        _MineClaim(owner: '微光', amount: 1.69),
      ],
    ),
  ];
  final List<_GameRecord> _records = <_GameRecord>[
    _GameRecord(
      kind: _GameKind.battle,
      game: '八房生存局',
      result: '胜利',
      detail: '淘汰1、6号房 · 存活2、3、4、5号房 · 你在4号房',
      stake: 10,
      payout: 14.5,
      fee: 0.5,
      net: 4.5,
      time: DateTime(2026, 7, 29, 10, 42),
    ),
    _GameRecord(
      kind: _GameKind.rps,
      game: '石头剪刀布',
      result: '平局',
      detail: '双方均出石头 · 退回投入10',
      stake: 10,
      payout: 10,
      fee: 0,
      net: 0,
      time: DateTime(2026, 7, 29, 9, 18),
    ),
    _GameRecord(
      kind: _GameKind.mine,
      game: '七人扫雷',
      result: '中雷',
      detail: '领取1.23 · 雷号3 · 赔付15',
      stake: 15,
      payout: 1.23,
      fee: 1.5,
      net: -13.77,
      mineHit: true,
      time: DateTime(2026, 7, 29, 8, 56),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _battleSeconds = max(1, widget.battleRoundDuration.inSeconds);
    _match3Board = List<int>.generate(64, (_) => _random.nextInt(6));
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _rpsShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
  }

  @override
  void dispose() {
    _battleTimer?.cancel();
    _battleSettleTimer?.cancel();
    _ambientController.dispose();
    _rpsShakeController.dispose();
    _battleStakeController.dispose();
    super.dispose();
  }

  String _points(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  int get _battleFreezeThreshold =>
      widget.battleRoundDuration.inSeconds > 5 ? 5 : 0;

  bool get _battleFrozen =>
      !_battleSettled &&
      _battleFreezeThreshold > 0 &&
      _battleSeconds <= _battleFreezeThreshold;

  int get _battleTotalSeconds =>
      max(1, (widget.battleRoundDuration.inMilliseconds / 1000).ceil());

  int get _battleElapsedSeconds => _battleTotalSeconds - _battleSeconds;

  bool get _battleCanSwitch =>
      !_battleSettled &&
      !_battleFrozen &&
      (_battleTotalSeconds <= 20 || _battleElapsedSeconds <= 20);

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _addRecord({
    required _GameKind kind,
    required String game,
    required String result,
    required String detail,
    required double stake,
    required double payout,
    double fee = 0,
    required double net,
    bool? mineHit,
  }) {
    _records.insert(
      0,
      _GameRecord(
        kind: kind,
        game: game,
        result: result,
        detail: detail,
        stake: stake,
        payout: payout,
        fee: fee,
        net: net,
        mineHit: mineHit,
        time: DateTime.now(),
      ),
    );
  }

  Future<void> _showConversion() async {
    final controller = TextEditingController(text: '10');
    var direction = _ConversionDirection.aiToGame;
    final request = await showDialog<_ConversionRequest>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final redeemable = min(_gamePoints, _convertibleGamePoints);
          final isAiToGame = direction == _ConversionDirection.aiToGame;
          return AlertDialog(
            title: const Text('AI额度与游戏积分兑换'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<_ConversionDirection>(
                    segments: const [
                      ButtonSegment(
                        value: _ConversionDirection.aiToGame,
                        label: Text(
                          'AI转积分',
                          key: ValueKey('conversion-ai-to-game'),
                        ),
                      ),
                      ButtonSegment(
                        value: _ConversionDirection.gameToAi,
                        label: Text(
                          '积分转AI',
                          key: ValueKey('conversion-game-to-ai'),
                        ),
                      ),
                    ],
                    selected: {direction},
                    showSelectedIcon: false,
                    onSelectionChanged: (selected) =>
                        setDialogState(() => direction = selected.first),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isAiToGame
                        ? '可用AI额度：$_aiQuota'
                        : '可兑回游戏积分：${_points(redeemable)}',
                    key: const ValueKey('conversion-available'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: isAiToGame ? '转为游戏积分' : '兑回AI额度',
                      suffixText: '1:1',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isAiToGame
                        ? '兑换后的积分可参与游戏，不可转赠或提现。'
                        : '只能兑回本人从AI额度转入后尚未参与游戏的本金，游戏到账不可兑回。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('conversion-confirm'),
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _ConversionRequest(
                    direction: direction,
                    amount: int.tryParse(controller.text.trim()),
                  ),
                ),
                child: const Text('确认兑换'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (request == null || !mounted) return;
    final amount = request.amount;
    if (amount == null || amount < 10) {
      _message('单次兑换数量至少为10');
      return;
    }
    if (request.direction == _ConversionDirection.aiToGame) {
      if (amount > _aiQuota) {
        _message('兑换数量不能超过可用AI额度');
        return;
      }
      setState(() {
        _aiQuota -= amount;
        _gamePoints += amount;
        _convertibleGamePoints += amount;
      });
      _message('已将$amount AI额度兑换为游戏积分');
      return;
    }
    final redeemable = min(_gamePoints, _convertibleGamePoints);
    if (amount > redeemable) {
      _message('最多可兑回${_points(redeemable)}，已参与游戏的积分不可兑回');
      return;
    }
    setState(() {
      _gamePoints -= amount;
      _convertibleGamePoints -= amount;
      _aiQuota += amount;
    });
    _message('已将$amount游戏积分兑回AI额度');
  }

  Future<void> _playRps() async {
    if (_rpsWaiting) return;
    final stake = _rpsStake.toDouble();
    if (_gamePoints < stake) {
      _message('游戏积分不足$_rpsStake');
      return;
    }
    const choices = <String>['rock', 'scissors', 'paper'];
    final userChoice = _rpsChoice;
    final bot = choices[_random.nextInt(choices.length)];
    setState(() {
      _gamePoints -= stake;
      _convertibleGamePoints = max(0.0, _convertibleGamePoints - stake);
      _rpsWaiting = true;
      _rpsCountdown = 1;
      _rpsUserChoice = userChoice;
      _rpsBotChoice = null;
      _rpsResult = null;
      _rpsOutcome = null;
    });
    _rpsShakeController.repeat(reverse: true);
    final shakeMs = min(
      1000,
      max(120, widget.rpsRevealDuration.inMilliseconds),
    );
    await Future<void>.delayed(Duration(milliseconds: shakeMs));
    if (!mounted) return;
    _rpsShakeController
      ..stop()
      ..reset();
    final draw = bot == userChoice;
    final win =
        (userChoice == 'rock' && bot == 'scissors') ||
        (userChoice == 'scissors' && bot == 'paper') ||
        (userChoice == 'paper' && bot == 'rock');
    final payout = draw ? stake : (win ? stake * 1.5 : 0.0);
    final net = payout - stake;
    final result = draw ? '平局' : (win ? '胜利' : '失败');
    final label = <String, String>{
      'rock': '石头',
      'scissors': '剪刀',
      'paper': '布',
    };
    setState(() {
      _gamePoints += payout;
      _rpsWaiting = false;
      _rpsBotChoice = bot;
      _rpsResult = '$result：你出${label[userChoice]}，对手出${label[bot]}';
      _rpsOutcome = draw ? 'draw' : (win ? 'win' : 'loss');
      _addRecord(
        kind: _GameKind.rps,
        game: '石头剪刀布',
        result: result,
        detail:
            '你出${label[userChoice]} · 对手出${label[bot]} · 到账${_points(payout)}',
        stake: stake,
        payout: payout,
        net: net,
      );
    });
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          draw
              ? Icons.horizontal_rule
              : win
              ? Icons.emoji_events
              : Icons.close,
          color: draw
              ? Colors.amber.shade700
              : win
              ? Colors.green
              : Colors.red,
        ),
        title: Text(
          draw
              ? '本局平局'
              : win
              ? '你赢了'
              : '对手获胜',
        ),
        content: Text(
          '你出${label[userChoice]}，对手出${label[bot]}；净盈亏${_points(net)}积分',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _openMineCreateDialog() async {
    var selectedTotal = _mineTotal;
    var selectedDigit = _mineDigit;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('发布扫雷红包'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('红包总积分'),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 10, label: Text('10')),
                  ButtonSegment(value: 50, label: Text('50')),
                  ButtonSegment(value: 100, label: Text('100')),
                ],
                selected: {selectedTotal},
                onSelectionChanged: (value) =>
                    setDialogState(() => selectedTotal = value.first),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: selectedDigit,
                decoration: const InputDecoration(labelText: '雷号'),
                items: List.generate(
                  10,
                  (digit) =>
                      DropdownMenuItem(value: digit, child: Text('$digit')),
                ),
                onChanged: (value) =>
                    setDialogState(() => selectedDigit = value ?? 0),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认发布'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    _mineTotal = selectedTotal;
    _mineDigit = selectedDigit;
    _createMinePacket();
  }

  void _createMinePacket() {
    final total = _mineTotal.toDouble();
    if (_gamePoints < total) {
      _message('创建红包需要$_mineTotal游戏积分');
      return;
    }
    setState(() {
      _gamePoints -= total;
      _convertibleGamePoints = max(0.0, _convertibleGamePoints - total);
      _minePackets.add(
        _MinePacket(
          id: 'preview-${DateTime.now().microsecondsSinceEpoch}',
          owner: '我',
          mineDigit: _mineDigit,
          total: total,
          claimed: 0,
          mine: true,
        ),
      );
    });
    _message('$_mineTotal积分红包已发出，固定由7人领取');
  }

  Future<void> _grabMine(_MinePacket packet) async {
    if (_openingMinePacketId != null) return;
    if (_claimedMinePacketIds.contains(packet.id) ||
        packet.claims.any((claim) => claim.isMine)) {
      _message('每人每个红包只能领取一次');
      return;
    }
    if (packet.claimed >= 7) {
      _message('这个红包已经抢完');
      return;
    }
    final liability = packet.total * 1.5;
    if (_gamePoints < liability) {
      _message('余额至少需要${_points(liability)}积分才能领取');
      return;
    }
    // 在动画和异步等待之前占用本局领取资格，拦住连续点击与重复请求。
    setState(() {
      _openingMinePacketId = packet.id;
      _claimedMinePacketIds.add(packet.id);
    });
    final opening = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _MineOpeningDialog(),
    );
    await Future<void>.delayed(widget.mineOpenDuration);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await opening;
    const samples = <double>[0.68, 0.92, 1.23, 1.57, 1.81, 2.1, 1.69];
    final amount = samples[_random.nextInt(samples.length)] * packet.total / 10;
    final cents = (amount * 100).round();
    final hit = cents % 10 == packet.mineDigit;
    final net = amount - (hit ? liability : 0);
    setState(() {
      _openingMinePacketId = null;
      packet.claimed += 1;
      packet.claims.add(
        _MineClaim(owner: '我', amount: amount, hit: hit, isMine: true),
      );
      _gamePoints += net;
      if (hit) {
        _convertibleGamePoints = max(0.0, _convertibleGamePoints - liability);
      }
      _addRecord(
        kind: _GameKind.mine,
        game: '七人扫雷',
        result: hit ? '中雷' : '领取',
        detail:
            '领取${_points(amount)} · 雷号${packet.mineDigit}${hit ? ' · 赔付${_points(liability)}' : ''}',
        stake: hit ? liability : 0,
        payout: amount,
        fee: hit ? 1.5 : 0,
        net: net,
        mineHit: hit,
      );
    });
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _MineResultDialog(
        amount: _points(amount),
        hit: hit,
        net: _points(net),
      ),
    );
    if (mounted) await _showMineDetails(packet);
  }

  Future<void> _showMineDetails(_MinePacket packet) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${packet.owner}的红包'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '7个红包共${_points(packet.total)}积分 · 雷号${packet.mineDigit}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              if (packet.claims.isEmpty)
                const Text('暂时还没有人领取')
              else
                ...packet.claims.map(
                  (claim) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Text('發')),
                    title: Text(claim.owner),
                    subtitle: const Text('刚刚领取'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${_points(claim.amount)} 积分'),
                        if (claim.hit)
                          const Text(
                            '中雷',
                            style: TextStyle(color: Color(0xFFFF4757)),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _joinBattle() {
    final stake = double.tryParse(_battleStakeController.text.trim());
    if (_selectedRoom == null) {
      _message('请先选择一个房间');
      return;
    }
    if (_battleSettled || _battleFrozen || _battleSeconds <= 0) {
      _message('本轮已经封盘，请进入下一轮');
      return;
    }
    if (stake == null ||
        stake < 1 ||
        stake > 1000 ||
        stake != stake.roundToDouble()) {
      _message('投入必须是1至1000的整数积分');
      return;
    }
    if (_gamePoints < stake) {
      _message('游戏积分不足');
      return;
    }
    setState(() {
      _battleJoined = true;
      _joinedStake = stake;
      _gamePoints -= stake;
      _convertibleGamePoints = max(0.0, _convertibleGamePoints - stake);
      _roomPlayers[_selectedRoom! - 1] += 1;
      _roomStakes[_selectedRoom! - 1] += stake;
    });
  }

  void _selectBattleRoom(int room) {
    if (_battleSettled || _battleFrozen) return;
    if (_battleJoined && !_battleCanSwitch) {
      _message('选房前20秒已结束，当前房间不能再切换');
      return;
    }
    if (_selectedRoom == room) return;
    final switching = _battleJoined;
    setState(() {
      if (_battleJoined && _selectedRoom != null) {
        _roomPlayers[_selectedRoom! - 1] -= 1;
        _roomStakes[_selectedRoom! - 1] -= _joinedStake;
        _roomPlayers[room - 1] += 1;
        _roomStakes[room - 1] += _joinedStake;
      }
      _selectedRoom = room;
    });
    if (switching) _message('已切换到$room号房，原投入未重复扣除');
  }

  void _settleBattle() {
    if (_battleSettled) return;
    _battleTimer?.cancel();
    _battleSettleTimer?.cancel();
    _ambientController.stop();
    final eliminated = _eliminatedRooms.length >= 2
        ? Set<int>.from(_eliminatedRooms)
        : _pickGhostRooms();
    final losingPool = List.generate(8, (index) => index)
        .where((index) => eliminated.contains(index + 1))
        .fold<double>(0, (sum, index) => sum + _roomStakes[index]);
    final winningStake = List.generate(8, (index) => index)
        .where((index) => !eliminated.contains(index + 1))
        .fold<double>(0, (sum, index) => sum + _roomStakes[index]);
    if (!_battleJoined) {
      setState(() {
        _battleSettled = true;
        _battleSeconds = 0;
        _eliminatedRooms = eliminated;
      });
      return;
    }
    final survived = !eliminated.contains(_selectedRoom);
    final profit = survived && winningStake > 0
        ? losingPool * 0.9 * _joinedStake / winningStake
        : 0.0;
    final payout = survived ? _joinedStake + profit : 0.0;
    final net = payout - _joinedStake;
    final eliminatedRooms = eliminated.toList()..sort();
    final survivingRooms = <int>[
      for (var room = 1; room <= 8; room++)
        if (!eliminated.contains(room)) room,
    ];
    setState(() {
      _battleSettled = true;
      _battleSeconds = 0;
      _eliminatedRooms = eliminated;
      _gamePoints += payout;
      _addRecord(
        kind: _GameKind.battle,
        game: '八房生存局',
        result: survived ? '胜利' : '淘汰',
        detail:
            '淘汰${eliminatedRooms.join('、')}号房 · 存活${survivingRooms.join('、')}号房 · 你在$_selectedRoom号房',
        stake: _joinedStake,
        payout: payout,
        fee: survived ? losingPool * 0.1 * _joinedStake / winningStake : 0,
        net: net,
      );
    });
  }

  void _nextBattleRound() {
    if (_battleJoined && _selectedRoom != null) {
      _roomPlayers[_selectedRoom! - 1] -= 1;
      _roomStakes[_selectedRoom! - 1] -= _joinedStake;
    }
    setState(() {
      _selectedRoom = null;
      _battleJoined = false;
      _battleSettled = false;
      _joinedStake = 0;
      _eliminatedRooms = <int>{};
      _battleStakeController.text = '10';
    });
    _ambientController.repeat(reverse: true);
    _startBattleTimer();
  }

  Future<void> _tapMatch3(int index) async {
    if (_match3Moves <= 0) return;
    if (_match3Selected == null) {
      setState(() => _match3Selected = index);
      return;
    }
    final previous = _match3Selected!;
    final adjacent =
        (previous ~/ 8 == index ~/ 8 && (previous - index).abs() == 1) ||
        (previous - index).abs() == 8;
    if (!adjacent) {
      setState(() => _match3Selected = index);
      return;
    }
    setState(() {
      final value = _match3Board[previous];
      _match3Board[previous] = _match3Board[index];
      _match3Board[index] = value;
      _match3Selected = null;
      _match3Moves -= 1;
      _match3Score += 30;
      for (var offset = 0; offset < 3; offset++) {
        _match3Board[(index + offset) % 64] = _random.nextInt(6);
      }
    });
    if (_match3Score >= 150) {
      final completedLevel = _match3Level;
      setState(() {
        _gamePoints += 1;
        _match3Level += 1;
        _match3Score = 0;
        _match3Moves = 15;
        _match3Board = List<int>.generate(64, (_) => _random.nextInt(6));
        _addRecord(
          kind: _GameKind.match3,
          game: '宝石消消乐',
          result: '通关',
          detail: '第$completedLevel关首次通关 · 奖励1积分',
          stake: 0,
          payout: 1,
          net: 1,
        );
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.emoji_events, color: Color(0xFF2B73B7)),
          title: Text('第$completedLevel关通关'),
          content: const Text('首次通关奖励1积分'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('继续'),
            ),
          ],
        ),
      );
    } else if (_match3Moves == 0 && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.hourglass_empty),
          title: const Text('步数用完了'),
          content: const Text('完整观看激励广告可增加5步继续本关'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('结束本关'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _message('检查版未连接真实广告，本次不增加步数');
              },
              child: const Text('真实广告未接通'),
            ),
          ],
        ),
      );
    }
  }

  void _startBattleTimer() {
    _battleTimer?.cancel();
    _battleSettleTimer?.cancel();
    _battleClosesAt = DateTime.now().add(widget.battleRoundDuration);
    if (mounted) {
      setState(() {
        _battleSeconds = max(
          1,
          (widget.battleRoundDuration.inMilliseconds / 1000).ceil(),
        );
      });
    }
    _battleTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final remainingMs = _battleClosesAt!
          .difference(DateTime.now())
          .inMilliseconds;
      final remaining = max(0, (remainingMs / 1000).ceil());
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (remaining != _battleSeconds) {
        setState(() {
          _battleSeconds = remaining;
          if (_battleFreezeThreshold > 0 &&
              remaining <= _battleFreezeThreshold &&
              _eliminatedRooms.isEmpty) {
            _eliminatedRooms = _pickGhostRooms();
          }
        });
      }
      if (remaining <= 0) {
        timer.cancel();
        _settleBattle();
      }
    });
    _battleSettleTimer = Timer(widget.battleRoundDuration, _settleBattle);
  }

  Set<int> _pickGhostRooms() {
    final rooms = <int>{};
    final count = 2 + _random.nextInt(2);
    while (rooms.length < count) {
      rooms.add(_random.nextInt(8) + 1);
    }
    return rooms;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: const NavigationBarThemeData(
          height: 66,
          backgroundColor: Color(0xFFF7FAFD),
          indicatorColor: Color(0xFFD8E7F4),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, color: _nordDark),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nord 游戏空间'),
          backgroundColor: _nordDark,
          foregroundColor: Colors.white,
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFD8E7F4), Color(0xFFEAF2F8), Color(0xFFC7DCEB)],
            ),
          ),
          child: Column(
            children: [
              _walletBar(),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: _currentView(),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _GameView.values.indexOf(_view),
          onDestinationSelected: (index) =>
              _selectGameView(_GameView.values[index]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: _nordBlue),
              selectedIcon: Icon(Icons.home, color: _nordBlue),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.sports_esports_outlined, color: _nordBlue),
              selectedIcon: Icon(Icons.sports_esports, color: _nordBlue),
              label: '游戏大厅',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined, color: _nordBlue),
              selectedIcon: Icon(Icons.receipt_long, color: _nordBlue),
              label: '我的记录',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline, color: _nordBlue),
              selectedIcon: Icon(Icons.person, color: _nordBlue),
              label: '个人中心',
            ),
          ],
        ),
      ),
    );
  }

  void _selectGameView(_GameView view) {
    if (_activeGame == _GameKind.battle) {
      _ambientController.stop();
    }
    setState(() {
      _view = view;
      if (view == _GameView.games) {
        _activeGame = null;
        _gameStarted = false;
      }
    });
  }

  Widget _walletBar() {
    return ColoredBox(
      color: const Color(0xF23B4252),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.toll_outlined, color: _nordLightBlue),
            const SizedBox(width: 8),
            const Text('游戏积分', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 6),
            Text(
              _points(_gamePoints),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _showConversion,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('额度兑换'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD8E7F4),
                side: const BorderSide(color: Color(0xFF81A1C1)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _currentView() {
    return switch (_view) {
      _GameView.home => _homeView(),
      _GameView.games => _gameHub(),
      _GameView.history => _historyView(),
      _GameView.profile => _profileView(),
    };
  }

  Widget _gameHub() {
    if (_activeGame == null) return _gameHall();
    if (!_gameStarted) return _gameSelection();
    return _gamePanel();
  }

  Widget _homeView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Text(
          '选择你的游戏',
          style: TextStyle(
            color: _nordDark,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          '先进入专属选择页，确认规则后再开始对局',
          style: TextStyle(color: _nordMid, fontSize: 13),
        ),
        const SizedBox(height: 18),
        _homeGameCard(
          kind: _GameKind.battle,
          icon: Icons.meeting_room_outlined,
          title: '大逃杀',
          subtitle: '八房生存 · 随机淘汰2至3房',
          colors: const [Color(0xFF2E3440), Color(0xFF5E81AC)],
        ),
        const SizedBox(height: 12),
        _homeGameCard(
          kind: _GameKind.rps,
          icon: Icons.back_hand_outlined,
          title: '石头剪刀布',
          subtitle: '左右摇拳 · 定格揭晓胜负',
          colors: const [Color(0xFF3B4252), Color(0xFF81A1C1)],
        ),
        const SizedBox(height: 12),
        _homeGameCard(
          kind: _GameKind.mine,
          icon: Icons.scatter_plot_outlined,
          title: '扫雷',
          subtitle: '拆红包 · 领取明细',
          colors: const [Color(0xFF434C5E), Color(0xFF88C0D0)],
        ),
      ],
    );
  }

  Widget _homeGameCard({
    required _GameKind kind,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
  }) {
    return Container(
      height: 116,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332E3440),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openSelection(kind),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0x26FFFFFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFFD8E7F4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gameHall() {
    const games = <(_GameKind, IconData, String, String)>[
      (_GameKind.battle, Icons.meeting_room_outlined, '大逃杀', '八房生存局'),
      (_GameKind.rps, Icons.back_hand_outlined, '石头剪刀布', '经典10积分场'),
      (_GameKind.mine, Icons.scatter_plot_outlined, '扫雷', '七人红包雷'),
      (_GameKind.match3, Icons.grid_view_rounded, '宝石消消乐', '闯关与宝箱'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Text(
          '游戏大厅',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 680 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: games
                  .map(
                    (game) => SizedBox(
                      width: width,
                      child: _hallGameCard(
                        kind: game.$1,
                        icon: game.$2,
                        title: game.$3,
                        subtitle: game.$4,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _hallGameCard({
    required _GameKind kind,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      color: const Color(0xF7FFFFFF),
      elevation: 3,
      shadowColor: const Color(0x332E3440),
      child: ListTile(
        minTileHeight: 86,
        leading: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFD8E7F4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _nordBlue),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, color: _nordBlue),
        onTap: () => _openSelection(kind),
      ),
    );
  }

  Widget _gameSelection() {
    final kind = _activeGame!;
    final (title, subtitle, icon, rule) = switch (kind) {
      _GameKind.battle => (
        '大逃杀 · 八房生存',
        '前20秒可切换房间，最后5秒锁定并揭晓杀手目标',
        Icons.meeting_room_outlined,
        '随机淘汰2至3个房间。幸存者返还本金，并按个人投入占全部幸存投入的比例分配扣除10%后的失败池。',
      ),
      _GameKind.rps => (
        '石头剪刀布',
        '玩家选择出拳，对手随机出拳',
        Icons.back_hand_outlined,
        '投入可选10、50或100积分；获胜总到账为投入的1.5倍，平局退回本金。',
      ),
      _GameKind.mine => (
        '七人扫雷',
        '选择雷号发包或参与现有红包',
        Icons.scatter_plot_outlined,
        '每人每个红包只能拆一次，发布者本人也可领取；详情只展示领取金额、时间和中雷状态。',
      ),
      _GameKind.match3 => (
        '宝石消消乐',
        '完成关卡并开启里程碑宝箱',
        Icons.grid_view_rounded,
        '每关首次通关奖励1积分；检查版不提供广告复活，也不会伪造广告奖励。',
      ),
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _activeGame = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('返回游戏大厅'),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_nordDark, _nordBlue]),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x442E3440),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: _nordLightBlue, size: 42),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(subtitle, style: const TextStyle(color: Color(0xFFD8E7F4))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: const Color(0xF7FFFFFF),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本局规则',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  rule,
                  style: const TextStyle(height: 1.55, color: _nordMid),
                ),
              ],
            ),
          ),
        ),
        if (kind == _GameKind.rps) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '本局投入',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 10, label: Text('10积分')),
                      ButtonSegment(value: 50, label: Text('50积分')),
                      ButtonSegment(value: 100, label: Text('100积分')),
                    ],
                    selected: {_rpsStake},
                    onSelectionChanged: (value) =>
                        setState(() => _rpsStake = value.first),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const ValueKey('game-enter-button'),
          onPressed: _enterSelectedGame,
          icon: const Icon(Icons.play_arrow),
          label: const Text('进入对局'),
          style: FilledButton.styleFrom(backgroundColor: _nordBlue),
        ),
      ],
    );
  }

  void _openSelection(_GameKind kind) {
    setState(() {
      _view = _GameView.games;
      _activeGame = kind;
      _gameStarted = false;
    });
  }

  void _enterSelectedGame() {
    final kind = _activeGame;
    if (kind == null) return;
    setState(() => _gameStarted = true);
    if (kind == _GameKind.battle) {
      _ambientController.repeat(reverse: true);
      if (_battleClosesAt == null) _startBattleTimer();
    }
  }

  Widget _gamePanel() {
    final title = switch (_activeGame!) {
      _GameKind.rps => '石头剪刀布',
      _GameKind.mine => '七人扫雷',
      _GameKind.battle => '八房生存局',
      _GameKind.match3 => '宝石消消乐',
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回选择页',
                onPressed: () {
                  if (_activeGame == _GameKind.battle) {
                    _ambientController.stop();
                  }
                  setState(() => _gameStarted = false);
                },
                icon: const Icon(Icons.arrow_back, color: _nordBlue),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD8E7F4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '对局中',
                  style: TextStyle(fontSize: 11, color: _nordBlue),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_activeGame!) {
            _GameKind.rps => _rpsGame(),
            _GameKind.mine => _mineGame(),
            _GameKind.battle => _battleGame(),
            _GameKind.match3 => _match3Game(),
          },
        ),
      ],
    );
  }

  Widget _rpsGame() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _ruleStrip('本局投入$_rpsStake积分；获胜到账1.5倍，平局退回本金。'),
        const SizedBox(height: 12),
        _rpsArena(),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'rock',
              icon: Icon(Icons.fitness_center),
              label: Text('石头'),
            ),
            ButtonSegment(
              value: 'scissors',
              icon: Icon(Icons.content_cut),
              label: Text('剪刀'),
            ),
            ButtonSegment(
              value: 'paper',
              icon: Icon(Icons.pan_tool_outlined),
              label: Text('布'),
            ),
          ],
          selected: {_rpsChoice},
          onSelectionChanged: _rpsWaiting
              ? null
              : (value) => setState(() => _rpsChoice = value.first),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _rpsWaiting ? null : _playRps,
          icon: Icon(_rpsWaiting ? Icons.hourglass_top : Icons.play_arrow),
          label: Text(_rpsWaiting ? '等待对手出拳' : '投入$_rpsStake积分并出拳'),
        ),
        if (_rpsResult != null) ...[
          const SizedBox(height: 12),
          _resultStrip(_rpsResult!),
        ],
      ],
    );
  }

  Widget _rpsArena() {
    return Container(
      height: 230,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD7DCE2)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: _fighterPanel(
                  title: '你',
                  choice: _rpsUserChoice ?? _rpsChoice,
                  background: const Color(0xFFDDEBFA),
                  foreground: const Color(0xFF2869B2),
                  isUser: true,
                ),
              ),
              Expanded(
                child: _fighterPanel(
                  title: '对手',
                  choice: _rpsBotChoice,
                  background: const Color(0xFFFBE3DF),
                  foreground: const Color(0xFFB55042),
                  waiting: _rpsWaiting,
                  isUser: false,
                ),
              ),
            ],
          ),
          AnimatedScale(
            scale: _rpsOutcome == null ? 0.94 : 1.08,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            child: Container(
              constraints: const BoxConstraints(minWidth: 58, minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: switch (_rpsOutcome) {
                  'win' => _nordGreen,
                  'loss' => _nordRed,
                  'draw' => const Color(0xFFEBCB8B),
                  _ => _nordDark,
                },
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x332E3440), blurRadius: 10),
                ],
              ),
              child: Text(
                _rpsWaiting
                    ? '$_rpsCountdown'
                    : switch (_rpsOutcome) {
                        'win' => '胜',
                        'loss' => '负',
                        'draw' => '平',
                        _ => 'VS',
                      },
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fighterPanel({
    required String title,
    required String? choice,
    required Color background,
    required Color foreground,
    required bool isUser,
    bool waiting = false,
  }) {
    final scale = switch (_rpsOutcome) {
      'win' => isUser ? 1.16 : 0.82,
      'loss' => isUser ? 0.82 : 1.16,
      _ => 1.0,
    };
    return ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            AnimatedBuilder(
              animation: _rpsShakeController,
              builder: (context, child) {
                final direction = isUser ? 1.0 : -1.0;
                final offset = waiting
                    ? sin(_rpsShakeController.value * pi * 6) * 8 * direction
                    : 0.0;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    waiting || choice == null ? '?' : _rpsChoiceGlyph(choice),
                    key: ValueKey('$waiting-$choice'),
                    style: TextStyle(fontSize: 64, color: foreground),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Text(
              waiting
                  ? '准备中'
                  : (choice == null ? '尚未揭晓' : _rpsChoiceLabel(choice)),
              style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  String _rpsChoiceGlyph(String choice) => switch (choice) {
    'rock' => '✊',
    'scissors' => '✌',
    _ => '✋',
  };

  String _rpsChoiceLabel(String choice) => switch (choice) {
    'rock' => '石头',
    'scissors' => '剪刀',
    _ => '布',
  };

  Widget _mineGame() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _ruleStrip('选择10、50或100积分与雷号发布红包。最早发布优先；7天未领完时，剩余积分自动退回。'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _openMineCreateDialog,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('发布红包'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.schedule, size: 17, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text('按发布时间：从早到晚', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        ..._minePackets.map(_minePacketTile),
      ],
    );
  }

  Widget _minePacketTile(_MinePacket packet) {
    final myClaims = packet.claims.where((claim) => claim.isMine).toList();
    final myClaim = myClaims.isEmpty ? null : myClaims.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(
              width: 92,
              height: packet.claims.isEmpty ? 112 : 154,
              color: const Color(0xFFD94A3F),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.mail, size: 58, color: Color(0xFFFFC66D)),
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFE0A3),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${packet.mineDigit}',
                      style: const TextStyle(
                        color: Color(0xFF9A331F),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${packet.owner} · 金额${_points(packet.total)} 雷号${packet.mineDigit}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${packet.claimed}/7 已领取 · 中雷赔付${_points(packet.total * 1.5)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: packet.claimed / 7,
                      minHeight: 5,
                      color: const Color(0xFFD94A3F),
                      backgroundColor: const Color(0xFFF3DDD8),
                    ),
                    if (packet.claims.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: packet.claims
                            .map(
                              (claim) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: claim.hit
                                      ? const Color(0xFFFFE5E2)
                                      : const Color(0xFFF1F3F5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${claim.owner} ${_points(claim.amount)}${claim.hit ? ' · 中雷' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: claim.hit
                                        ? const Color(0xFFB54848)
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton.tonalIcon(
                onPressed: myClaim != null || packet.claimed >= 7
                    ? () => _showMineDetails(packet)
                    : _openingMinePacketId != null
                    ? null
                    : () => _grabMine(packet),
                icon: Icon(
                  myClaim != null || packet.claimed >= 7
                      ? Icons.manage_search
                      : Icons.touch_app_outlined,
                  size: 18,
                ),
                label: Text(
                  myClaim != null || packet.claimed >= 7 ? '查看详情' : '拆红包',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _battleGame() {
    final totalSeconds = _battleTotalSeconds;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 10,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (context, index) => Container(
              width: 116,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFD7E4F2)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '第${index + 1}近局\n淘汰 ${(index % 8) + 1}、${((index + 3) % 8) + 1}号房',
                style: const TextStyle(fontSize: 11, height: 1.45),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _ruleStrip('每轮只能选择一个房间，封盘后随机淘汰2至3房；幸存者返还本金并按投入占比分配90%失败池。'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D4E82),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: _battleFrozen && _battleSeconds.isEven ? 1.25 : 1,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _battleFrozen ? _nordRed : const Color(0xFF376C98),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _battleSettled ? '0' : '$_battleSeconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _battleSettled
                          ? '本轮已结算'
                          : _battleFrozen
                          ? '杀手进房 · 最后$_battleSeconds秒锁定'
                          : _battleCanSwitch
                          ? '选房阶段 · 前20秒可切换'
                          : '等待封盘 · 房间已固定',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    LinearProgressIndicator(
                      value: _battleSettled ? 0 : _battleSeconds / totalSeconds,
                      minHeight: 6,
                      color: const Color(0xFF79C8FF),
                      backgroundColor: const Color(0xFF2E6D9F),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _battleStakeController,
                enabled: !_battleJoined && !_battleSettled && !_battleFrozen,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '投入积分',
                  suffixText: '1-1000',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _battleJoined || _battleSettled || _battleFrozen
                  ? null
                  : _joinBattle,
              child: Text(_battleJoined ? '已加入' : '确认加入'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _battleScene(),
        if (_battleJoined) ...[
          const SizedBox(height: 12),
          if (!_battleSettled)
            _resultStrip(
              _battleFrozen
                  ? '画面已定格 · 杀手进入${(_eliminatedRooms.toList()..sort()).join('、')}号房'
                  : _battleCanSwitch
                  ? '已加入$_selectedRoom号房 · 前20秒内可以切换'
                  : '已锁定$_selectedRoom号房 · 等待本轮结算',
            )
          else ...[
            _resultStrip('淘汰房间：${_eliminatedRooms.toList()..sort()}'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _nextBattleRound,
              icon: const Icon(Icons.refresh),
              label: const Text('进入下一轮'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _battleScene() {
    const positions = <Offset>[
      Offset(0.03, 0.16),
      Offset(0.56, 0.17),
      Offset(0.08, 0.36),
      Offset(0.51, 0.37),
      Offset(0.03, 0.56),
      Offset(0.56, 0.57),
      Offset(0.08, 0.76),
      Offset(0.51, 0.77),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final sceneWidth = constraints.maxWidth;
        final sceneHeight = (sceneWidth * 1.45).clamp(560.0, 720.0);
        final roomWidth = (sceneWidth * 0.40).clamp(142.0, 230.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: sceneHeight,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _SkyRealmPainter()),
                ),
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: CustomPaint(
                          painter: _GhostPainter(active: _battleFrozen),
                        ),
                      ),
                      Text(
                        _battleFrozen ? '幽灵完成选择' : '幽灵正在巡游',
                        style: const TextStyle(
                          color: Color(0xFFD8F2FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                for (var index = 0; index < positions.length; index++)
                  Positioned(
                    left: positions[index].dx * (sceneWidth - roomWidth),
                    top: positions[index].dy * (sceneHeight - 102),
                    width: roomWidth,
                    height: 96,
                    child: _battleRoom(index + 1),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _battleRoom(int room) {
    final index = room - 1;
    final selected = room == _selectedRoom;
    final ghostLocked = _eliminatedRooms.contains(room);
    final disabled =
        _battleSettled || _battleFrozen || (_battleJoined && !_battleCanSwitch);
    final borderColor = ghostLocked
        ? _nordRed
        : selected
        ? const Color(0xFFFFD166)
        : const Color(0xFF75B8E8);
    return AnimatedBuilder(
      animation: _ambientController,
      builder: (context, child) {
        final pulse = _ambientController.value;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('battle-room-$room'),
            borderRadius: BorderRadius.circular(7),
            onTap: disabled ? null : () => _selectBattleRoom(room),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
              decoration: BoxDecoration(
                color: ghostLocked
                    ? const Color(0xEA552F3A)
                    : selected
                    ? const Color(0xE6376F9D)
                    : const Color(0xD9184668),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: borderColor,
                  width: ghostLocked ? 2.5 + pulse : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ghostLocked
                        ? _nordRed.withValues(alpha: 0.35 + pulse * 0.35)
                        : const Color(
                            0xFF88C0D0,
                          ).withValues(alpha: 0.12 + pulse * 0.12),
                    blurRadius: ghostLocked ? 12 + pulse * 8 : 7 + pulse * 4,
                    spreadRadius: ghostLocked ? 1 + pulse * 2 : 0,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 42,
                        height: 66,
                        child: CustomPaint(
                          painter: _CultivatorPainter(accent: borderColor),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$room号房',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_roomPlayers[index]}人 · ${_points(_roomStakes[index])}积分',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD6EAF8),
                                fontSize: 10,
                              ),
                            ),
                            if (ghostLocked)
                              const Text(
                                '杀手进入',
                                style: TextStyle(
                                  color: Color(0xFFFFC8CE),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            else if (selected)
                              const Text(
                                '已选择',
                                style: TextStyle(
                                  color: Color(0xFFFFE09A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (ghostLocked)
                    Positioned(
                      right: 1 + (1 - pulse) * 14,
                      top: 1,
                      child: Opacity(
                        opacity: 0.55 + pulse * 0.45,
                        child: Transform.rotate(
                          angle: -0.18,
                          child: const Icon(
                            Icons.directions_walk,
                            color: Color(0xFFFF9AA5),
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _match3Game() {
    const colors = <Color>[
      Color(0xFFEC5D69),
      Color(0xFF49A7E8),
      Color(0xFF52B788),
      Color(0xFFF2BD42),
      Color(0xFF9A6DE0),
      Color(0xFFEF8B45),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            _match3Stat('关卡', '$_match3Level'),
            const SizedBox(width: 8),
            _match3Stat('得分', '$_match3Score/150'),
            const SizedBox(width: 8),
            _match3Stat('剩余步数', '$_match3Moves'),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFB8D3E8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(6),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: 64,
                  itemBuilder: (context, index) => InkWell(
                    onTap: () => _tapMatch3(index),
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: colors[_match3Board[index]],
                        borderRadius: BorderRadius.circular(6),
                        border: _match3Selected == index
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ruleStrip('相邻宝石交换形成三连；每关仅首次通关奖励1积分，每10关出现宝箱。'),
      ],
    );
  }

  Widget _match3Stat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD7E4F2)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7E91)),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyView() {
    const filters = <(String, String)>[
      ('all', '全部'),
      ('石头剪刀布', '石头剪刀布'),
      ('七人扫雷', '七人扫雷'),
      ('八房生存局', '八房生存局'),
      ('宝石消消乐', '宝石消消乐'),
    ];
    final records = _records
        .where(
          (record) => _historyFilter == 'all' || record.game == _historyFilter,
        )
        .take(20)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '最近20局',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '共${records.length}局',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: filters
              .map(
                (filter) => ChoiceChip(
                  label: Text(filter.$2),
                  selected: _historyFilter == filter.$1,
                  onSelected: (_) => setState(() => _historyFilter = filter.$1),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 44),
            child: Center(child: Text('还没有完成的对局')),
          )
        else
          for (final record in records) _historyTile(record),
      ],
    );
  }

  Widget _historyTile(_GameRecord record) {
    final positive = record.net > 0;
    final moneyColor = positive
        ? const Color(0xFF16815F)
        : (record.net < 0 ? const Color(0xFFB54848) : Colors.grey.shade700);
    final icon = switch (record.kind) {
      _GameKind.rps => Icons.back_hand_outlined,
      _GameKind.mine => Icons.redeem_outlined,
      _GameKind.battle => Icons.auto_awesome_outlined,
      _GameKind.match3 => Icons.grid_view_rounded,
    };
    return Card(
      key: ValueKey('game-record-${record.time.microsecondsSinceEpoch}'),
      margin: const EdgeInsets.only(top: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFD7E4F2)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 174),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FD),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, size: 19, color: const Color(0xFF2767A8)),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.game,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _timeText(record.time),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF718096),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: moneyColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      record.kind == _GameKind.mine
                          ? (record.mineHit == true
                                ? '中雷 · ${record.result}'
                                : '未中雷 · ${record.result}')
                          : record.result,
                      style: TextStyle(
                        color: moneyColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                record.detail,
                style: const TextStyle(
                  color: Color(0xFF4A5A6A),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F9FD),
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
                child: Row(
                  children: [
                    _historyMetric('投入', record.stake),
                    _historyMetric('到账', record.payout),
                    _historyMetric('手续费', record.fee),
                    _historyMetric(
                      '净盈亏',
                      record.net,
                      color: moneyColor,
                      signed: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyMetric(
    String label,
    double value, {
    Color color = const Color(0xFF25374A),
    bool signed = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: 10, color: Color(0xFF7C8B9A)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${signed && value > 0 ? '+' : ''}${_points(value)}',
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileView() {
    final todayNet = _records.fold<double>(
      0,
      (sum, record) => sum + record.net,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Text(
          '个人中心',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_nordDark, _nordBlue]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 27,
                backgroundColor: Color(0xFFD8E7F4),
                child: Icon(Icons.person, color: _nordBlue),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'preview_user',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '今日盈亏 ${todayNet >= 0 ? '+' : ''}${_points(todayNet)}',
                      style: TextStyle(
                        color: todayNet >= 0 ? _nordGreen : _nordRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xF7FFFFFF),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _profileMetric('游戏积分', _points(_gamePoints)),
                const Divider(height: 24),
                _profileMetric(
                  '可兑回积分',
                  _points(min(_gamePoints, _convertibleGamePoints)),
                ),
                const Divider(height: 24),
                _profileMetric('AI额度', '$_aiQuota'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _showConversion,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('AI额度与游戏积分兑换'),
          style: FilledButton.styleFrom(backgroundColor: _nordBlue),
        ),
        const SizedBox(height: 14),
        const Card(
          color: Color(0xF7FFFFFF),
          child: ListTile(
            leading: Icon(Icons.verified_user_outlined, color: _nordBlue),
            title: Text('账户规则'),
            subtitle: Text('积分与额度不可提现、不可转赠；所有结算以服务端记录为准。'),
          ),
        ),
      ],
    );
  }

  Widget _profileMetric(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: _nordMid)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }

  String _timeText(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${time.month}月${time.day}日 $hour:$minute';
  }

  Widget _ruleStrip(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FD),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF284D7C))),
    );
  }

  Widget _resultStrip(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD7DCE2)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _SkyRealmPainter extends CustomPainter {
  const _SkyRealmPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF082D4B), Color(0xFF176A9D), Color(0xFFBDE6F2)],
        stops: [0, 0.58, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    final moon = Paint()
      ..color = const Color(0xFFDDF5FF).withValues(alpha: 0.75);
    canvas.drawCircle(
      Offset(size.width * 0.77, size.height * 0.11),
      size.width * 0.075,
      moon,
    );
    final moonShade = Paint()
      ..color = const Color(0xFF8CC9DF).withValues(alpha: 0.35);
    canvas.drawCircle(
      Offset(size.width * 0.80, size.height * 0.095),
      size.width * 0.061,
      moonShade,
    );

    final farMountain = Paint()
      ..color = const Color(0xFF316F91).withValues(alpha: 0.55);
    final farPath = Path()
      ..moveTo(0, size.height * 0.52)
      ..lineTo(size.width * 0.18, size.height * 0.34)
      ..lineTo(size.width * 0.31, size.height * 0.49)
      ..lineTo(size.width * 0.48, size.height * 0.27)
      ..lineTo(size.width * 0.66, size.height * 0.49)
      ..lineTo(size.width * 0.82, size.height * 0.31)
      ..lineTo(size.width, size.height * 0.52)
      ..close();
    canvas.drawPath(farPath, farMountain);

    final ridge = Paint()
      ..color = const Color(0xFF164D70).withValues(alpha: 0.76);
    final ridgePath = Path()
      ..moveTo(0, size.height * 0.68)
      ..quadraticBezierTo(
        size.width * 0.18,
        size.height * 0.49,
        size.width * 0.36,
        size.height * 0.65,
      )
      ..quadraticBezierTo(
        size.width * 0.61,
        size.height * 0.42,
        size.width,
        size.height * 0.66,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(ridgePath, ridge);

    final mist = Paint()
      ..color = const Color(0xFFE4F7FA).withValues(alpha: 0.25);
    for (var index = 0; index < 7; index++) {
      final x = size.width * (0.05 + index * 0.16);
      final y = size.height * (0.46 + (index.isEven ? 0.03 : 0));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: size.width * 0.27,
          height: size.height * 0.065,
        ),
        mist,
      );
    }

    final water = Paint()
      ..color = const Color(0xFF79C8DC).withValues(alpha: 0.22);
    for (var index = 0; index < 5; index++) {
      final y = size.height * (0.74 + index * 0.045);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.12, y, size.width * 0.76, 1.5),
          const Radius.circular(1),
        ),
        water,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkyRealmPainter oldDelegate) => false;
}

class _GhostPainter extends CustomPainter {
  const _GhostPainter({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..color = (active ? const Color(0xFF90EAFF) : const Color(0xFF7AB9DB))
          .withValues(alpha: active ? 0.35 : 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.48),
      size.width * 0.42,
      glow,
    );

    final robe = Paint()
      ..color = active ? const Color(0xFFB8F4FF) : const Color(0xFF9AC8DF);
    final body = Path()
      ..moveTo(size.width * 0.50, size.height * 0.30)
      ..quadraticBezierTo(
        size.width * 0.23,
        size.height * 0.48,
        size.width * 0.18,
        size.height * 0.88,
      )
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.76,
        size.width * 0.50,
        size.height * 0.92,
      )
      ..quadraticBezierTo(
        size.width * 0.66,
        size.height * 0.77,
        size.width * 0.82,
        size.height * 0.88,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.48,
        size.width * 0.50,
        size.height * 0.30,
      )
      ..close();
    canvas.drawPath(body, robe);
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.28),
      size.width * 0.18,
      robe,
    );

    final face = Paint()..color = const Color(0xFF0A4266);
    canvas.drawCircle(Offset(size.width * 0.44, size.height * 0.27), 2.4, face);
    canvas.drawCircle(Offset(size.width * 0.56, size.height * 0.27), 2.4, face);
  }

  @override
  bool shouldRepaint(covariant _GhostPainter oldDelegate) =>
      oldDelegate.active != active;
}

class _CultivatorPainter extends CustomPainter {
  const _CultivatorPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final hair = Paint()..color = const Color(0xFF102B3D);
    final skin = Paint()..color = const Color(0xFFF3D2B5);
    final robe = Paint()..color = accent.withValues(alpha: 0.92);
    final sash = Paint()..color = const Color(0xFFE8F7FF);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.25),
        width: size.width * 0.48,
        height: size.width * 0.42,
      ),
      hair,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.28),
      size.width * 0.17,
      skin,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.18,
          size.height * 0.40,
          size.width * 0.64,
          size.height * 0.48,
        ),
        const Radius.circular(8),
      ),
      robe,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.61,
        size.width * 0.64,
        size.height * 0.07,
      ),
      sash,
    );
    canvas.drawCircle(Offset(size.width * 0.44, size.height * 0.28), 1.3, hair);
    canvas.drawCircle(Offset(size.width * 0.56, size.height * 0.28), 1.3, hair);
  }

  @override
  bool shouldRepaint(covariant _CultivatorPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class _MineOpeningDialog extends StatelessWidget {
  const _MineOpeningDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 150,
                height: 184,
                decoration: BoxDecoration(
                  color: const Color(0xFFD94A3F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned(
                      top: 34,
                      child: Icon(
                        Icons.mail,
                        size: 92,
                        color: Color(0xFFFFC66D),
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFE0A3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.toll, color: Color(0xFF9A331F)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '正在拆红包',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const SizedBox(width: 150, child: LinearProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}

class _MineResultDialog extends StatelessWidget {
  const _MineResultDialog({
    required this.amount,
    required this.hit,
    required this.net,
  });

  final String amount;
  final bool hit;
  final String net;

  @override
  Widget build(BuildContext context) {
    final color = hit ? const Color(0xFFB54848) : const Color(0xFF16815F);
    return AlertDialog(
      icon: Icon(
        hit ? Icons.crisis_alert : Icons.redeem,
        size: 54,
        color: color,
      ),
      title: Text(hit ? '中雷' : '安全'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$amount 积分',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(hit ? '本次中雷，亏损 ${net.replaceFirst('-', '')} 积分' : '本次领取安全'),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.manage_search),
          label: const Text('查看详情'),
        ),
      ],
    );
  }
}

class _MinePacket {
  _MinePacket({
    required this.id,
    required this.owner,
    required this.mineDigit,
    required this.claimed,
    this.total = 10,
    this.mine = false,
    List<_MineClaim>? claims,
  }) : claims = List<_MineClaim>.from(claims ?? const []);

  final String id;
  final String owner;
  final int mineDigit;
  final double total;
  int claimed;
  final bool mine;
  final List<_MineClaim> claims;
}

class _MineClaim {
  const _MineClaim({
    required this.owner,
    required this.amount,
    this.hit = false,
    this.isMine = false,
  });

  final String owner;
  final double amount;
  final bool hit;
  final bool isMine;
}

class _ConversionRequest {
  const _ConversionRequest({required this.direction, required this.amount});

  final _ConversionDirection direction;
  final int? amount;
}

class _GameRecord {
  const _GameRecord({
    required this.kind,
    required this.game,
    required this.result,
    required this.detail,
    required this.stake,
    required this.payout,
    required this.fee,
    required this.net,
    this.mineHit,
    required this.time,
  });

  final _GameKind kind;
  final String game;
  final String result;
  final String detail;
  final double stake;
  final double payout;
  final double fee;
  final double net;
  final bool? mineHit;
  final DateTime time;
}
