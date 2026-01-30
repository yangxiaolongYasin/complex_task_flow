import 'dart:async';

import 'package:complex_task_flow/complex_task_flow.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: HomePage()));
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ComplexTaskFlow")),
      body: ListView(padding: const EdgeInsets.all(16), children: [_navItem(context, "场景 1: 严格顺序", const ScenarioOnePage(), Colors.blue), _navItem(context, "场景 2: 替换并丢弃", const ScenarioTwoPage(), Colors.orange), _navItem(context, "场景 3: 插入并保留", const ScenarioThreePage(), Colors.purple), _navItem(context, "场景 4: 循环阻塞", const ScenarioFourPage(), Colors.red)]),
    );
  }

  Widget _navItem(BuildContext context, String title, Widget page, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: const Icon(Icons.play_arrow, color: Colors.white),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      ),
    );
  }
}

// --- 基础页面类 (包含 UI 队列自动同步逻辑) ---
abstract class BaseFlowPage extends StatefulWidget {
  final String title;
  const BaseFlowPage({super.key, required this.title});
}

abstract class BaseFlowPageState<T extends BaseFlowPage> extends State<T> {
  List<int> visualQueue = [];
  Set<int> bufferedSteps = {};
  int? activeStep;
  String get flowKey;

  @override
  void dispose() {
    ComplexTaskFlowCenter.I.cancel(flowKey);
    super.dispose();
  }

  void startFlow();

  void mockApi(int step, int delayMs, Function() onReady) async {
    await Future.delayed(Duration(milliseconds: delayMs));
    if (!mounted) return;
    setState(() => bufferedSteps.add(step));
    onReady();
  }

  Future<void> showVisualDialog(int step, String title, String content, {Color color = Colors.blue}) {
    setState(() {
      activeStep = step;
      // 智能同步：移除 UI 队列中当前步骤之前的残留项
      while (visualQueue.isNotEmpty && visualQueue.first != step) {
        visualQueue.removeAt(0);
      }
    });

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: TextStyle(color: color)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                // 关闭时移除当前步骤
                if (visualQueue.isNotEmpty && visualQueue.first == step) {
                  visualQueue.removeAt(0);
                }
                activeStep = null;
              });
            },
            child: const Text("下一步"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.grey[200],
            child: ElevatedButton(onPressed: startFlow, child: const Text("启动演示")),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (visualQueue.isEmpty) const Center(child: Text("队列空闲")),
                for (var step in visualQueue) _buildStepCard(step),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(int step) {
    bool isBuffered = bufferedSteps.contains(step);
    bool isActive = activeStep == step;
    Color color = isActive ? Colors.blue : (isBuffered ? Colors.orange : Colors.grey);
    return Card(
      color: isActive ? Colors.blue[50] : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Text("$step", style: const TextStyle(color: Colors.white)),
        ),
        title: Text("步骤 $step"),
        subtitle: Text(isActive ? "正在展示..." : (isBuffered ? "接口已回 (等待中)" : "等待 API...")),
      ),
    );
  }
}

// --- 场景 1: 严格顺序 ---
class ScenarioOnePage extends BaseFlowPage {
  const ScenarioOnePage({super.key}) : super(title: "严格顺序");
  @override
  State<ScenarioOnePage> createState() => _ScenarioOneState();
}

class _ScenarioOneState extends BaseFlowPageState<ScenarioOnePage> {
  @override
  String get flowKey => 'flow_strict';
  @override
  void startFlow() {
    setState(() {
      visualQueue = [1, 2, 3];
      bufferedSteps = {};
      activeStep = null;
    });
    ComplexTaskFlowCenter.I.start(flowKey, [1, 2, 3]);
    mockApi(3, 100, () => ComplexTaskFlowCenter.I.resolve(flowKey, 3, task: () => showVisualDialog(3, "步骤 3", "最后一步，最早返回", color: Colors.orange)));
    mockApi(2, 500, () => ComplexTaskFlowCenter.I.resolve(flowKey, 2, task: () => showVisualDialog(2, "步骤 2", "中间步骤", color: Colors.blue)));
    mockApi(1, 1000, () => ComplexTaskFlowCenter.I.resolve(flowKey, 1, task: () => showVisualDialog(1, "步骤 1", "第一步，最慢返回", color: Colors.purple)));
  }
}

// --- 场景 2: 替换并丢弃 ---
class ScenarioTwoPage extends BaseFlowPage {
  const ScenarioTwoPage({super.key}) : super(title: "替换并丢弃");
  @override
  State<ScenarioTwoPage> createState() => _ScenarioTwoState();
}

