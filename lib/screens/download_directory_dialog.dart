import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/download_service.dart';

/// 「默认下载路径」编辑对话框。
///
/// 选目录走 file_picker 的系统目录选择器（桌面/Android），选择器
/// 不可用（如 Linux 缺 zenity）时可手动输入路径兜底；保存前统一用
/// [DownloadService.prepareDirectory] 校验（不存在则尝试创建 + 可写
/// 探针），不可用则报错不保存。
///
/// 返回要保存的自定义路径（空串 = 恢复默认）；取消返回 null。
/// 改路径只影响之后的新下载，已下载文件不会搬移。
class DownloadDirectoryDialog extends StatefulWidget {
  /// 当前自定义值（空串 = 未设置，走默认）
  final String current;

  /// 默认目录路径（展示用，未知时为空串）
  final String defaultPath;

  const DownloadDirectoryDialog({
    super.key,
    required this.current,
    required this.defaultPath,
  });

  @override
  State<DownloadDirectoryDialog> createState() =>
      _DownloadDirectoryDialogState();
}

class _DownloadDirectoryDialogState extends State<DownloadDirectoryDialog> {
  late final TextEditingController _controller;
  String? _error;
  bool _validating = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    try {
      final initial = _controller.text.trim();
      final picked = await FilePicker.getDirectoryPath(
        dialogTitle: '选择下载目录',
        initialDirectory: initial.isNotEmpty ? initial : null,
      );
      if (picked != null && picked.isNotEmpty) {
        setState(() {
          _controller.text = picked;
          _error = null;
        });
      }
    } catch (_) {
      // 选择器不可用（平台缺组件/无权限等）：提示手动输入兜底
      if (mounted) {
        setState(() => _error = '目录选择不可用，请手动输入路径');
      }
    }
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      Navigator.of(context).pop('');
      return;
    }
    setState(() {
      _validating = true;
      _error = null;
    });
    final ok = await DownloadService.prepareDirectory(Directory(value));
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(value);
    } else {
      setState(() {
        _validating = false;
        _error = '目录不可用：不存在且无法创建，或不可写';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('默认下载路径'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: '下载目录',
              hintText: widget.defaultPath,
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _validating ? null : _pickDirectory,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('选择目录'),
            ),
          ),
          Text(
            '留空保存即使用默认目录'
            '${widget.defaultPath.isEmpty ? '' : '：${widget.defaultPath}'}\n'
            '仅影响之后的新下载，已下载文件不会搬移。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _validating
              ? null
              : () => Navigator.of(context).pop(''),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: _validating
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _validating ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
