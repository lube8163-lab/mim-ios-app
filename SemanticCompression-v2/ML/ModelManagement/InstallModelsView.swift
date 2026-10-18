import SwiftUI
struct InstallModelsView: View {
    @ObservedObject var modelManager: ModelManager
    var body: some View { NavigationStack { ModelManagementView().environmentObject(modelManager) } }
}
