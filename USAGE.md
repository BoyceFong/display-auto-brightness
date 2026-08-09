# 外接显示器自动亮度调节 — 使用文档

## 这是什么

让外接显示器按时间自动调节**真实背光亮度**的工具。当前管理两台：**MateView** 和 **U27U2D**（各自独立亮度曲线）。

MateView 本身没有环境光传感器，也不提供官方自动亮度功能；华为官方文档甚至称亮度"无法在主机端调节"。但实测发现：通过 **USB-C 直连**时，显示器的 **DDC/CI** 通道是可用的，macOS 上的 `m1ddc` 工具可以直接读写显示器的真实亮度（效果等同于用显示器摇杆在 OSD 里调亮度，而非软件压暗画面）。U27U2D 同样实测支持 DDC 读写。

本方案 = `m1ddc`（DDC/CI 读写） + 一个定时脚本（按时间曲线计算目标亮度） + launchd（每分钟校准一次）。

## 亮度曲线

每台显示器使用独立曲线（当前配置）：

| 时间段 | MateView | U27U2D |
|---|---|---|
| 07:30 – 12:00 | 45%（恒定） | 25%（恒定） |
| 12:00 – 19:00 | 45% 线性缓降到 20% | 25% 线性缓降到 0% |
| 19:00 – 次日 07:30 | 20% | 0% |

中间时段约每 17 分钟降 1%，无感过渡。

## 文件结构

```
mateview-auto-brightness/
├── m1ddc                          # DDC/CI 命令行工具（编译产物，需自行 build）
├── m1ddc-1.1.0/                   # m1ddc 源码（已加补丁：DDC 应答校验 + 失败重试，重新编译用）
├── mateview-brightness.sh         # 核心脚本：计算目标亮度、检测手动调节、写入显示器
├── mateview-brightness-ctl        # 控制脚本：start/stop/restart/status/install/uninstall
├── com.boyce.mateview-brightness.plist  # launchd 定时任务配置（每 60 秒）
├── mateview-brightness.log        # 调整记录日志（运行时生成）
├── mateview-brightness.state      # 手动调节检测状态（运行时生成）
├── launchd.out.log / launchd.err.log    # 定时任务的 stdout/stderr（运行时生成）
└── USAGE.md                       # 本文档
```

## 一次性安装（开机自启）

若是新克隆的仓库，先构建 `m1ddc`（需要 Xcode Command Line Tools）：

```bash
cd m1ddc-1.1.0 && make && cp m1ddc ../ && cd ..
```

然后安装：

```bash
/Users/boyce/Misc/code/dev/mateview-auto-brightness/mateview-brightness-ctl install
```

这会把定时任务配置复制到 `~/Library/LaunchAgents/` 并启动，之后每次登录系统自动运行。只需执行一次。

## 日常使用：一行命令起停

```bash
cd /Users/boyce/Misc/code/dev/mateview-auto-brightness

./mateview-brightness-ctl start     # 启动自动调光
./mateview-brightness-ctl stop      # 停止自动调光（当前会话）
./mateview-brightness-ctl restart   # 重启（同时清除手动调节暂停）
./mateview-brightness-ctl status    # 查看运行状态、当前亮度、最近调整记录
```

注意 `stop` 与 `uninstall` 的区别：

- `stop`：**仅当前会话停止**。由于已安装登录自启，下次登录系统会自动恢复运行。适合临时暂停，用完 `start` 恢复即可。
- `restart`：**重启并清除手动调节暂停**。如果你手动调过亮度导致某台显示器被暂停，`restart` 会立即恢复自动调光。
- `uninstall`：**彻底停用**。停止服务并移除开机自启，重启后也不会再运行；想恢复时执行一次 `install` 即可。

### 配置短命令（可选，实现真正的"一键"）

在 `~/.zshrc` 中加入别名，之后任意目录下 `mvb stop` / `mvb start` / `mvb status` 即可：

```bash
echo "alias mvb='/Users/boyce/Misc/code/dev/mateview-auto-brightness/mateview-brightness-ctl'" >> ~/.zshrc && source ~/.zshrc
```

### 手动调节亮度

直接用显示器摇杆调节亮度即可，无需先停止服务。脚本检测到手动调节后会**自动暂停该显示器的自动调光**，直到次日或手动 `restart`。DDC 读数毛刺已在工具层根治（m1ddc 对每次读取做应答校验，无效应答自动重试，彻底失败则报错而非返回假值）；在此之上，异常值仍需**连续 3 次校准（约 3 分钟）保持稳定**才会判定为手动调节并暂停，作为双重保险。确认期间不会覆盖你手动设置的值。

