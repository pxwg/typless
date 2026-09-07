import SwiftUI

struct QwenSettingsSection: View {
  @ObservedObject var model: QwenSettingsModel
  let connectionStatus: String
  let isTestingConnection: Bool
  let testConnection: () -> Void
  @State private var confirmsRemoval = false

  var body: some View {
    Section {
      SecureField("API Key", text: $model.apiKeyInput,
        prompt: Text(model.hasSavedKey ? "已保存；粘贴新密钥可替换" : "粘贴你的百炼 API Key"))
        .textFieldStyle(.roundedBorder)
        .privacySensitive()
        .onSubmit { model.save() }
      Picker("服务地域", selection: $model.region) {
        ForEach(QwenRegion.allCases) { Text($0.title).tag($0) }
      }
      DisclosureGroup("高级连接设置") {
        TextField("业务空间 ID", text: $model.workspaceID, prompt: Text("可选"))
        TextField("连接地址", text: $model.endpoint, prompt: Text("留空使用所选地域的默认地址"))
        Text("仅在使用业务空间或自定义服务时填写。密钥和录音将发送到此地址；远程地址必须使用 wss://。")
          .font(.caption).foregroundStyle(.secondary)
      }
      DisclosureGroup("System Prompt（智能整理）") {
        VStack(alignment: .leading, spacing: 10) {
          Text("自定义口述的整理方式，替换默认整理规则。保存后从下一次录音生效；忠实转写直接使用原始识别结果。")
            .font(.caption).foregroundStyle(.secondary)
          TextEditor(text: $model.systemPrompt)
            .font(.system(.body, design: .monospaced))
            .frame(height: 220)
            .padding(6)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .accessibilityLabel("智能整理 System Prompt")
          HStack {
            Button("恢复默认") { model.restoreDefaultSystemPrompt() }
            Text("留空也会使用默认规则；修改后请点击保存。")
              .font(.caption).foregroundStyle(.secondary)
          }
          DisclosureGroup("始终保留的转写约束") {
            Text(QwenProtocol.dictationBoundary)
              .font(.caption).foregroundStyle(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      HStack {
        Button("保存") { model.save() }
          .buttonStyle(.borderedProminent)
          .disabled(!model.hasUnsavedChanges)
        Button("测试连接", action: testConnection)
          .disabled(!model.canTestConnection || isTestingConnection)
        if isTestingConnection { ProgressView().controlSize(.small) }
        Spacer()
        if model.hasSavedKey {
          Button("删除密钥…", role: .destructive) { confirmsRemoval = true }
        }
      }
      if !model.statusMessage.isEmpty {
        Text(model.statusMessage).foregroundStyle(.secondary)
      }
      if !connectionStatus.isEmpty {
        Text(connectionStatus).foregroundStyle(.secondary).textSelection(.enabled)
      }
    } header: {
      Text("语音模型")
    } footer: {
      Text("密钥保存在本机钥匙串中，重启后仍可使用。请选择与密钥一致的地域；录音将发送至对应的 Qwen 服务。")
    }
    .onAppear { model.refreshCredentialStatus() }
    .alert("删除已保存的 API Key？", isPresented: $confirmsRemoval) {
      Button("取消", role: .cancel) {}
      Button("删除", role: .destructive) { model.removeAPIKey() }
    } message: {
      Text("删除后需要重新粘贴并保存密钥，才能使用语音输入。")
    }
  }
}
