//
//  Manager.swift
//  Potatso
//
//  Created by LEI on 4/7/16.
//  Copyright © 2016 TouchingApp. All rights reserved.
//

import PotatsoBase
import PotatsoModel
import RealmSwift
import KissXML
import NetworkExtension
import ICSMainFramework
import MMWormhole

public enum ManagerError: ErrorType {
    case InvalidProvider
    case VPNStartFail
}

public enum VPNStatus : Int {
    case Off
    case Connecting
    case On
    case Disconnecting
}


public let kDefaultGroupIdentifier = "defaultGroup"
public let kDefaultGroupName = "defaultGroupName"
private let statusIdentifier = "status"
public let kProxyServiceVPNStatusNotification = "kProxyServiceVPNStatusNotification"

public class Manager {
    
    public static let sharedManager = Manager()
    
    public private(set) var vpnStatus = VPNStatus.Off {
        didSet {
            NSNotificationCenter.defaultCenter().postNotificationName(kProxyServiceVPNStatusNotification, object: nil)
        }
    }
    
    public let wormhole = MMWormhole(applicationGroupIdentifier: sharedGroupIdentifier, optionalDirectory: "wormhole")

    var observerAdded: Bool = false
    
    public var defaultConfigGroup: ConfigurationGroup {
        return getDefaultConfigGroup()
    }

    private init() {
        loadProviderManager { (manager) -> Void in
            if let manager = manager {
                self.updateVPNStatus(manager)
                if self.vpnStatus == .On {
                    self.observerAdded = true
                    NSNotificationCenter.defaultCenter().addObserverForName(NEVPNStatusDidChangeNotification, object: manager.connection, queue: NSOperationQueue.mainQueue(), usingBlock: { [unowned self] (notification) -> Void in
                        self.updateVPNStatus(manager)
                        })
                }
            }
        }
    }
    
