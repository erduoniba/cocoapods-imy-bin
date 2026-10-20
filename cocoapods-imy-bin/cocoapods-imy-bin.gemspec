# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cocoapods-imy-bin/gem_version.rb'

Gem::Specification.new do |spec|
  spec.name          = 'cocoapods-imy-bin'
  spec.version       = CBin::VERSION
  spec.authors       = ['苏良锦', 'tripleCC', 'ImyBin Team']
  spec.email         = ['suliangjin@xiaoyouzi.com', 'triplec.linux@gmail.com', 'dev@imybin.org']
  spec.summary       = 'CocoaPods plugin for seamless source and binary switching with zero-conflict configuration tables.'
  spec.description   = 'cocoapods-imy-bin provides XCFramework binary distribution, dual-track spec publishing, per-component mode switching (local, source, binary, branch), and configuration-table-driven dependency management to eliminate Podfile merge conflicts.'
  spec.homepage      = 'https://github.com/su350380433/cocaopods-imy-bin'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 2.6.0'

  spec.files = Dir['lib/**/*.rb', 'spec/**/*.rb', 'lib/**/*.plist'] + %w[README.md LICENSE.txt]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  
  # ["lib"] 表示 Ruby 将在 gem 的 lib 目录中查找需要加载的文件。
  spec.require_paths = ['lib']

  spec.add_dependency 'parallel', '>= 1.20'
  spec.add_dependency 'cocoapods', '>= 1.10.0'
  spec.add_dependency 'cocoapods-generate', '2.2.5'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
end
