<p align="center">
  <img src="assets/icon/app_icon.png" width="128" alt="xmlyfm 图标">
</p>

# xmlyfm（喜马拉雅第三方客户端）

非官方第三方 Flutter 客户端，**访客态浏览 + 播放**：无需登录、无自建后端，直连喜马拉雅官方接口（`mobile.ximalaya.com` / `search.ximalaya.com`，接口整理自官方 App 逆向文档）。

- UI：原生 Material 3，动态取色 / 自定义种子色 / 纯黑模式
- 布局自适应：手机底部导航；宽屏（≥600）左侧 NavigationRail，专辑页 / 播放页双栏
- 平台：Android / iOS / macOS / Windows

> 免责声明：本项目仅供学习研究使用，与喜马拉雅官方无关，请遵守国家法律法规。

## 功能

- **首页**：推荐信息流（下拉刷新 + 分页）
- **分类**：全量分类页签与各分类内容页
- **搜索**：综合搜索（专辑 / 声音 / 主播等分栏）、搜索联想、热词与热搜榜
- **专辑详情**：封面信息、简介、节目列表（分页加载、正序 / 倒序切换）
- **播放器**：多档音质（标准 / 高清 / 臻品 / 无损等，按声音实际支持情况）、倍速、播放队列、断点续播（本地记录进度）、播放历史
- **收藏**：收藏专辑与声音（本地持久化）
- **下载管理**：
  - 单集下载与多选批量下载，队列并发与进度、暂停 / 继续 / 重试，任务持久化
  - 下载文件名格式可在设置中自定义（变量：`{album}` 专辑、`{title}` 标题、`{index}` 集序号、`{trackId}`、`{author}` 主播）
  - 下载完成后将标签写入文件本体（MP3 的 ID3：标题 / 专辑 / 主播 / 集序号 / 封面图 / 简介 / 分类 / 发布日期 / 时长等；M4A 容器暂不写本体标签，信息保留在下载管理中）
  - 默认下载路径可在设置中修改（iOS 除外，iOS 固定使用应用沙盒目录）
  - 已下载的声音优先本地播放，断网可听

## 已知限制（访客态与服务端规则，非客户端缺陷）

- 付费声音仅提供约 180 秒试听，不可下载完整文件，客户端会明确标记「试听」
- 部分播放链接受服务端地域限制（中国大陆以外可能无法播放）
- 综合搜索接口偶受服务端风控影响，命中时结果为空，可稍后重试

## 构建与发布

版本号由 **git tag** 决定：推送 `v*` 标签触发 GitHub Actions 多平台构建（`.github/workflows/release.yml`），CI 从标签解析版本号（不足三段补齐，如 `v0.1` → `0.1.0`），构建号取 Actions 的 run number；`pubspec.yaml` 中的版本仅为占位。

产物：Android APK（分架构）/ iOS IPA（未签名）/ macOS DMG / Windows ZIP。

Android 固定签名（可选）：在仓库 Settings → Secrets 中配置以下变量后，Release 构建将使用固定钥匙签名（可覆盖升级）；未配置时每次构建临时自签。

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

本地开发：

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## 技术说明

- 数据层直连官方接口，播放链接按声音类型三路解析：专辑列表直带链接 → 播放页 baseInfo 接口（v4 签名已实现）→ 付费声音走试听标记
- 本地数据（收藏 / 历史 / 进度 / 下载任务 / 设置）使用 SharedPreferences 持久化
- 界面全程使用原生 Material 3 组件，颜色走 ColorScheme 动态取色