    func addVPNStatusObserver() {
        guard !observerAdded else{
            return
        }
        loadProviderManager { [unowned self] (manager) -> Void in
            if let manager = manager {
                self.observerAdded = true
                NSNotificationCenter.defaultCenter().addObserverForName(NEVPNStatusDidChangeNotification, object: manager.connection, queue: NSOperationQueue.mainQueue(), usingBlock: { [unowned self] (notification) -> Void in
                    self.updateVPNStatus(manager)
                })
            }
        }
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func updateVPNStatus(manager: NEVPNManager) {
        print("updateVPNStatus:", manager.connection.status.rawValue)
        switch manager.connection.status {
        case .Connected:
            self.vpnStatus = .On
        case .Connecting, .Reasserting:
            self.vpnStatus = .Connecting
        case .Disconnecting:
            self.vpnStatus = .Disconnecting
        case .Disconnected, .Invalid:
            self.vpnStatus = .Off
        }
    }

    public func switchVPN(completion: ((NETunnelProviderManager?, ErrorType?) -> Void)? = nil) {
        loadProviderManager { [unowned self] (manager) in
            if let manager = manager {
                self.updateVPNStatus(manager)
            }
            let current = self.vpnStatus
            guard current != .Connecting && current != .Disconnecting else {
                return
            }
            if current == .Off {
                self.startVPN { (manager, error) -> Void in
                    completion?(manager, error)
                }
            }else {
                self.stopVPN()
                completion?(nil, nil)
            }

        }
    }
    
    public func switchVPNFromTodayWidget(context: NSExtensionContext) {
        if let url = NSURL(string: "mume://switch") {
            context.openURL(url, completionHandler: nil)
        }
    }
    
    public func setup() {
        setupDefaultReaml()
        do {
            try copyGEOIPData()
        }catch{
            print("copyGEOIPData fail")
        }
        do {
            try copyTemplateData()
        }catch{
            print("copyTemplateData fail")
        }
    }

    func copyGEOIPData() throws {
        let toURL = Potatso.sharedUrl().URLByAppendingPathComponent("GeoLite2-Country.mmdb")

        guard let fromURL = NSBundle.mainBundle().URLForResource("GeoLite2-Country", withExtension: "mmdb") else {
            let MaxmindLastModifiedKey = "MaxmindLastModifiedKey"
            let lastM = Potatso.sharedUserDefaults().stringForKey(MaxmindLastModifiedKey) ?? "Tue, 20 Dec 2016 12:53:05 GMT"
            
            let url = NSURL(string: "https://mumevpn.com/ios/GeoLite2-Country.mmdb")
            let request = NSMutableURLRequest(URL: url!)
            request.setValue(lastM, forHTTPHeaderField: "If-Modified-Since")
            let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {data, response, error in
                guard let data = data where error == nil else {
                    print("Download GeoLite2-Country.mmdb error: " + (error?.description ?? ""))
                    return
                }
                if let r = response as? NSHTTPURLResponse {
                    if (r.statusCode == 200 && data.length > 1024) {
                        let result = data.writeToURL(toURL!, atomically: true)
                        if result {
                            let thisM = r.allHeaderFields["Last-Modified"];
                            if let m = thisM {
                                Potatso.sharedUserDefaults().setObject(m, forKey: MaxmindLastModifiedKey)
                            }
                            print("writeToFile GeoLite2-Country.mmdb: OK")
                        } else {
                            print("writeToFile GeoLite2-Country.mmdb: failed")
                        }
                    } else {
                        print("Download GeoLite2-Country.mmdb no update maybe: " + (r.description))
                    }
                } else {
                    print("Download GeoLite2-Country.mmdb bad responese: " + (response?.description ?? ""))
                }
            }
            task.resume()
            return
        }
        if NSFileManager.defaultManager().fileExistsAtPath(fromURL.path!) {
            try NSFileManager.defaultManager().copyItemAtURL(fromURL, toURL: toURL!)
        }
    }

    func copyTemplateData() throws {
        guard let bundleURL = NSBundle.mainBundle().URLForResource("template", withExtension: "bundle") else {
            return
        }
        let fm = NSFileManager.defaultManager()
        let toDirectoryURL = Potatso.sharedUrl().URLByAppendingPathComponent("httptemplate")
        if !fm.fileExistsAtPath(toDirectoryURL!.path!) {
            try fm.createDirectoryAtURL(toDirectoryURL!, withIntermediateDirectories: true, attributes: nil)
        }
        for file in try fm.contentsOfDirectoryAtPath(bundleURL.path!) {
            let destURL = toDirectoryURL!.URLByAppendingPathComponent(file)
            let dataURL = bundleURL.URLByAppendingPathComponent(file)
            if NSFileManager.defaultManager().fileExistsAtPath(dataURL!.path!) {
                if NSFileManager.defaultManager().fileExistsAtPath(destURL!.path!) {
                    try NSFileManager.defaultManager().removeItemAtURL(destURL!)
                }
                try fm.copyItemAtURL(dataURL!, toURL: destURL!)
            }
        }
    }

    private func getDefaultConfigGroup() -> ConfigurationGroup {
        if let groupUUID = Potatso.sharedUserDefaults().stringForKey(kDefaultGroupIdentifier), let group = DBUtils.get(groupUUID, type: ConfigurationGroup.self) {
            return group
        } else {
            var group: ConfigurationGroup
            if let g = DBUtils.allNotDeleted(ConfigurationGroup.self, sorted: "createAt").first {
                group = g
            }else {
                group = ConfigurationGroup()
                group.name = "Default".localized()
                do {
                    try DBUtils.add(group)
                }catch {
                    fatalError("Fail to generate default group")
                }
            }
            let uuid = group.uuid
            let name = group.name
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { 
                self.setDefaultConfigGroup(uuid, name: name)
            })
            return group
        }
    }
    
    public func setDefaultConfigGroup(id: String, name: String) {
        do {
            try regenerateConfigFiles()
        } catch {

        }
        Potatso.sharedUserDefaults().setObject(id, forKey: kDefaultGroupIdentifier)
        Potatso.sharedUserDefaults().setObject(name, forKey: kDefaultGroupName)
        Potatso.sharedUserDefaults().synchronize()
    }
    
    public func regenerateConfigFiles() throws {
        try generateGeneralConfig()
        try generateShadowsocksConfig()
        try generateHttpProxyConfig()
    }

}

extension ConfigurationGroup {

    public var isDefault: Bool {
        let defaultUUID = Manager.sharedManager.defaultConfigGroup.uuid
        let isDefault = defaultUUID == uuid
        return isDefault
    }
    
}

extension Manager {
    
    var upstreamProxy: Proxy? {
        return defaultConfigGroup.proxies.first
    }
    
    var defaultToProxy: Bool {
        return upstreamProxy != nil && defaultConfigGroup.defaultToProxy
    }
    
    func generateGeneralConfig() throws {
        let confURL = Potatso.sharedGeneralConfUrl()
        let json: NSDictionary = ["dns": defaultConfigGroup.dns ?? ""]
        do {
            try json.jsonString()?.writeToURL(confURL, atomically: true, encoding: NSUTF8StringEncoding)
        } catch {
            print("generateGeneralConfig error")
        }
    }
    
