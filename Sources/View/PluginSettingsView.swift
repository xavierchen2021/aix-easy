import SwiftUI

struct PluginSettingsView: View {
    @ObservedObject private var pluginManager = PluginManager.shared
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @State private var selectedPluginId: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: L10n.tr("plugin.installedPlugins"), icon: "puzzlepiece.extension") {
                    VStack(alignment: .leading, spacing: 12) {
                        if pluginManager.registeredPlugins.isEmpty {
                            Text(L10n.tr("plugin.noPlugins"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(sortedPlugins, id: \.pluginId) { plugin in
                                PluginRow(plugin: plugin)
                                    .onTapGesture {
                                        selectedPluginId = plugin.pluginId
                                    }
                            }
                        }
                    }
                }
                
                if let selectedPluginId = selectedPluginId,
                   let plugin = pluginManager.registeredPlugins[selectedPluginId] {
                    SettingsSection(title: L10n.tr("plugin.details"), icon: "info.circle") {
                        VStack(alignment: .leading, spacing: 16) {
                            SettingsRow(
                                title: L10n.tr("plugin.name"),
                                description: L10n.tr("plugin.nameDesc")
                            ) {
                                Text(plugin.displayName)
                                    .font(.body)
                                    .foregroundColor(.primary)
                            }
                            
                            SettingsRow(
                                title: L10n.tr("plugin.id"),
                                description: L10n.tr("plugin.idDesc")
                            ) {
                                Text(plugin.pluginId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: 200, alignment: .trailing)
                            }
                            
                            SettingsRow(
                                title: L10n.tr("plugin.description"),
                                description: L10n.tr("plugin.descriptionDesc")
                            ) {
                                Text(plugin.description)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: 250, alignment: .trailing)
                            }
                            
                            SettingsRow(
                                title: L10n.tr("plugin.enabledStatus"),
                                description: L10n.tr("plugin.enabledStatusDesc")
                            ) {
                                Toggle("", isOn: Binding(
                                    get: { plugin.isEnabled },
                                    set: { _ in
                                        if plugin.isEnabled {
                                            pluginManager.disable(pluginId: plugin.pluginId)
                                        } else {
                                            pluginManager.enable(pluginId: plugin.pluginId)
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private var sortedPlugins: [PluginAction] {
        pluginManager.registeredPlugins.values.sorted { $0.displayName < $1.displayName }
    }
}

struct PluginRow: View {
    let plugin: PluginAction
    @ObservedObject private var pluginManager = PluginManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            if let iconName = plugin.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(plugin.isEnabled ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                    )
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 20))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(plugin.isEnabled ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.displayName)
                    .font(.system(size: 14, weight: .medium))
                
                Text(plugin.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { _ in
                    if plugin.isEnabled {
                        pluginManager.disable(pluginId: plugin.pluginId)
                    } else {
                        pluginManager.enable(pluginId: plugin.pluginId)
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct ButtonPluginRow: View {
    let buttonIndex: Int
    @ObservedObject private var configManager = FloatingButtonConfigManager.shared
    @ObservedObject private var pluginManager = PluginManager.shared
    @State private var showPluginPicker = false
    
    var body: some View {
        let currentAction = configManager.config.buttonActions[buttonIndex] ?? .none
        let currentPluginId = configManager.config.buttonPluginIds[buttonIndex]
        let currentPlugin = currentPluginId != nil ? pluginManager.registeredPlugins[currentPluginId!] : nil
        
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("按钮 \(buttonIndex + 1)")
                    .font(.system(size: 14, weight: .medium))
                
                if let plugin = currentPlugin {
                    Text(plugin.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(currentAction.localizedName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Picker("", selection: Binding(
                get: {
                    if let pluginId = currentPluginId {
                        return "plugin:\(pluginId)"
                    } else {
                        return "action:\(currentAction.rawValue)"
                    }
                },
                set: { newValue in
                    if newValue.hasPrefix("plugin:") {
                        let pluginId = String(newValue.dropFirst(7))
                        configManager.updateButtonAction(index: buttonIndex, action: .plugin)
                        configManager.updateButtonPluginId(index: buttonIndex, pluginId: pluginId)
                    } else {
                        let actionString = String(newValue.dropFirst(7))
                        if let action = FloatingButtonConfig.ButtonAction(rawValue: actionString) {
                            configManager.updateButtonAction(index: buttonIndex, action: action)
                            configManager.updateButtonPluginId(index: buttonIndex, pluginId: nil)
                        }
                    }
                }
            )) {
                Text(L10n.tr("common.none")).tag("action:无")
                
                ForEach(FloatingButtonConfig.ButtonAction.allCases.filter { $0 != .plugin }, id: \.self) { action in
                    Text(action.localizedName).tag("action:\(action.rawValue)")
                }
                
                Divider()
                
                Text(L10n.tr("plugin.plugin")).tag("plugin:divider")
                
                ForEach(pluginManager.registeredPlugins.values.sorted { $0.displayName < $1.displayName }, id: \.pluginId) { plugin in
                    Text(plugin.displayName).tag("plugin:\(plugin.pluginId)")
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 180)
        }
        .padding(.vertical, 8)
    }
}
