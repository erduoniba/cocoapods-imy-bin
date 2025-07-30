# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cocoapods-imy-bin/gem_version.rb'

Gem::Specification.new do |spec|
  spec.name          = 'cocoapods-imy-bin'
  spec.version       = CBin::VERSION
  spec.authors       = ['苏良锦']
  spec.email         = ['suliangjin@xiaoyouzi.com']
  spec.description   = %q{cocoapods-imy-bin is a plugin which helps develpers switching pods between source code and binary.}
  spec.summary       = %q{cocoapods-imy-bin is a plugin which helps develpers switching pods between source code and binary.}
  spec.homepage      = 'https://github.com/su350380433/cocaopods-imy-bin'
  spec.license       = 'MIT'

  spec.files = Dir["lib/**/*.rb","spec/**/*.rb","lib/**/*.plist"] + %w{README.md LICENSE.txt }

  #spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  
  # ["lib"] 表示 Ruby 将在 gem 的 lib 目录中查找需要加载的文件。
  spec.require_paths = ['lib']

  spec.add_dependency 'parallel'
  spec.add_dependency 'cocoapods'
  spec.add_dependency "cocoapods-generate",'2.2.5'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
end
