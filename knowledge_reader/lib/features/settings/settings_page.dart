import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../application/providers.dart';
import '../../data/remote/server_client.dart';

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
  bool _busy = false;
  String? _status;

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
    }
    final preferences = ref.watch(preferencesProvider).value ?? const ReaderPreferences();
    final library = ref.watch(libraryIndexProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('服务器'),
          TextField(
            controller: _urlController,
            autofocus: widget.focusServer,
            decoration: const InputDecoration(
              labelText: '服务地址',
              hintText: 'https://reader.example.com 或 http://192.168.1.10:18765',
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
                onPressed: _busy ? null : _testConnection,
                child: const Text('测试连接'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy ? null : _save,
                child: const Text('保存'),
              ),
            ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_status!),
            ),
          const Divider(height: 36),
          const _SectionTitle('阅读偏好'),
          Text('主题：${preferences.theme.label}'),
          SegmentedButton<ReaderTheme>(
            segments: [
              for (final theme in ReaderTheme.values)
                ButtonSegment(value: theme, label: Text(theme.label)),
            ],
            selected: {preferences.theme},
            onSelectionChanged: (selection) =>
                ref.read(preferencesProvider.notifier).save(preferences.copyWith(theme: selection.first)),
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
          const _SectionTitle('本地存储'),
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

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final config = ServerConfig(baseUrl: _urlController.text.trim(), token: _tokenController.text.trim());
    await ref.read(serverConfigProvider.notifier).save(config);
    setState(() {
      _busy = false;
      _status = '已保存';
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _status = '连接中…';
    });
    final config = ServerConfig(baseUrl: _urlController.text.trim(), token: _tokenController.text.trim());
    try {
      final client = ServerClient(config: config);
      final health = await client.health();
      await client.fetchCatalog();
      setState(() => _status = '连接成功：${health.service} ${health.version}');
    } catch (error) {
      setState(() => _status = '连接失败：$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _clearLibrary() async {
    final store = await ref.read(libraryStoreProvider.future);
    final library = await store.readLibrary();
    for (final itemId in library.keys) {
      await store.removeItem(itemId);
    }
    ref.invalidate(libraryIndexProvider);
    setState(() => _status = '已清理离线内容');
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
