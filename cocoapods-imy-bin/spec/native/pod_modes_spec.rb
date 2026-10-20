require File.expand_path('../../spec_helper', __FILE__)
require 'tmpdir'
require 'cocoapods-imy-bin/pod_modes'
require 'cocoapods-imy-bin/native/resolver'

module Pod
  describe 'per-component binary mode' do
    it 'overrides the global mode and source whitelist for versioned pods' do
      Dir.mktmpdir do |root|
        filename = File.join(root, 'Podfile')
        File.write(filename, "plugin 'cocoapods-imy-bin'\nuse_binaries!\nset_use_source_pods 'Foo'\n")
        podfile = Podfile.from_file(filename)
        root_spec = Struct.new(:name).new('Foo')
        resolved = Struct.new(:name, :root, :spec).new('Foo/Subspec', root_spec, root_spec)

        CBin::PodModes.write(root, 'Foo' => 'source')
        podfile.use_binary_for_spec?(resolved).should == false

        CBin::PodModes.write(root, 'Foo' => 'binary')
        podfile.use_binary_for_spec?(resolved).should == true
      end
    end

    it 'rejects malformed local mode files instead of evaluating YAML objects' do
      Dir.mktmpdir do |root|
        File.write(CBin::PodModes.path(root), "--- !ruby/object:Object {}\n")
        -> { CBin::PodModes.read(root) }.should.raise Informative
      end
    end

    it 'replaces a previously resolved spec in either explicit mode' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'Podfile'), "plugin 'cocoapods-imy-bin'\nuse_binaries!\n")
        CBin::PodModes.write(root, 'Foo' => 'source')
        podfile = Podfile.from_file(File.join(root, 'Podfile'))
        binary_spec = Specification.new do |spec|
          spec.name = 'Foo'
          spec.version = '1.0.0'
          spec.summary = 'Binary'
        end
        source_spec = Specification.new do |spec|
          spec.name = 'Foo'
          spec.version = '1.0.0'
          spec.summary = 'Source'
        end
        binary_source = mock('binary source')
        code_source = mock('code source')
        code_source.stubs(:specification).with('Foo', binary_spec.version).returns(source_spec)
        binary_source.stubs(:specification).with('Foo', source_spec.version).returns(binary_spec)
        sources_manager = mock('sources manager')
        sources_manager.stubs(:binary_source).returns(binary_source)
        sources_manager.stubs(:code_source).returns(code_source)
        Config.instance.stubs(:sources_manager).returns(sources_manager)
        resolved = Resolver::ResolverSpecification.new(binary_spec, false, binary_source)
        resolver = Resolver.allocate
        resolver.instance_variable_set(:@podfile, podfile)
        resolver.instance_variable_set(:@resolver_specs_by_target, { Object.new => [resolved] })

        replacement = resolver.resolver_specs_by_target.values.first.first
        replacement.spec.should.equal source_spec
        replacement.source.should.equal code_source

        CBin::PodModes.write(root, 'Foo' => 'binary')
        resolved = Resolver::ResolverSpecification.new(source_spec, false, code_source)
        resolver = Resolver.allocate
        resolver.instance_variable_set(:@podfile, podfile)
        resolver.instance_variable_set(:@resolver_specs_by_target, { Object.new => [resolved] })

        replacement = resolver.resolver_specs_by_target.values.first.first
        replacement.spec.should.equal binary_spec
        replacement.source.should.equal binary_source
      end
    end

    it 'fails rather than silently using a different spec for an explicit mode' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'Podfile'), "plugin 'cocoapods-imy-bin'\nuse_binaries!\n")
        CBin::PodModes.write(root, 'Foo' => 'source')
        podfile = Podfile.from_file(File.join(root, 'Podfile'))
        binary_spec = Specification.new do |spec|
          spec.name = 'Foo'
          spec.version = '1.0.0'
        end
        code_source = mock('code source')
        code_source.stubs(:specification).raises(Informative, 'version missing')
        sources_manager = mock('sources manager')
        sources_manager.stubs(:code_source).returns(code_source)
        Config.instance.stubs(:sources_manager).returns(sources_manager)
        resolved = Resolver::ResolverSpecification.new(binary_spec, false, mock('binary source'))
        resolver = Resolver.allocate
        resolver.instance_variable_set(:@podfile, podfile)
        resolver.instance_variable_set(:@resolver_specs_by_target, { Object.new => [resolved] })

        -> { resolver.resolver_specs_by_target }.should.raise Informative
      end
    end
  end
end
