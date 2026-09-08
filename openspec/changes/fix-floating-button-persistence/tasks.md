## 1. 修复 SettingsStore 保存功能

- [x] 1.1 在 SettingsStore.swift 顶部添加 `SQLITE_TRANSIENT` 常量定义（值为 -3）
- [x] 1.2 修改 `saveConfig` 方法中的 `sqlite3_bind_text` 调用，将 destructor 参数从 `nil` 改为 `SQLITE_TRANSIENT`

## 2. 修复 SettingsStore 加载功能

- [x] 2.1 修改 `loadConfig` 方法中的 `sqlite3_bind_text` 调用，将 destructor 参数从 `nil` 改为 `SQLITE_TRANSIENT`
- [x] 2.2 验证 `getString` 辅助方法的正确性，确保字符串解码无误

## 3. 验证与测试

- [ ] 3.1 运行应用测试悬浮球配置保存功能
- [ ] 3.2 重启应用验证配置是否正确恢复
- [ ] 3.3 测试各种配置修改（颜色、大小、透明度等）
- [ ] 3.4 验证首次启动使用默认配置的逻辑

## 3. 验证与测试

- [ ] 3.1 运行应用测试悬浮球配置保存功能
- [ ] 3.2 重启应用验证配置是否正确恢复
- [ ] 3.3 测试各种配置修改（颜色、大小、透明度等）
- [ ] 3.4 验证首次启动使用默认配置的逻辑
