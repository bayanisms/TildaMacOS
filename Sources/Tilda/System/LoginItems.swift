import ServiceManagement

protocol LoginItemControlling {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

struct SystemLoginItemController: LoginItemControlling {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
