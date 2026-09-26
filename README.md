# ETSToolbox

> [!WARNING]
> **由于官方修复，本项目已停用，不再维护。**

ETSToolbox 是面向 Windows 版 E听说客户端的本地扩展实验项目。项目通过 `winmm.dll` 代理加载前端脚本，用于研究桌面客户端的页面注入、本地数据处理和交互自动化。

> [!WARNING]
> **仅用于个人代码学习与本地测试；严禁用于真实评测或影响他人权益。**
>
> 使用场景：请勿在学校、培训机构、正式考试、正式作业、成绩评定、共享设备或公共服务中运行，也不要借此代答、规避录音要求，或向真实平台提交伪造、修改过的成绩。测试应限于本人控制且已获使用许可的设备、账户和数据。
>
> 第三方权利：使用前应核对客户端及平台的许可协议、适用规定和内容权利。不要随项目分发 E听说客户端、其安装包、题库或录音；公开日志和截图前应移除账户、个人信息及其他敏感内容。
>
> 项目关系与许可：本项目是非官方维护分支，与 E听说及其运营方无关联，也未获其认可。仓库中的 MIT 声明仅覆盖维护者有权许可的新增原创代码；上游未声明许可证的代码及第三方软件、商标和内容不因此获得 MIT 授权。
>
> 本警告说明项目的预期用途与风险边界，不改变任何许可证条款，也不能替代权利人的许可或专业法律意见。

## 产品功能

- 按百分比在本地预览听说题目的朗读指标，并为每道题设置独立的随机偏移。
- 在本地结果页调整文本朗读的完整度、准确度、流畅度和逐词颜色。
- 设置作业记录中的提交用时。
- 在独立终端中显示页面能够识别的参考内容，支持听说、选择、填空、完形、阅读、翻译、写作等常见结构。
- 自动处理录音流程：检测录音状态，在客户端允许的 2 秒后停止。
- 用户手动开始整套练习后，按页面实际状态自动执行后续“下一步”。

按 `F1` 打开功能面板，按 `F12` 打开客户端网页开发者工具并查看运行日志。

## 已知限制

- 当前服务端会返回最终题目得分和朗读维度；客户端提交的分数字段不再决定最终记录。
- `1.0.7` 中的“控分”只用于本地界面预览，不会改变服务端保存的总分、完整度、准确度、流畅度或标准度。
- 答案显示仍取决于页面数据或本机已下载元数据中是否存在可识别的参考内容。

## 界面预览

### F1 功能面板

![F1 功能面板](assets/settings-1.0.5.png)

### 答案终端

![答案终端](assets/answer-console-1.0.5.png)

### 文本朗读结果

最终得分、三项指标和逐词颜色来自同一组处理后的数据。

![文本朗读评分结果](assets/reading-score-1.0.6.png)

## 安装流程

### 环境要求

- Windows 10 或 Windows 11
- 已安装 Microsoft Visual C++ 2015–2022 Redistributable
- 当前发布包匹配 x86 版 `ETSShell.exe`

### 安装发行包

