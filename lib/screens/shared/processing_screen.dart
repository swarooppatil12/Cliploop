import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/app_constants.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/processing_status_text.dart';
import '../../providers/music_provider.dart';
import '../../widgets/common/app_logo.dart';
import 'widgets/error_widget.dart';
import 'widgets/progress_indicator_widget.dart';

enum ProcessingMethod { spleeter, whisper }

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    required this.method,
  });

  final ProcessingMethod method;

  static ProcessingMethod methodFromArgs(Object? arguments) {
    if (arguments == 'whisper') {
      return ProcessingMethod.whisper;
    }
    return ProcessingMethod.spleeter;
  }

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;
  bool _started = false;
  bool _navigatedOnComplete = false;

  ActiveProcessingMethod get _activeMethod =>
      widget.method == ProcessingMethod.whisper
          ? ActiveProcessingMethod.whisper
          : ActiveProcessingMethod.spleeter;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startProcessing());
  }

  Future<void> _startProcessing() async {
    if (_started) {
      return;
    }
    _started = true;

    final provider = context.read<MusicProvider>();
    try {
      await provider.ensureProcessing(_activeMethod);
    } catch (_) {
      // Errors are surfaced via provider state.
    }

    if (!mounted) {
      return;
    }

    _handleCompletion(context.read<MusicProvider>());
  }

  void _handleCompletion(MusicProvider provider) {
    if (_navigatedOnComplete) {
      return;
    }

    if (widget.method == ProcessingMethod.spleeter) {
      if (provider.spleeterState == ProcessingState.complete) {
        _navigatedOnComplete = true;
        Navigator.pushReplacementNamed(context, AppRoutes.spleeter);
      }
      return;
    }

    if (provider.whisperState == ProcessingState.complete) {
      _navigatedOnComplete = true;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.whisper);
      }
    }
  }

  void _cancel(MusicProvider provider) {
    provider.cancelProcessing(
      spleeter: widget.method == ProcessingMethod.spleeter,
      whisper: widget.method == ProcessingMethod.whisper,
    );
    Navigator.pop(context);
  }

  void _continueInBackground() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Processing continues in the background. We will notify you when it finishes.',
        ),
      ),
    );
    Navigator.pop(context);
  }

  String _stepText(MusicProvider provider) {
    return processingStepText(
      method: _activeMethod,
      state: widget.method == ProcessingMethod.spleeter
          ? provider.spleeterState
          : provider.whisperState,
      progress: widget.method == ProcessingMethod.spleeter
          ? provider.spleeterProgress
          : provider.whisperProgress,
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        final provider = context.read<MusicProvider>();
        final isRunning = widget.method == ProcessingMethod.spleeter
            ? provider.spleeterState == ProcessingState.preparing ||
                provider.spleeterState == ProcessingState.processing
            : provider.whisperState == ProcessingState.preparing ||
                provider.whisperState == ProcessingState.processing;

        if (isRunning) {
          _continueInBackground();
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Consumer<MusicProvider>(
          builder: (context, provider, _) {
            final isSpleeter = widget.method == ProcessingMethod.spleeter;
            final state =
                isSpleeter ? provider.spleeterState : provider.whisperState;
            final progress =
                isSpleeter ? provider.spleeterProgress : provider.whisperProgress;
            final fileName = provider.selectedFile?.name ?? 'Audio file';
            final hasError = state == ProcessingState.error;
            final isRunning = state == ProcessingState.preparing ||
                state == ProcessingState.processing;

            if (state == ProcessingState.complete) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleCompletion(provider);
              });
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: _ShimmerWaveformBackground(
                    animation: _waveController,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppLogo(size: 28),
                              const SizedBox(width: 10),
                              Text(
                                AppConstants.appName,
                                style: AppTextStyles.displayMedium,
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (hasError)
                          ErrorDisplayWidget(
                            message: provider.lastErrorMessage ??
                                'Processing failed. Please try again.',
                            onRetry: () {
                              if (isSpleeter) {
                                provider.markSpleeterNeedsRun();
                              } else {
                                provider.markWhisperNeedsRun();
                              }
                              _started = false;
                              _navigatedOnComplete = false;
                              _startProcessing();
                            },
                          )
                        else ...[
                          ProgressIndicatorWidget(progress: progress),
                          const SizedBox(height: 28),
                          Text(
                            _stepText(provider),
                            style: AppTextStyles.headlineLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            fileName,
                            style: AppTextStyles.bodyMedium,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isRunning) ...[
                            const SizedBox(height: 16),
                            Text(
                              'You can leave this screen — processing will continue '
                              'and we will notify you when done.',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                        const Spacer(),
                        if (isRunning) ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _continueInBackground,
                              icon: const Icon(Icons.layers_outlined),
                              label: const Text('Continue in background'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryGreen,
                                side: BorderSide(
                                  color: AppColors.primaryGreen.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: hasError
                                ? () => Navigator.pop(context)
                                : isRunning
                                    ? () => _cancel(provider)
                                    : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.surfaceBorder),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              hasError
                                  ? 'Close'
                                  : isRunning
                                      ? 'Cancel processing'
                                      : 'Close',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ShimmerWaveformBackground extends StatelessWidget {
  const _ShimmerWaveformBackground({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Shimmer.fromColors(
          baseColor: AppColors.surface.withValues(alpha: 0.35),
          highlightColor: AppColors.primaryGreen.withValues(alpha: 0.18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 120),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(28, (index) {
                final wave = (math.sin((index + animation.value * 6)) + 1) / 2;
                final height = 24 + wave * 120 + (index % 4) * 8;
                return Expanded(
                  child: Container(
                    height: height,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
