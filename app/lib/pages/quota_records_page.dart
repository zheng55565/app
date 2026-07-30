import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../preview/preview_data.dart';

enum _RecordFilter { all, income, expense }

class QuotaRecordsPage extends StatefulWidget {
  const QuotaRecordsPage({super.key});

  @override
  State<QuotaRecordsPage> createState() => _QuotaRecordsPageState();
}

class _QuotaRecordsPageState extends State<QuotaRecordsPage> {
  List<Map<String, dynamic>> _records = const [];
  _RecordFilter _filter = _RecordFilter.all;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (AppConfig.previewMode) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() {
        _records = PreviewData.quotaRecords();
        _loading = false;
      });
      return;
    }
    try {
      final result = await ApiClient.instance.requestLegacy(
        'GET',
        '/api/wallet/records?page=1&page_size=50',
      );
      final raw = result['records'] as List<dynamic>? ?? const [];
      if (!mounted) return;
      setState(() {
        _records = raw.whereType<Map<String, dynamic>>().toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '额度明细加载失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visibleRecords {
    return _records.where((record) {
      final amount = _amount(record);
      return switch (_filter) {
        _RecordFilter.all => true,
        _RecordFilter.income => amount > 0,
        _RecordFilter.expense => amount < 0,
      };
    }).toList();
  }

  static double _amount(Map<String, dynamic> record) {
    final usd = record['amount_usd'];
    if (usd is num) return usd.toDouble();
    final micro = record['amount_microunits'];
    return micro is num ? micro.toDouble() / 1000000 : 0;
  }

  static double? _balanceAfter(Map<String, dynamic> record) {
    final usd = record['balance_after_usd'];
    if (usd is num) return usd.toDouble();
    final micro = record['balance_after_microunits'];
    return micro is num ? micro.toDouble() / 1000000 : null;
  }

  static String _recordTitle(Map<String, dynamic> record) {
    final remark = record['remark']?.toString().trim();
    if (remark != null && remark.isNotEmpty) return remark;
    return switch (record['type']?.toString()) {
      'ad_reward' => '广告任务奖励',
      'api_consume' || 'consume' => 'API 调用',
      'image_generation' => '图片生成',
      'game_consume' => '游戏参与',
      'game_reward' => '游戏奖励',
      'admin_adjust' => '额度调整',
      _ => '额度变动',
    };
  }

  static String _formatTime(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (parsed == null) return '--';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleRecords;
    final income = _records.fold<double>(
      0,
      (sum, record) => _amount(record) > 0 ? sum + _amount(record) : sum,
    );
    final expense = _records.fold<double>(
      0,
      (sum, record) => _amount(record) < 0 ? sum + _amount(record).abs() : sum,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('额度收支明细'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryValue(
                        label: '本页收入',
                        value: '+\$${income.toStringAsFixed(2)}',
                        color: const Color(0xFF49DDA5),
                      ),
                    ),
                    Expanded(
                      child: _SummaryValue(
                        label: '本页支出',
                        value: '-\$${expense.toStringAsFixed(2)}',
                        color: const Color(0xFFFF7186),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_RecordFilter>(
                    segments: const [
                      ButtonSegment(
                        value: _RecordFilter.all,
                        label: Text('全部'),
                      ),
                      ButtonSegment(
                        value: _RecordFilter.income,
                        label: Text('收入'),
                      ),
                      ButtonSegment(
                        value: _RecordFilter.expense,
                        label: Text('支出'),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (values) {
                      setState(() => _filter = values.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(
                      padding: const EdgeInsets.all(32),
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('重新加载'),
                          ),
                        ),
                      ],
                    )
                  : visible.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(32),
                      children: const [
                        Icon(Icons.receipt_long_outlined, size: 48),
                        SizedBox(height: 12),
                        Text('暂无相关额度记录', textAlign: TextAlign.center),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        return _RecordTile(record: visible[index]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final amount = _QuotaRecordsPageState._amount(record);
    final balanceAfter = _QuotaRecordsPageState._balanceAfter(record);
    final income = amount > 0;
    final color = income ? const Color(0xFF49DDA5) : const Color(0xFFFF7186);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
        child: Icon(income ? Icons.south_west : Icons.north_east),
      ),
      title: Text(_QuotaRecordsPageState._recordTitle(record)),
      subtitle: Text(
        '${_QuotaRecordsPageState._formatTime(record['created_at'])}'
        '${balanceAfter == null ? '' : '  ·  余额 \$${balanceAfter.toStringAsFixed(2)}'}',
      ),
      trailing: Text(
        '${income ? '+' : '-'}\$${amount.abs().toStringAsFixed(2)}',
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
