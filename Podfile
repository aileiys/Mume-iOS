source 'https://github.com/CocoaPods/Specs.git'

platform :ios, '9.0'
use_frameworks!

def library
    pod 'KissXML'
    pod 'KissXML/libxml_module'
    pod 'ICSMainFramework', :path => "./Library/ICSMainFramework/"
    pod 'MMWormhole', '~> 2.0.0'
end

def tunnel
    pod 'MMWormhole', '~> 2.0.0'
end

def socket
    pod 'CocoaAsyncSocket', '~> 7.4.3'
end

def model
    pod 'RealmSwift', '~> 1.1.0'
end

target "Potatso" do
    pod 'Aspects', :path => "./Library/Aspects/"
    pod 'Cartography', '~> 0.7'
    pod 'AsyncSwift', '~> 1.7'
    pod 'SwiftColor', :git => 'https://github.com/liruqi/SwiftColor.git'
    pod 'Appirater'
    pod 'Eureka', :git => 'https://github.com/xmartlabs/Eureka.git', :branch => 'swift2.3'
    pod 'MBProgressHUD'
    pod 'CallbackURLKit', '~> 0.2'
    pod 'SVPullToRefresh', :git => 'https://github.com/samvermette/SVPullToRefresh'
    pod 'ISO8601DateFormatter', '~> 0.8'
    pod 'Alamofire', '~> 3.5'
    pod 'ObjectMapper', '~> 1.5.0'
    pod 'PSOperations', '~> 2.3'
    pod 'Fabric'
    pod 'Crashlytics'
    tunnel
    library
    socket
    model
end

target "PacketTunnel" do
    tunnel
    socket
end

target "PacketProcessor" do
    socket
end

target "TodayWidget" do
    pod 'Cartography', '~> 0.7'
    pod 'SwiftColor', :git => 'https://github.com/liruqi/SwiftColor.git'
    library
    socket
    model
end

target "PotatsoLibrary" do
    library
    model
end

target "PotatsoModel" do
    model
end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['ENABLE_BITCODE'] = 'NO'
            config.build_settings['SWIFT_VERSION'] = '2.3'
        end
    end
end

