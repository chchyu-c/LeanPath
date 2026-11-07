import 'dart:async';

import 'package:pedometer/pedometer.dart';

enum MotionState { unavailable, still, walking }

/// 一次感知判定结果。reasonCode 交给 UI 映射成多语言文案，服务层不硬编码中文。
class SensingVerdict {
  final bool detected;
  final MotionState state;
  final int stepsInWindow;
  final String reasonCode;

  const SensingVerdict({
    required this.detected,
    required this.state,
    required this.stepsInWindow,
    required this.reasonCode,
  });

  static const unavailable = SensingVerdict(
    detected: false,
    state: MotionState.unavailable,
    stepsInWindow: 0,
    reasonCode: 'unavailable',
  );
}

/// 「手机感知到有在做这件事」：计步 + 活动状态双通道，手动打卡兜底。
///
/// - Android：TYPE_STEP_COUNTER + ACTIVITY_RECOGNITION（pedometer 插件封装）
/// - iOS：CMPedometer + CMMotionActivityManager（Info.plist 需 NSMotionUsageDescription）
/// - 判定只在「提醒窗口」内进行，不常驻后台采样，控制耗电与隐私风险。
/// - 感知不可用或未达标时返回 detected=false，UI 显示手动打卡按钮。
class ActivitySensingService {
  static const int defaultMinSteps = 120; // 约 1~2 分钟快走，可按用户调整

  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<PedestrianStatus>? _statusSub;
  final StreamController<SensingVerdict> _controller =
      StreamController<SensingVerdict>.broadcast();

  int? _lastSteps;
  int? _baselineSteps;
  int _windowSteps = 0;
  int _minSteps = defaultMinSteps;
  MotionState _state = MotionState.unavailable;
  bool _sensorError = false;
  bool _running = false;
  DateTime? _windowStart;

  Stream<SensingVerdict> get verdicts => _controller.stream;
  SensingVerdict get current => evaluate();
  DateTime? get windowStart => _windowStart;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    _stepSub = Pedometer.stepCountStream.listen(
      (StepCount event) {
        _lastSteps = event.steps;
        final baseline = _baselineSteps;
        if (baseline != null) {
          final delta = event.steps - baseline;
          if (delta >= 0 && delta > _windowSteps) {
            _windowSteps = delta;
            _emit();
          }
        }
      },
      onError: (Object _) {
        _sensorError = true;
        _emit();
      },
      cancelOnError: false,
    );

    _statusSub = Pedometer.pedestrianStatusStream.listen(
      (PedestrianStatus event) {
        _state = event.status.toLowerCase() == 'walking'
            ? MotionState.walking
            : MotionState.still;
        _emit();
      },
      onError: (Object _) {
        // 部分 Android 机型不提供活动状态流，保留步数通道单独判定。
      },
      cancelOnError: false,
    );
  }

  /// 提醒触发 / App 回到前台时开启一个观察窗口。
  void beginWindow({int? minSteps}) {
    _baselineSteps = _lastSteps;
    _windowSteps = 0;
    _minSteps = minSteps ?? defaultMinSteps;
    _windowStart = DateTime.now();
    _emit();
  }

  void endWindow() {
    _baselineSteps = null;
    _windowStart = null;
  }

  SensingVerdict evaluate() {
    if (_sensorError && _lastSteps == null) {
      return SensingVerdict.unavailable;
    }
    if (_windowStart == null) {
      return SensingVerdict(
        detected: false,
        state: _state,
        stepsInWindow: 0,
        reasonCode: 'window_not_started',
      );
    }

    final detected = _windowSteps >= _minSteps ||
        (_state == MotionState.walking && _windowSteps >= _minSteps ~/ 2);

    final reason = detected
        ? (_state == MotionState.walking ? 'sensor_walking' : 'steps_exceeded')
        : (_state == MotionState.walking
            ? 'walking_insufficient_steps'
            : (_sensorError ? 'unavailable' : 'still'));

    return SensingVerdict(
      detected: detected,
      state: _state,
      stepsInWindow: _windowSteps,
      reasonCode: reason,
    );
  }

  void _emit() => _controller.add(evaluate());

  Future<void> stop() async {
    await _stepSub?.cancel();
    await _statusSub?.cancel();
    _stepSub = null;
    _statusSub = null;
    _running = false;
    await _controller.close();
  }
}
