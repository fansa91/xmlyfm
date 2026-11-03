import 'package:flutter/material.dart';

import '../services/download_filename.dart';

/// 下载文件名格式编辑弹窗（原生 M3 AlertDialog）：
/// 文本框 + 变量插入 chips + 实时预览 + 恢复默认；
/// 保存校验：模板不能为空、示例渲染结果不能为空。
class DownloadFormatDialog extends StatefulWidget {
  final String initial;

  const DownloadFormatDialog({super.key, required this.initial});

  @override
  State<DownloadFormatDialog> createState() => _DownloadFormatDialogState();
}

class _DownloadFormatDialogState extends State<DownloadFormatDialog> {
  late final TextEditingController _controller;

  /// 预览示例数据
  static const _sampleAlbum = '暮色航行·声音日记';
  static const _sampleTitle = '秋风信件';
  static const _sampleAuthor = '拾光电台';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _preview {
    final fmt = _controller.text;
    if (fmt.trim().isEmpty) return '';
    final rendered = DownloadFileNameFormatter.render(
      fmt,
      album: _sampleAlbum,
      title: _sampleTitle,
      index: 3,
      trackId: 123456,
      author: _sampleAuthor,
    );
    return '$rendered.mp3';
  }

  bool get _valid => _controller.text.trim().isNotEmpty && _preview.isNotEmpty;

  void _insertVariable(String variable) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final next = text.replaceRange(start, end, variable);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + variable.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('下载文件名格式'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '文件名模板',
                helperText: '只影响之后的新下载，不重命名已下载文件',
              ),
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in DownloadFileNameFormatter.variables.entries)
                  ActionChip(
                    label: Text('${entry.key} ${entry.value}'),
                    onPressed: () => _insertVariable(entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _preview.isEmpty ? '预览：（渲染结果为空）' : '预览：$_preview',
              style: TextStyle(
                fontSize: 13,
                color: _valid
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              _controller.text = DownloadFileNameFormatter.defaultFormat,
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