    func generateShadowsocksConfig() throws {
        let confURL = Potatso.sharedProxyConfUrl()
        var content = ""
        if let upstreamProxy = upstreamProxy {
            if upstreamProxy.type == .Shadowsocks || upstreamProxy.type == .ShadowsocksR {
                content = ["type": upstreamProxy.type.rawValue, "host": upstreamProxy.host, "port": upstreamProxy.port, "password": upstreamProxy.password ?? "", "authscheme": upstreamProxy.authscheme ?? "", "ota": upstreamProxy.ota, "protocol": upstreamProxy.ssrProtocol ?? "", "obfs": upstreamProxy.ssrObfs ?? "", "obfs_param": upstreamProxy.ssrObfsParam ?? ""].jsonString() ?? ""
            } else if upstreamProxy.type == .Socks5 {
                content = ["type": upstreamProxy.type.rawValue, "host": upstreamProxy.host, "port": upstreamProxy.port, "password": upstreamProxy.password ?? "", "authscheme": upstreamProxy.authscheme ?? ""].jsonString() ?? ""
            }
        }
        try content.writeToURL(confURL, atomically: true, encoding: NSUTF8StringEncoding)
    }
    
    func generateHttpProxyConfig() throws {
        let rootUrl = Potatso.sharedUrl()
        let confDirUrl = rootUrl.URLByAppendingPathComponent("httpconf")
        let templateDirPath = rootUrl.URLByAppendingPathComponent("httptemplate")!.path!
        let temporaryDirPath = rootUrl.URLByAppendingPathComponent("httptemporary")!.path!
        let logDir = rootUrl.URLByAppendingPathComponent("log")!.path!
        let maxminddbPath = Potatso.sharedUrl().URLByAppendingPathComponent("GeoLite2-Country.mmdb")!.path!
        let userActionUrl = confDirUrl!.URLByAppendingPathComponent("potatso.action")
        for p in [confDirUrl!.path!, templateDirPath, temporaryDirPath, logDir] {
            if !NSFileManager.defaultManager().fileExistsAtPath(p) {
                _ = try? NSFileManager.defaultManager().createDirectoryAtPath(p, withIntermediateDirectories: true, attributes: nil)
            }
        }
        var mainConf: [String: AnyObject] = [:]
        if let path = NSBundle.mainBundle().pathForResource("proxy", ofType: "plist"), let defaultConf = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            mainConf = defaultConf
        }
        mainConf["confdir"] = confDirUrl!.path!
        mainConf["templdir"] = templateDirPath
        mainConf["logdir"] = logDir
        mainConf["mmdbpath"] = maxminddbPath
        mainConf["global-mode"] = defaultToProxy
//        mainConf["debug"] = 1024+65536+1
        mainConf["debug"] = 131071
        if LoggingLevel.currentLoggingLevel != .OFF {
            mainConf["logfile"] = privoxyLogFile
        }
        mainConf["actionsfile"] = userActionUrl!.path!
        mainConf["tolerate-pipelining"] = 1
        let mainContent = mainConf.map { "\($0) \($1)"}.joinWithSeparator("\n")
        try mainContent.writeToURL(Potatso.sharedHttpProxyConfUrl(), atomically: true, encoding: NSUTF8StringEncoding)

        var actionContent: [String] = []
        var forwardURLRules: [String] = []
        var forwardIPRules: [String] = []
        var forwardGEOIPRules: [String] = []
        let rules = defaultConfigGroup.ruleSets.flatMap({ $0.rules })
        for rule in rules {
            
            switch rule.type {
            case .GeoIP:
                forwardGEOIPRules.append(rule.description)
            case .IPCIDR:
                forwardIPRules.append(rule.description)
            default:
                forwardURLRules.append(rule.description)
            }
        }

        if forwardURLRules.count > 0 {
            actionContent.append("{+forward-rule}")
            actionContent.appendContentsOf(forwardURLRules)
        }

        if forwardIPRules.count > 0 {
            actionContent.append("{+forward-rule}")
            actionContent.appendContentsOf(forwardIPRules)
        }

        if forwardGEOIPRules.count > 0 {
            actionContent.append("{+forward-rule}")
            actionContent.appendContentsOf(forwardGEOIPRules)
        }

        // DNS pollution
        actionContent.append("{+forward-rule}")
        actionContent.appendContentsOf(Pollution.dnsList.map({ "DNS-IP-CIDR, \($0)/32, PROXY" }))

