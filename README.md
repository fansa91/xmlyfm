# xmlyfm · 播客 Flutter 客户端

基于 [ultrazg/xyz](https://github.com/ultrazg/xyz) 项目抓取的小宇宙FM 官方接口开发的第三方播客客户端，**直连官方 API，无需部署后端**。

- 接口：`https://api.xiaoyuzhoufm.com`（小宇宙官方 App 接口，请求头仿官方 iOS 客户端）
- 登录：手机号 + 短信验证码（官方 `podcaster-api.xiaoyuzhoufm.com` 登录接口）
- UI：Material 3，动态取色 / 自定义主题色 / 纯黑模式，手机底部导航 + 桌面端左侧栏

> 免责声明：本项目仅供学习研究使用，请遵守国家法律法规。

## 功能

- **发现**：编辑精选、大家都在听（支持换一换）、最热榜 / 锋芒榜 / 新星榜
- **订阅**：我的订阅、订阅更新动态，订阅/取消订阅/星标
- **搜索**：节目 / 单集搜索，热词推荐
- **播客详情**：节目信息、单集列表（新到旧分页）、最受欢迎单集、相关节目推荐
- **播放器**：单集播放、断点续播、播放进度云同步、倍速（0.5x–3.0x）、4 种播放模式、简介/ shownotes 查看、iOS 锁屏信息同步
- **评论**：单集评论列表（最热/最新）、发表评论、点赞
- **我的**：短信登录、我的收藏、收听历史、主题设置、退出登录

## 构建

推送 tag 即触发 GitHub Actions 多平台构建（Android APK / iOS IPA（未签名）/ macOS dmg / Windows zip，Linux 暂略）：

```bash
git tag v1.0.0 && git push origin v1.0.0
```

## 开发说明

接口抓包定义见 [ultrazg/xyz](https://github.com/ultrazg/xyz) 的 `handlers/` 与 `doc/docs/`。App 内 `lib/core/api.dart` 的请求头照抄该项目抓到的官方 App 请求头；官方接口变更时同步更新即可。
