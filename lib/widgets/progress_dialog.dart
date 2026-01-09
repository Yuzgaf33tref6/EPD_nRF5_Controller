import 'package:flutter/material.dart';

class ProgressDialog extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback? onCancel;
  final bool showCancelButton;

  const ProgressDialog({
    super.key,
    required this.title,
    required this.message,
    this.onCancel,
    this.showCancelButton = true,
  });

  @override
  State<ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> {
  double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            widget.message,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_progress > 0)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
        ],
      ),
      actions: [
        if (widget.showCancelButton)
          TextButton(
            onPressed: widget.onCancel,
            child: const Text('取消'),
          ),
      ],
    );
  }

  // 更新进度
  void updateProgress(double progress) {
    setState(() {
      _progress = progress;
    });
  }
}