        let userActionString = actionContent.joinWithSeparator("\n")
        try userActionString.writeToFile(userActionUrl!.path!, atomically: true, encoding: NSUTF8StringEncoding)
    }

}

extension Manager {
    
    public func isVPNStarted(complete: (Bool, NETunnelProviderManager?) -> Void) {
        loadProviderManager { (manager) -> Void in
            if let manager = manager {
                complete(manager.connection.status == .Connected, manager)
            }else{
                complete(false, nil)
            }
        }
    }
    
    public func startVPN(complete: ((NETunnelProviderManager?, ErrorType?) -> Void)? = nil) {
        startVPNWithOptions(nil, complete: complete)
    }
    
    private func startVPNWithOptions(options: [String : NSObject]?, complete: ((NETunnelProviderManager?, ErrorType?) -> Void)? = nil) {
        // regenerate config files
        do {
            try Manager.sharedManager.regenerateConfigFiles()
        }catch {
            complete?(nil, error)
            return
        }
        // Load provider
        loadAndCreateProviderManager { (manager, error) -> Void in
            if let error = error {
                complete?(nil, error)
            }else{
                guard let manager = manager else {
                    complete?(nil, ManagerError.InvalidProvider)
                    return
                }
                if manager.connection.status == .Disconnected || manager.connection.status == .Invalid {
                    do {
                        try manager.connection.startVPNTunnelWithOptions(options)
                        self.addVPNStatusObserver()
                        complete?(manager, nil)
                    }catch {
                        complete?(nil, error)
                    }
                }else{
                    self.addVPNStatusObserver()
                    complete?(manager, nil)
                }
            }
        }
    }
    
    public func stopVPN() {
        // Stop provider
        loadProviderManager { (manager) -> Void in
            guard let manager = manager else {
                return
            }
            manager.connection.stopVPNTunnel()
        }
    }
    
    public func postMessage() {
        loadProviderManager { (manager) -> Void in
            if let session = manager?.connection as? NETunnelProviderSession,
                let message = "Hello".dataUsingEncoding(NSUTF8StringEncoding)
                 where manager?.connection.status != .Invalid
            {
                do {
                    try session.sendProviderMessage(message) { response in
                        
                    }
                } catch {
                    print("Failed to send a message to the provider")
                }
            }
        }
    }
    
    private func loadAndCreateProviderManager(complete: (NETunnelProviderManager?, ErrorType?) -> Void ) {
        NETunnelProviderManager.loadAllFromPreferencesWithCompletionHandler { [unowned self] (managers, error) -> Void in
            if let managers = managers {
                let manager: NETunnelProviderManager
                if managers.count > 0 {
                    manager = managers[0]
                }else{
                    manager = self.createProviderManager()
                }
                manager.enabled = true
                manager.localizedDescription = AppEnv.appName
                manager.protocolConfiguration?.serverAddress = AppEnv.appName
                manager.onDemandEnabled = true
                let quickStartRule = NEOnDemandRuleEvaluateConnection()
                quickStartRule.connectionRules = [NEEvaluateConnectionRule(matchDomains: ["connect.mume.vpn"], andAction: NEEvaluateConnectionRuleAction.ConnectIfNeeded)]
                manager.onDemandRules = [quickStartRule]
                manager.saveToPreferencesWithCompletionHandler({ (error) -> Void in
                    if let error = error {
                        print("Failed to saveToPreferencesWithCompletionHandler" + error.description)
                        complete(nil, error)
                    }else{
                        print("Did saveToPreferencesWithCompletionHandler")
                        manager.loadFromPreferencesWithCompletionHandler({ (error) -> Void in
                            if let error = error {
                                complete(nil, error)
                            }else{
                                complete(manager, nil)
                            }
                        })
                    }
                })
            }else{
                complete(nil, error)
            }
        }
    }
    
    public func loadProviderManager(complete: (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferencesWithCompletionHandler { (managers, error) -> Void in
            if let managers = managers {
                if managers.count > 0 {
                    let manager = managers[0]
                    complete(manager)
                    return
                }
            }
            complete(nil)
        }
    }
    
    private func createProviderManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let p = NETunnelProviderProtocol()
        p.providerBundleIdentifier = "info.liruqi.potatso.tunnel"
        if let upstreamProxy = upstreamProxy where upstreamProxy.type == .Shadowsocks {
            p.providerConfiguration = ["host": upstreamProxy.host, "port": upstreamProxy.port]
            p.serverAddress = upstreamProxy.host
        }
        manager.protocolConfiguration = p
        return manager
    }
}

