import 'dart:async';

import 'package:flutter/foundation.dart';

typedef FlowTask = FutureOr<void> Function();

class ComplexTaskFlow {
  ComplexTaskFlow(List<int> initialSteps, {this.onComplete}) : _stepQueue = List<int>.from(initialSteps) {
    assert(_stepQueue.isNotEmpty, 'Initial steps cannot be empty');
  }

  final List<int> _stepQueue;
  final VoidCallback? onComplete;

  // 缓冲区
  final Map<int, _PendingResolution> _resultBuffer = {};

  bool _processing = false;
  bool _disposed = false;

  bool get isCompleted => _disposed || (_stepQueue.isEmpty && !_processing);

  void resolve(int stepId, {FlowTask? task, List<int>? nextSteps, bool stay = false}) {
    if (_disposed) return;

    final resolution = _PendingResolution(task, nextSteps, stay);

    // 【核心修复】：无论 stepId 当前是否在队列中，都必须存入 Buffer。
    // 原因：在动态替换/插入场景中，Step 3 的接口可能在 Step 1 把 Step 3 插入队列之前就返回了。
    // 如果这时候因为队列里没 3 就丢弃结果，会导致后续插入 3 之后，系统找不到 3 的结果而卡死。
    _resultBuffer[stepId] = resolution;

    // 只有当该步骤是当前的队头时，才触发处理循环
    // 如果不是队头（或者是还没插入队列的步骤），就静静地在 Buffer 里等着
    if (_stepQueue.isNotEmpty && _stepQueue.first == stepId) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_processing || _disposed) return;
    _processing = true;

    try {
      while (_stepQueue.isNotEmpty && !_disposed) {
        final currentStep = _stepQueue.first;
        final resolution = _resultBuffer[currentStep];

        // 如果队头步骤还没有结果，跳出循环等待
        if (resolution == null) break;

        // 1. 执行任务
        if (resolution.task != null) {
          try {
            await resolution.task!();
          } catch (e, s) {
            debugPrint('ComplexTaskFlow Error (Step $currentStep): $e\n$s');
          }
        }

        if (_disposed) break;

        // 2. 处理替换/分支逻辑
        if (resolution.nextSteps != null) {
          _handleReplacement(resolution.nextSteps!);
        }

        // 3. 队列流转
        if (resolution.stay) {
          // Stay 模式：消耗 Buffer，保留队头
          _resultBuffer.remove(currentStep);
          break;
        } else {
          // Next 模式：移除队头，移除 Buffer
          _stepQueue.removeAt(0);
          _resultBuffer.remove(currentStep);
        }
      }
    } finally {
      _processing = false;
    }

    if (_stepQueue.isEmpty && !_disposed) {
      cancel();
      onComplete?.call();
    }
  }

  void _handleReplacement(List<int> nextSteps) {
    // 1. 获取旧的后续步骤
    final oldFutureSteps = _stepQueue.length > 1 ? _stepQueue.sublist(1) : <int>[];

    // 2. 清理脏数据：如果旧步骤不在新计划中，必须清除其 Buffer
    final newStepSet = nextSteps.toSet();
    for (final step in oldFutureSteps) {
      if (!newStepSet.contains(step)) {
        _resultBuffer.remove(step);
      }
    }

    // 3. 修改队列
    if (_stepQueue.length > 1) {
      _stepQueue.removeRange(1, _stepQueue.length);
    }
    if (nextSteps.isNotEmpty) {
      _stepQueue.addAll(nextSteps);
    }
  }

  void cancel() {
    _disposed = true;
    _stepQueue.clear();
    _resultBuffer.clear();
  }
}

class _PendingResolution {
  final FlowTask? task;
  final List<int>? nextSteps;
  final bool stay;
  const _PendingResolution(this.task, this.nextSteps, this.stay);
}

class ComplexTaskFlowCenter {
  ComplexTaskFlowCenter._();
  static final ComplexTaskFlowCenter I = ComplexTaskFlowCenter._();
  final Map<String, ComplexTaskFlow> _flows = {};

  ComplexTaskFlow start(String key, List<int> initialSteps, {VoidCallback? onComplete}) {
    cancel(key);
    final flow = ComplexTaskFlow(
      initialSteps,
      onComplete: () {
        if (_flows[key]?.isCompleted == true) _flows.remove(key);
        onComplete?.call();
      },
    );
    _flows[key] = flow;
    return flow;
  }

  void resolve(String key, int stepId, {FlowTask? task, List<int>? nextSteps, bool stay = false}) {
    _flows[key]?.resolve(stepId, task: task, nextSteps: nextSteps, stay: stay);
  }

  void cancel(String key) => _flows.remove(key)?.cancel();
}
