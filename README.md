# InteractionFlow

[![Pub Version](https://img.shields.io/pub/v/interaction_flow)](https://pub.dev/packages/interaction_flow)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

一个强大、严格有序且支持动态调度的 Flutter 交互流控制器。

**InteractionFlow** 专为解决复杂的 UI 串行场景而生——例如 APP 启动弹窗链、新手引导流程或多步骤表单。它能确保 UI 严格按照预设顺序展示，哪怕背后的 API 是乱序返回的。

它将 **业务逻辑 (API)** 与 **UI 表现 (Dialog)** 彻底解耦，优雅地解决了“回调地狱”和“竞态条件 (Race Condition)”问题。

## 🚀 核心特性

*   **🛡️ 严格有序 (Strict Ordering)**：定义 A -> B -> C 的顺序，无论 API 谁先返回，用户看到的永远是 A -> B -> C。
*   **⏳ 乱序缓冲 (Async Buffering)**：如果步骤 C 的接口比 A 先返回，C 的结果会被安全缓冲，直到 A 和 B 执行完毕后才触发。
*   **🔀 智能替换 (Smart Replacement)**：支持根据用户交互或接口结果动态修改后续流程（分支逻辑）。
    *   *自动清洗*：如果已缓冲的步骤被移出计划，其结果会自动销毁（杜绝“幽灵弹窗”）。
    *   *状态保留*：如果已缓冲的步骤被保留，其结果将继续有效。
*   **🔄 循环重试 (Loop/Retry)**：支持在特定步骤停留（例如权限申请），直到满足条件才放行。
*   **安全并发**：通过唯一的 Key 管理多条并行流，互不干扰。

## 📦 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  interaction_flow: ^0.0.1
```
或者执行命令：

```Bash

flutter pub add interaction_flow
```
## 📖 使用指南
1. 基础：严格顺序流
定义一个顺序（例如：协议 -> 广告）。即使“广告”接口瞬间返回，而“协议”接口耗时 3 秒，用户也会先看到“协议”。

```dart

import 'package:interaction_flow/interaction_flow.dart';

// 定义步骤 ID
const int stepTOS = 1;
const int stepAd = 2;

void start() {
  // 1. 初始化流程
  InteractionFlowCenter.I.start('init_flow', [stepTOS, stepAd], onComplete: () {
    print('流程结束！');
  });

  // 2. 模拟并发请求 (顺序无关)
  _mockAdApi(); // 极速返回
  _mockTosApi(); // 慢速返回
}

void _mockAdApi() async {
  await Future.delayed(Duration(milliseconds: 100));
  // 此时 Step 1 还没完，Step 2 的结果会被存入 Buffer 等待
  InteractionFlowCenter.I.resolve(
    'init_flow', 
    stepAd, 
    task: () async => await showDialog(...),
  );
}

void _mockTosApi() async {
  await Future.delayed(Duration(seconds: 2));
  // Step 1 完成，立即展示。展示结束后，会自动触发已缓冲的 Step 2。
  InteractionFlowCenter.I.resolve(
    'init_flow', 
    stepTOS, 
    task: () async => await showDialog(...),
  );
}
```
2. 分支：智能替换 (Branching)
动态改变后续流程。例如：如果是 VIP 用户，跳过“普通广告 (Step 2)”，直接显示“VIP 礼包 (Step 3)”。

场景演示：

初始计划：[1, 2]
Step 2 (广告) 接口先回，结果已缓冲。
Step 1 (用户检查) 接口后回，决定替换后续流程为 [3]。
结果： Step 2 的缓冲结果被自动销毁，Step 3 被加入队列。

```dart

// 初始: [CheckUser, Ad]
InteractionFlowCenter.I.start('vip_flow', [1, 2]);

// ... Step 2 (Ad) 接口已回并缓冲 ...

// Step 1: 用户检查
InteractionFlowCenter.I.resolve(
  'vip_flow', 
  1, 
  task: null, // 该步骤本身无 UI
  // 逻辑: 替换剩余步骤为 [3] (VIP Gift)。
  // 系统会自动清理 Step 2 的脏数据。
  nextSteps: [3], 
);
```
3. 插队：保留并插入 (Insertion)
你也可以在插入新步骤的同时，保留旧步骤。

场景演示：

初始计划：[1, 2]
Step 1 决定在 2 之前插入 3。
结果： 顺序变为 1 -> 3 -> 2。如果 Step 2 之前已缓冲，它会保留在 Buffer 中等待最后执行。

```dart

// Step 1
InteractionFlowCenter.I.resolve(
  'vip_flow', 
  1, 
  task: () async => await showDialog(...),
  // 逻辑: 插入 3，但保留 2。
  nextSteps: [3, 2], 
);
```
4. 循环：权限重试 (Looping)
使用 stay: true 让流程停留在当前步骤，直到条件满足。

```dart

void checkPermission() {
  if (isGranted) {
    // 通过：移除步骤，继续向下
    InteractionFlowCenter.I.resolve('perm_flow', 2, task: null);
  } else {
    // 拒绝：停留重试
    InteractionFlowCenter.I.resolve(
      'perm_flow',
      2,
      stay: true, // <--- 关键参数
      task: () async {
        await showDialog(content: "必须同意权限才能继续。");
        // 弹窗关闭后递归检查
        checkPermission();
      },
    );
  }
}
```
## 🧩 API 参考
## InteractionFlowCenter.I (单例)
*   start(String key, List<int> steps, {VoidCallback? onComplete})
	*   开启一条新流。如果同名 key 已存在，旧流会被自动取消。
*   resolve(String key, int stepId, {FlowTask? task, List<int>? nextSteps, bool stay = false})

*   stepId: 步骤 ID。
*   task: UI 逻辑 (通常是 showDialog)。必须返回 FutureOr<void>。如果需要等待弹窗关闭，
*   请使用 await。传 null 表示无 UI。
*   nextSteps:
	*   null: 不改变后续队列。
	*   [...]: 替换 剩余队列为新列表。
*   stay:
	*   true: 执行完 task 后不移除当前步骤（用于重试）。
	*   false: 执行完 task 后移除当前步骤，进入下一步。
*   cancel(String key)
	*   立即终止流程并清空所有缓冲区。
## 💡 核心机制解密
1. 解决“幽灵弹窗”问题
在使用 nextSteps 替换队列时，InteractionFlow 会执行 集合差集运算 (Set Difference)：

如果某个步骤 不在 新的 nextSteps 列表中，它的缓冲结果会被 立即销毁。
如果某个步骤 在 新列表中，它的缓冲结果会被 保留。
这确保了当你决定跳过某个步骤（如“广告”）时，即使它的接口已经返回了，广告弹窗也绝对不会再跳出来。

2. 预缓冲机制
你可以对当前队列中不存在的 stepId 调用 resolve。系统会将结果存入缓冲区，一旦该步骤通过 nextSteps 被插入到队列中，它就会立即被执行。这完美支持了动态插入场景下的乱序返回。

## 🤝 贡献
欢迎提交 Issue 和 Pull Request！

## 📄 协议
MIT License. 详见 LICENSE 文件。