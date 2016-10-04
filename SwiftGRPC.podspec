Pod::Spec.new do |s|
  s.name = 'SwiftGRPC'
  s.version = '0.1.5'
  s.license = { :type => 'Apache 2.0', :file => 'LICENSE.txt' }
  s.summary = 'Swift GRPC library adaptor'
  s.homepage = 'https://github.com/nathanborror/swift-grpc'
  s.author = 'Nathan Borror'
  s.source = { :git => 'https://github.com/nathanborror/swift-grpc.git', :tag => s.version }

  s.requires_arc = true
  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.9'
  s.tvos.deployment_target = '9.0'
  s.watchos.deployment_target = '2.0'

  s.source_files = 'Sources/*.swift'

  s.dependency 'SwiftProtobuf'
  s.dependency 'hpack'
end