- 暂停是**逐屏独立**的：只暂停被手动调节的那台，另一台不受影响继续自动调光。
- 次日首次运行时自动恢复。
- 想立即恢复：`mvb restart`。
- 查看暂停状态：`mvb status` 会标注"已暂停-手动调节"。

## 自定义亮度曲线

亮度曲线由三个时间段定义：07:30 前和 19:00 后为夜间值，07:30–12:00 为白天平台值，12:00–19:00 从白天值线性降到夜间值。每台显示器独立配置。

换算规则：分钟数 = 小时 × 60 + 分钟（如 08:30 = 510）。改完无需重启服务，下一个 60 秒周期自动生效。

### 修改曲线参数 / 增删显示器

`mateview-brightness.sh` 和 `mateview-brightness-ctl` 两个文件顶部各有一行显示器配置，格式为 `名字:白天亮度:夜间亮度`：

```bash
DISPLAYS="MateView:45:20 U27U2D:25:0"
```

- 调亮度：直接改对应条目的白天/夜间数值（0~100）。
- 移除某台：删掉对应条目。
- 新增一台：先用 `./m1ddc display list` 查看显示器名字，再用 `./m1ddc display <编号> get luminance` 确认支持 DDC 后，以 `名字:白天:夜间` 加入。
- 两个文件中的配置需保持一致。改完下一个 60 秒周期自动生效。

## 常见问题

**Q: 状态显示某台显示器"未连接"？**
确认该显示器已开机且连接线正常（DDC 依赖 USB-C 直连或支持 DDC 的链路，HDMI 转接可能不可用）。可运行 `./m1ddc display list` 检查系统是否能识别。未连接的显示器会被自动跳过，不影响另一台。

**Q: 亮度调不动了？**
检查系统是否给 MateView 开启了 HDR——HDR 模式下显示器会锁定亮度（OSD 中亮度置灰），关闭 HDR 即可恢复。

**Q: 重启后自动调光没运行？**
确认执行过一次 `install`。运行 `./mateview-brightness-ctl status` 查看状态，未运行时执行 `start`。若 `start` 报 I/O 错误，是 launchd 瞬态问题，等几分钟重试或重启 Mac 即可。

**Q: 手动调了亮度后自动调光不生效了？**
这是预期行为：脚本检测到手动调节（连续约 3 分钟确认）后会暂停该显示器的自动调光，直到次日或 `restart`。运行 `./mateview-brightness-ctl status` 可查看暂停状态。注意"次日"以午夜为界：凌晨触发的暂停同样在当天午夜后解除。

**Q: 换了 Mac 或升级了大的 macOS 版本后 m1ddc 报错？**
重新编译：`cd m1ddc-1.1.0 && make && cp m1ddc ../`（需要 Xcode Command Line Tools）。

**Q: 日志里出现可疑读数（如某台显示器一直是 0）？**
m1ddc 已内置应答校验（地址/应答类型/结果码/opcode 回显/校验和）与最多 3 次重试：偶发的无效应答会被重试恢复，彻底失败时输出错误信息并以非零退出，脚本对非数字读数直接跳过，不会产生错误写入或误判。若某台显示器持续读取失败或读数与 OSD 显示长期不符，先检查连接线缆，仍不行则可能是该显示器 DDC 实现不完整。

**Q: 会不会伤显示器？**
DDC/CI 是显示器标准协议，等效于手动调 OSD 亮度；且脚本只在亮度值真正变化时才写入（白天平台期不写，下降期约 17 分钟写一次），写入频率极低。手动调节暂停后更是完全不写入。

## 彻底停用与卸载

**彻底停用**（保留所有文件，随时可恢复）：

```bash
/Users/boyce/Misc/code/dev/mateview-auto-brightness/mateview-brightness-ctl uninstall
```

执行后服务停止、开机自启被移除，重启后不会再运行。想恢复时执行一次 `install` 即可。

**完全卸载**（删除所有文件）：

```bash
cd /Users/boyce/Misc/code/dev/mateview-auto-brightness
./mateview-brightness-ctl uninstall        # 停止服务并移除开机自启
cd .. && rm -rf mateview-auto-brightness   # 删除整个项目目录
```

如配置过 `mvb` 别名，记得从 `~/.zshrc` 中删除对应行。
