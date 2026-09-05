import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../application/providers.dart';
import '../../data/remote/server_client.dart';

/// Connection state shown on the settings page.
enum ConnectionState { unknown, checking, connected, failed }

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.focusServer = false});

  final bool focusServer;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _initialised = false;
  ConnectionState _connection = ConnectionState.unknown;
  String _connectionDetail = '';

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(serverConfigProvider).value;
    if (!_initialised && config != null) {
      _urlController.text = config.baseUrl;
      _tokenController.text = config.token;
      _initialised = true;
      if (config.isConfigured) {
        // Quietly confirm the stored configuration the first time the page opens.
        WidgetsBinding.instance.addPostFrameCallback((_) => _verify(quiet: true));
      }
    }

    final preferences = ref.watch(preferencesProvider).value ?? const ReaderPreferences();
    final library = ref.watch(libraryIndexProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _connectionCard(context, preferences),
          const SizedBox(height: 20),
          _sectionTitle(context, '阅读偏好'),
          Text(
            '以下设置即时生效，无需保存。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text('主题：${preferences.theme.label}'),
          SegmentedButton<ReaderTheme>(
            segments: [
              for (final theme in ReaderTheme.values)
                ButtonSegment(value: theme, label: Text(theme.label)),
            ],
            selected: {preferences.theme},
            onSelectionChanged: (selection) => ref
                .read(preferencesProvider.notifier)
                .save(preferences.copyWith(theme: selection.first)),
          ),
          const SizedBox(height: 16),
          Text('字号：${preferences.fontScale.toStringAsFixed(1)}'),
          Slider(
            value: preferences.fontScale,
            min: 0.8,
            max: 1.6,
            divisions: 16,
            onChanged: (value) =>
                ref.read(preferencesProvider.notifier).save(preferences.copyWith(fontScale: value)),
          ),
          Text('行距：${preferences.lineHeight.toStringAsFixed(1)}'),
          Slider(
            value: preferences.lineHeight,
            min: 1.2,
            max: 2.2,
            divisions: 10,
            onChanged: (value) =>
                ref.read(preferencesProvider.notifier).save(preferences.copyWith(lineHeight: value)),
          ),
          const Divider(height: 36),
          _sectionTitle(context, '本地存储'),
          Text('已下载文档：${library.length} 篇'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('清理全部离线内容'),
            onPressed: library.isEmpty ? null : _clearLibrary,
          ),
        ],
      ),
    );
  }

  Widget _connectionCard(BuildContext context, ReaderPreferences preferences) {
    final (icon, color, label) = switch (_connection) {
      ConnectionState.connected => (Icons.cloud_done_outlined, Colors.green, '已连接'),
      ConnectionState.failed => (Icons.cloud_off_outlined, Colors.redAccent, '连接失败'),
      ConnectionState.checking => (Icons.cloud_sync_outlined, Colors.orange, '连接中…'),
      ConnectionState.unknown => (Icons.cloud_queue, Colors.grey, '未验证'),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, '服务器连接'),
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _connectionDetail.isEmpty ? label : '$label · $_connectionDetail',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              autofocus: widget.focusServer,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: 'https://reader.example.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '访问令牌',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: _connection == ConnectionState.checking ? null : _saveAndVerify,
                  child: const Text('保存并测试连接'),
                ),
                const SizedBox(width: 12),
                if (_connection == ConnectionState.connected)
                  TextButton(
                    onPressed: _clearConfig,
                    child: const Text('清除配置'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Future<void> _saveAndVerify() async {
    final config = ServerConfig(
      baseUrl: _urlController.text.trim(),
      token: _tokenController.text.trim(),
    );
    await ref.read(serverConfigProvider.notifier).save(config);
    await _verify();
  }

  Future<void> _verify({bool quiet = false}) async {
    final config = ServerConfig(
      baseUrl: _urlController.text.trim(),
      token: _tokenController.text.trim(),
    );
    if (!config.isConfigured) {
      setState(() {
        _connection = ConnectionState.unknown;
        _connectionDetail = '尚未填写服务地址或令牌';
      });
      return;
    }
    setState(() {
      _connection = ConnectionState.checking;
      _connectionDetail = '';
    });
    try {
      final client = ServerClient(config: config);
      final health = await client.health();
      await client.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _connection = ConnectionState.connected;
        _connectionDetail = '${health.service} ${health.version}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connection = ConnectionState.failed;
        _connectionDetail = error is ServerException ? error.message : '$error';
      });
      if (!quiet) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败：$_connectionDetail')),
        );
      }
    }
  }

  Future<void> _clearConfig() async {
    await ref.read(serverConfigProvider.notifier).save(const ServerConfig(baseUrl: '', token: ''));
    _urlController.clear();
    _tokenController.clear();
    setState(() {
      _connection = ConnectionState.unknown;
      _connectionDetail = '配置已清除';
    });
  }

  Future<void> _clearLibrary() async {
    final store = await ref.read(libraryStoreProvider.future);
    final library = await store.readLibrary();
    for (final itemId in library.keys) {
      await store.removeItem(itemId);
    }
    ref.invalidate(libraryIndexProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清理离线内容')));
    }
  }
}