1. 从 [Releases](https://github.com/HY916-cn/ETSToolbox/releases) 下载最新的 `ETSToolbox-*-win32.zip`。
2. 完全退出客户端，确认任务管理器中没有 `ETSShell.exe`。
3. 将压缩包完整解压到单独目录，不要直接在压缩包内运行脚本。
4. 打开 PowerShell，进入解压目录后运行：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File '.\install.ps1'
   ```

普通 PowerShell 中运行时，安装器会自动请求管理员权限；在 Windows 的 UAC 提示中选择“是”即可继续。安装器会校验文件、备份现有 DLL 和前端资源，然后复制新版本。安装完成后不会自动启动客户端，可由用户手动测试。默认目标目录为：

```text
C:\Program Files (x86)\ETS
```

不要从第三方网站下载单独 DLL，也不要修改 `System32`、`SysWOW64` 等系统目录。

## 使用方法

1. 启动客户端并按 `F1` 打开面板。
2. 按需设置本地评分预览、随机偏移上限、提交用时、答案终端、自动录音和自动下一步。
3. 随机偏移的单位是百分点。例如基准值为 `80`、偏移上限为 `5` 时，每道题会在 `75%` 至 `85%` 范围内独立取值。
4. 需要查看已识别的参考内容时，启用“显示答案”，再点击“打开答案终端”。
5. 需要自动处理听说流程时，同时启用“自动录音”和“自动下一步”，然后由用户手动点击整套练习的第一次“开始”。

自动流程会持续检查按钮和录音状态。只有录音状态实际生效后才开始 2 秒计时；页面没有响应时会按受控间隔重试。运行详情可在 `F12` 控制台中查看。

答案匹配只读取 `%APPDATA%\ETS` 中已由客户端下载的 `content.json` 和 `content2.json`，不会联网查询。资源尚未下载、缓存已清理或元数据没有参考内容时，终端会显示未找到。

## 开发指南

### 项目组成

- 本仓库：原生加载器、本地服务、安装与诊断脚本。
- [ETSToolbox-js](https://github.com/HY916-cn/ETSToolbox-js)：设置面板、页面处理和自动流程。

### 构建 Windows DLL

需要 Visual Studio C++、Windows SDK、CMake、PowerShell、Git 和 vcpkg。克隆仓库时应初始化子模块：

```powershell
git clone --recurse-submodules https://github.com/HY916-cn/ETSToolbox.git
Set-Location '.\ETSToolbox'
$env:VCPKG_ROOT = 'C:\File\build\vcpkg'
powershell -NoProfile -ExecutionPolicy Bypass -File '.\scripts\build-release.ps1' -VcpkgRoot $env:VCPKG_ROOT
```

构建脚本会检查本机 `ETSShell.exe` 的 PE 架构、准备匹配架构的 Detours、使用 MSVC Release CRT 构建，并生成依赖检查报告。确认全部检查通过后，可添加 `-Deploy` 参数进行安装。

### 构建前端

前端需要 Node.js 20 或更高版本：

```bash
git clone https://github.com/HY916-cn/ETSToolbox-js.git
cd ETSToolbox-js
npm ci
npm test
npm run build
```

### 验证安装器

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\scripts\test-install.ps1'
```

### 收集启动诊断

如果客户端启动后立即退出，请先保持现场并运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\scripts\collect-crash-diagnostics.ps1'
```

诊断脚本只读取本机状态，不会启动或修改客户端。结果保存在当前目录的 `ETSToolbox-crash-diagnostics.txt`。

## 实现说明

- `winmm.dll` 使用 Win32 Release 和 MSVC `/MD` 构建，不应依赖 `VCRUNTIME140D.dll`、`MSVCP140D.dll` 或 `ucrtbased.dll`。
- 本地评分预览只作用于已识别的听说练习。服务端最终记录以 `/m/audio/sync-v2` 的返回值为准，不保证与本地预览一致。
- 文本朗读会在评测 XML 写盘和上传前同步写入总分、三项指标和逐词分值。每个普通单词独立计算命中概率和实际分值，颜色由客户端原生规则渲染。
- 作业提交用时只处理 `m/homework/set-use-time`。
- 自动流程只识别听说页面操作栏中的录音、停止录音和下一步按钮。
- 答案提取支持常见题型和嵌套字段。页面只提供题干时，本地服务会在 `%APPDATA%\ETS` 中匹配已经下载的题目元数据。
- 本地 HTTP 服务只监听 `127.0.0.1`；答案终端只能由安装目录内的固定启动脚本打开。
- 当前发布 DLL 为 x86，是依据实测 `ETSShell.exe` 的 PE 架构选择，不依据安装目录名称推断。

更完整的 DLL 构建和依赖检查说明见 [WINDOWS-RELEASE.md](WINDOWS-RELEASE.md)。

## 许可证

本维护分支新增的原创代码以 [MIT License](LICENSE) 提供。上游仓库没有声明许可证，因此上游既有代码的权利状态不会因本文件而改变；MIT 授权仅覆盖维护者有权许可的新增内容。
