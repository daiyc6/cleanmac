# cleanmac

一个免费、开源、**不联网**的 macOS 空间管理工具。

> 不判断"你有没有用"，只判断"系统能不能重新造出来"，并保证每一步都能撤回。

**[下载 macOS 版](https://github.com/daiyc6/cleanmac/releases/latest)** · 2.0 MB · macOS 14+ · 免费开源

---

## 三条原则

1. **核心功能优先。** 先做能释放空间的模块，再谈视觉。
2. **删除必须可逆。** 所有删除先进隔离区，1 天后自动清理。
3. **用户文件由用户决定。** 系统缓存一步清理，个人文件必须逐项确认。

## 功能

| 模块 | 能力 |
|---|---|
| 概览 | 大字号可清理量，一个按钮完成 |
| 清理 | 系统数据一键清 / 个人文件需确认，两级分离 |
| 应用程序 | 每行：**删数据**（留 App）/ **删 App**（留数据） |
| 大文件 | ≥200 MB 或一年未访问，可直接删除 |
| 空间地图 | 逐层下钻、面包屑、小项聚合、勾选删除 |
| 隐形空间 | TCC 受保护目录诊断与授权引导 |
| 设置 | 背景通透度、隔离区、自动清理 |
| 菜单栏 | 常驻显示可用空间 |

## 三个核心机制

| 机制 | 说明 |
|---|---|
| **三级判定** | 可重建 / 需确认 / 不可删，依据 Apple 官方对 `~/Library` 各目录的定义 |
| **隔离区** | 移动而非删除，可还原；保留 1 天（可调）后自动清空 |
| **失败诊断** | 删不掉时给出原因与解法：解除锁定、结束占用进程、管理员删除 |

详见 → [决策归档](docs/决策归档.md)

## 安装（给使用者）

下载 `cleanmac-0.1.0.dmg`，把 cleanmac 拖进「应用程序」。

**第一次打开会被系统拦截**——这个版本没做苹果公证（$99/年），提示"无法验证开发者"是正常的。两种解法任选：

1. 右键点击 cleanmac → 「打开」→ 再点「打开」
2. 打开终端执行：`xattr -dr com.apple.quarantine /Applications/cleanmac.app`

**建议**在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中勾选 cleanmac，否则「下载 / 桌面 / 文稿」里的文件扫不到。

## 构建

```bash
bash build.sh          # universal 二进制 + 图标 + Info.plist + ad-hoc 签名
bash tools/package.sh  # 打包 dist/cleanmac-0.1.0.dmg
```

要求 macOS 14+、Xcode 或 Command Line Tools。也可用 Xcode 打开 `Package.swift`。

## 测试

```bash
cleanmac --selftest        # 隔离区往返自测（只动临时目录）
cleanmac --scan-report     # 无界面扫描报告
cleanmac --apps-report     # 应用体积与可移除性
cleanmac --diagnose <path> # 文件标志位与保护判定
```

## 结构

```
├── Package.swift
├── build.sh                  # 编译 + 打包 .app（universal）
├── LICENSE                   # MIT
├── tools/package.sh          # 打包 DMG
├── resources/rules.json      # 规则源数据
├── tools/gen_rules.py        # 规则生成器（改完 JSON 跑一次）
├── docs/
│   ├── 决策归档.md            # 所有定稿决策
│   ├── 清理清单.md            # 46 项分级清单（含 Apple 依据）
│   └── 安全机制.md            # 判定机制详解
└── Sources/cleanmac/         # 11 个源文件
```

## 文档

- [决策归档](docs/决策归档.md) — 定稿决策、被推翻的方案、已知限制
- [清理清单](docs/清理清单.md) — 按「可重建 / 需确认 / 不可删 / 系统级」四级分类
- [安全机制](docs/安全机制.md) — 什么样的文件可以删，以及为什么

## 视觉

Apple 2025 年发布的 **Liquid Glass**，用系统原生 API，不是仿制：

```swift
if #available(macOS 26.0, *) {
    content.glassEffect(.regular, in: .rect(cornerRadius: radius))
} else {
    // macOS 14–15 回退到 ultraThinMaterial
}
```
