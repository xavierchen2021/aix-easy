## ADDED Requirements

### Requirement: 配置保存功能

当用户修改悬浮球的颜色、大小或其他个性化设置时，系统 SHALL 立即将配置保存到 SQLite 数据库。

#### Scenario: 用户修改悬浮球颜色
- **WHEN** 用户在设置界面选择新的悬浮球颜色
- **THEN** 系统调用 `FloatingButtonConfigManager.updateColorScheme()` 方法
- **AND** 方法内部调用 `save()` 将配置序列化并保存到数据库
- **AND** 数据库中的 `floatingButtonConfig` 记录被更新

#### Scenario: 用户修改悬浮球大小
- **WHEN** 用户在设置界面调整悬浮球大小
- **THEN** 系统调用 `FloatingButtonConfigManager.updateSize()` 方法
- **AND** 大小值被限制在 `FloatingButtonConfig.minSize` (30) 和 `FloatingButtonConfig.maxSize` (150) 范围内
- **AND** 新的配置值被保存到数据库

#### Scenario: 配置保存失败处理
- **WHEN** 数据库保存操作返回错误
- **THEN** 系统记录错误日志（使用 `Logger`）
- **AND** 错误被静默处理，不影响应用继续运行

### Requirement: 配置加载功能

当应用启动时，系统 SHALL 从 SQLite 数据库加载用户保存的悬浮球配置。

#### Scenario: 正常启动加载配置
- **WHEN** 应用启动并初始化 `FloatingButtonConfigManager`
- **THEN** 系统调用 `store.loadConfig(key: "floatingButtonConfig")` 从数据库读取
- **AND** 如果数据库中存在有效配置，JSON 数据被解码为 `FloatingButtonConfig` 对象
- **AND** 悬浮球使用加载的颜色和大小设置显示

#### Scenario: 首次启动使用默认配置
- **WHEN** 应用首次启动且数据库中无配置记录
- **THEN** 系统使用 `FloatingButtonConfig.default` 作为初始配置
- **AND** 悬浮球使用默认的海洋蓝颜色和 50pt 大小

#### Scenario: 配置数据损坏处理
- **WHEN** 数据库中的配置 JSON 数据损坏或无法解码
- **THEN** 系统捕获解码异常
- **AND** 回退使用 `FloatingButtonConfig.default`
- **AND** 记录错误日志但不崩溃

### Requirement: 配置持久化完整性

系统 SHALL 确保配置的保存和加载操作使用正确的 SQLite 绑定方式，防止数据丢失或损坏。

#### Scenario: SQLite 文本绑定使用正确生命周期
- **WHEN** `SettingsStore.saveConfig` 执行
- **THEN** `sqlite3_bind_text` 的 destructor 参数使用 `SQLITE_TRANSIENT`
- **AND** SQLite 内部复制字符串数据，不依赖传入指针的生命周期

#### Scenario: SQLite 查询绑定使用正确生命周期
- **WHEN** `SettingsStore.loadConfig` 执行
- **THEN** `sqlite3_bind_text` 正确绑定查询参数
- **AND** 指针在 SQLite 执行期间保持有效

#### Scenario: 配置跨会话保持
- **WHEN** 用户修改悬浮球设置后关闭应用
- **AND** 重新打开应用
- **THEN** 悬浮球显示用户上次设置的顔色
- **AND** 悬浮球显示用户上次设置的大小
