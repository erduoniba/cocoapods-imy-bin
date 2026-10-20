require 'cocoapods-imy-bin/managed_policy'

module Pod
  class Command
    class Bin < Command
      class Sync < Bin
        self.summary = '将平台上的工程依赖策略同步为本地固定快照.'
        self.arguments = [CLAide::Argument.new('PROJECT', true)]

        def self.options
          [['--revision=REVISION', '不可变策略版本；CI 必填'],
           ['--server=URL', '平台服务地址，默认读取 IMY_BIN_PLATFORM_URL']].concat(super)
        end

        def initialize(argv)
          @project = argv.shift_argument
          @revision = argv.option('revision') || ENV['IMY_BIN_POLICY_REVISION']
          @server = argv.option('server') || ENV['IMY_BIN_PLATFORM_URL']
          super
        end

        def validate!
          super
          raise Informative, '请指定工程标识.' unless CBin::PodModes.valid_name?(@project)
          raise Informative, '请配置 --server 或 IMY_BIN_PLATFORM_URL.' if @server.to_s.empty?
          raise Informative, '请通过 IMY_BIN_PLATFORM_TOKEN 提供访问令牌.' if ENV['IMY_BIN_PLATFORM_TOKEN'].to_s.empty?
        end

        def run
          result = CBin::ManagedPolicy.sync(
            config.installation_root.to_s,
            project: @project,
            revision: @revision,
            server: @server,
            token: ENV['IMY_BIN_PLATFORM_TOKEN']
          )
          UI.puts "工程 #{@project} 已同步策略 #{result['revision']}."
        end
      end
    end
  end
end