class _ScenarioTwoState extends BaseFlowPageState<ScenarioTwoPage> {
  @override
  String get flowKey => 'flow_clean';
  @override
  void startFlow() {
    setState(() {
      visualQueue = [1, 2];
      bufferedSteps = {};
      activeStep = null;
    });
    ComplexTaskFlowCenter.I.start(flowKey, [1, 2]);

    // Step 2 接口先回，存入 Buffer (之前这里会失败，现在修复了)
    mockApi(2, 100, () => ComplexTaskFlowCenter.I.resolve(flowKey, 2, task: () => showVisualDialog(2, "错误", "我不应该出现")));

    // Step 1 后回，触发替换
    mockApi(1, 1000, () {
      ComplexTaskFlowCenter.I.resolve(flowKey, 1, task: () => showVisualDialog(1, "步骤 1", "点击下一步后，\nStep 2 将消失，Step 3 将出现。"), nextSteps: [3]);
      // 同步 UI: 当前是1，后续变成了3
      setState(() => visualQueue = [1, 3]);
      _mockStep3();
    });
  }

  void _mockStep3() {
    mockApi(3, 500, () => ComplexTaskFlowCenter.I.resolve(flowKey, 3, task: () => showVisualDialog(3, "步骤 3", "Step 2 已被丢弃", color: Colors.green)));
  }
}

// --- 场景 3: 插入并保留 ---
class ScenarioThreePage extends BaseFlowPage {
  const ScenarioThreePage({super.key}) : super(title: "插入并保留");
  @override
  State<ScenarioThreePage> createState() => _ScenarioThreeState();
}

class _ScenarioThreeState extends BaseFlowPageState<ScenarioThreePage> {
  @override
  String get flowKey => 'flow_merge';
  @override
  void startFlow() {
    setState(() {
      visualQueue = [1, 2];
      bufferedSteps = {};
      activeStep = null;
    });
    ComplexTaskFlowCenter.I.start(flowKey, [1, 2]);

    mockApi(2, 100, () => ComplexTaskFlowCenter.I.resolve(flowKey, 2, task: () => showVisualDialog(2, "步骤 2", "我是保留下来的", color: Colors.orange)));

    mockApi(1, 1000, () {
      ComplexTaskFlowCenter.I.resolve(flowKey, 1, task: () => showVisualDialog(1, "步骤 1", "插入 Step 3，保留 Step 2。\n顺序: 1->3->2"), nextSteps: [3, 2]);
      setState(() => visualQueue = [1, 3, 2]);
      _mockStep3();
    });
  }

  void _mockStep3() {
    mockApi(3, 500, () => ComplexTaskFlowCenter.I.resolve(flowKey, 3, task: () => showVisualDialog(3, "步骤 3", "插队步骤", color: Colors.green)));
  }
}

// --- 场景 4: 循环阻塞 ---
class ScenarioFourPage extends BaseFlowPage {
  const ScenarioFourPage({super.key}) : super(title: "循环阻塞");
  @override
  State<ScenarioFourPage> createState() => _ScenarioFourState();
}

class _ScenarioFourState extends BaseFlowPageState<ScenarioFourPage> {
  @override
  String get flowKey => 'flow_loop';
  bool _isAuthorized = false;
  int _denyCount = 0;

  @override
  void startFlow() {
    setState(() {
      visualQueue = [1, 2, 3];
      bufferedSteps = {};
      activeStep = null;
      _isAuthorized = false;
      _denyCount = 0;
    });
    ComplexTaskFlowCenter.I.start(flowKey, [1, 2, 3]);

    mockApi(1, 100, () => ComplexTaskFlowCenter.I.resolve(flowKey, 1, task: () => showVisualDialog(1, "步骤 1", "欢迎", color: Colors.blue)));
    mockApi(2, 500, _checkPermission);
    mockApi(3, 100, () => ComplexTaskFlowCenter.I.resolve(flowKey, 3, task: () => showVisualDialog(3, "步骤 3", "流程结束", color: Colors.green)));
  }

  void _checkPermission() {
    if (_isAuthorized) {
      // 逻辑通过
      ComplexTaskFlowCenter.I.resolve(flowKey, 2, task: null);
      // UI 手动移除 (因为 task: null 不会触发 showVisualDialog)
      setState(() => visualQueue.removeWhere((id) => id == 2));
    } else {
      // 逻辑拒绝 (Stay)
      ComplexTaskFlowCenter.I.resolve(
        flowKey,
        2,
        stay: true,
        task: () => showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("⚠️ 权限申请"),
            content: Text("必须点击【同意】。\n已拒绝 $_denyCount 次。"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _denyCount++;
                  Future.delayed(const Duration(milliseconds: 300), _checkPermission);
                },
                child: const Text("拒绝"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _isAuthorized = true;
                  Future.delayed(const Duration(milliseconds: 300), _checkPermission);
                },
                child: const Text("同意"),
              ),
            ],
          ),
        ),
      );
    }
  }
}
