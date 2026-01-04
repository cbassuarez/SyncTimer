import SwiftUI

/// Small, focused settings window that reuses your existing settings pager.
struct SettingsWindow: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var syncSettings: SyncSettings

    @State private var page: Int = 0
    @State private var editingTarget: EditableField? = nil
    @State private var inputText: String = ""
    @State private var isEnteringField: Bool = false
    @State private var showBadPortError: Bool = false

    var body: some View {
        SettingsPagerCard(page: $page,
                          editingTarget: $editingTarget,
                          inputText: $inputText,
                          isEnteringField: $isEnteringField,
                          showBadPortError: $showBadPortError)
        .frame(minWidth: 480, minHeight: 520)
        .navigationTitle("Settings")
    }
}
