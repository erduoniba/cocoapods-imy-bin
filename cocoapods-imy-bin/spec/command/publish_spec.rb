require File.expand_path('../../spec_helper', __FILE__)
require 'tmpdir'

module Pod
  describe Command::Bin::Publish do
    it 'archives one pod before uploading its artifact and spec' do
      Dir.mktmpdir do |root|
        Dir.chdir(root) do
          File.write('Foo.podspec', '')
          spec = Struct.new(:name, :version) do
            def subspec?
              false
            end
          end.new('Foo', '1.0.0')
          Specification.stubs(:from_file).returns(spec)

          helper = mock('uploader')
          helper.expects(:preflight!)
          helper.expects(:upload)
          CBin::Upload::Helper.stubs(:new).returns(helper)

          archive = mock('archive')
          archive.expects(:validate!)
          archive.expects(:run).returns([spec])
          Command::Bin::Archive.stubs(:new).returns(archive)

          command = Command::Bin::Publish.new(CLAide::ARGV.new(%w[Foo.podspec --env=dev]))
          command.stubs(:binary_source)
          command.stubs(:code_source)
          command.validate!
          command.run
        end
      end
    end

    it 'does not upload when archive returns no matching artifact' do
      Dir.mktmpdir do |root|
        Dir.chdir(root) do
          File.write('Foo.podspec', '')
          spec = Struct.new(:name, :version) do
            def subspec?
              false
            end
          end.new('Foo', '1.0.0')
          Specification.stubs(:from_file).returns(spec)
          helper = mock('uploader')
          helper.stubs(:preflight!)
          helper.expects(:upload).never
          CBin::Upload::Helper.stubs(:new).returns(helper)
          archive = mock('archive')
          archive.stubs(:validate!)
          archive.stubs(:run).returns([])
          Command::Bin::Archive.stubs(:new).returns(archive)

          command = Command::Bin::Publish.new(CLAide::ARGV.new(%w[Foo.podspec]))
          command.stubs(:binary_source)
          command.stubs(:code_source)
          command.validate!
          -> { command.run }.should.raise Informative
        end
      end
    end

    it 'stops after archiving when --dry-run is enabled' do
      Dir.mktmpdir do |root|
        Dir.chdir(root) do
          File.write('Foo.podspec', '')
          spec = Struct.new(:name, :version) do
            def subspec?
              false
            end
          end.new('Foo', '1.0.0')
          Specification.stubs(:from_file).returns(spec)
          helper = mock('uploader')
          helper.expects(:preflight!)
          helper.expects(:upload).never
          CBin::Upload::Helper.stubs(:new).returns(helper)
          archive = mock('archive')
          archive.expects(:validate!)
          archive.expects(:run).returns([spec])
          Command::Bin::Archive.stubs(:new).returns(archive)

          command = Command::Bin::Publish.new(CLAide::ARGV.new(%w[Foo.podspec --dry-run]))
          command.stubs(:binary_source)
          command.stubs(:code_source)
          command.validate!
          command.run.should == [spec]
        end
      end
    end

    it 'rolls back a newly created git tag when uploading fails' do
      Dir.mktmpdir do |root|
        Dir.chdir(root) do
          Dir.mkdir('.git')
          File.write('Foo.podspec', '')
          spec = Struct.new(:name, :version) do
            def subspec?
              false
            end
          end.new('Foo', '1.2.0')
          Specification.stubs(:from_file).returns(spec)
          helper = mock('uploader')
          helper.stubs(:preflight!)
          helper.expects(:upload).raises(Informative, 'upload failed')
          CBin::Upload::Helper.stubs(:new).returns(helper)
          archive = mock('archive')
          archive.stubs(:validate!)
          archive.stubs(:run).returns([spec])
          Command::Bin::Archive.stubs(:new).returns(archive)

          missing_status = stub('status', :success? => false)
          ok_status = stub('status', :success? => true)
          Open3.expects(:capture2e).with('git', 'rev-parse', '-q', '--verify', 'refs/tags/1.2.0').returns(['', missing_status])
          Open3.expects(:capture2e).with('git', 'tag', '1.2.0').returns(['', ok_status])
          Open3.expects(:capture2e).with('git', 'tag', '-d', '1.2.0').returns(['', ok_status])

          command = Command::Bin::Publish.new(CLAide::ARGV.new(%w[Foo.podspec]))
          command.stubs(:binary_source)
          command.stubs(:code_source)
          command.validate!
          -> { command.run }.should.raise Informative
        end
      end
    end

    it 'auto-commits dirty changes and pushes branch and tag when --auto-commit and --push are enabled' do
      Dir.mktmpdir do |root|
        Dir.chdir(root) do
          Dir.mkdir('.git')
          File.write('Foo.podspec', '')
          spec = Struct.new(:name, :version) do
            def subspec?
              false
            end
          end.new('Foo', '1.3.0')
          Specification.stubs(:from_file).returns(spec)
          helper = mock('uploader')
          helper.stubs(:preflight!)
          helper.expects(:upload)
          CBin::Upload::Helper.stubs(:new).returns(helper)
          archive = mock('archive')
          archive.stubs(:validate!)
          archive.stubs(:run).returns([spec])
          Command::Bin::Archive.stubs(:new).returns(archive)

          ok_status = stub('status', :success? => true)
          missing_status = stub('status', :success? => false)

          # auto_commit expectations
          Open3.expects(:capture2e).with('git', 'status', '--porcelain').returns([" M Classes/Foo.swift\n", ok_status])
          Open3.expects(:capture2e).with('git', 'add', '-A').returns(['', ok_status])
          Open3.expects(:capture2e).with('git', 'commit', '-m', 'chore: release Foo 1.3.0').returns(['[main 1234] commit', ok_status])

          # tag expectations
          Open3.expects(:capture2e).with('git', 'rev-parse', '-q', '--verify', 'refs/tags/1.3.0').returns(['', missing_status])
          Open3.expects(:capture2e).with('git', 'tag', '1.3.0').returns(['', ok_status])

          # push expectations
          Open3.expects(:capture2e).with('git', 'remote').returns(["origin\n", ok_status])
          Open3.expects(:capture2e).with('git', 'push', 'origin', 'HEAD').returns(['', ok_status])
          Open3.expects(:capture2e).with('git', 'push', 'origin', '1.3.0', '--force').returns(['', ok_status])

          command = Command::Bin::Publish.new(CLAide::ARGV.new(%w[Foo.podspec --auto-commit --push]))
          command.stubs(:binary_source)
          command.stubs(:code_source)
          command.validate!
          command.run
        end
      end
    end
  end
end
