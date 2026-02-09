import 'dart:async';

import 'package:flutter/material.dart';

import '../services/offline_manager.dart';

/// Overlay that shows download progress on the map screen.
///
/// Displays a progress bar with percentage and a cancel button.
/// Auto-dismisses when the download completes or is cancelled.
class DownloadProgressOverlay extends StatefulWidget {
  final Stream<DownloadProgress> progressStream;
  final VoidCallback onCancel;
  final VoidCallback onComplete;

  const DownloadProgressOverlay({
    super.key,
    required this.progressStream,
    required this.onCancel,
    required this.onComplete,
  });

  @override
  State<DownloadProgressOverlay> createState() =>
      _DownloadProgressOverlayState();
}

class _DownloadProgressOverlayState extends State<DownloadProgressOverlay> {
  DownloadProgress? _progress;
  StreamSubscription<DownloadProgress>? _sub;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.progressStream.listen(
      (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);

        if (progress.isComplete && !_completed) {
          _completed = true;
          // Show final state briefly, then dismiss
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) widget.onComplete();
          });
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _progress = DownloadProgress(
              progressPercent: 0,
              isComplete: true,
              error: 'Download failed: $e',
            ));
        _completed = true;
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) widget.onComplete();
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withAlpha(240),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _statusText(progress),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              if (progress == null || !progress.isComplete)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                    onPressed: widget.onCancel,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress?.progressPercent,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(
              _progressColor(progress),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${((progress?.progressPercent ?? 0) * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              if (progress?.error != null)
                Flexible(
                  child: Text(
                    progress!.error!,
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusText(DownloadProgress? progress) {
    if (progress == null) return 'Starting download...';
    if (progress.error != null) return 'Download failed';
    if (progress.isComplete) return 'Download complete';
    return 'Downloading tiles...';
  }

  Color _progressColor(DownloadProgress? progress) {
    if (progress?.error != null) return Colors.red.shade400;
    if (progress?.isComplete == true) return Colors.green.shade400;
    return const Color(0xFF4A90D9);
  }
}
