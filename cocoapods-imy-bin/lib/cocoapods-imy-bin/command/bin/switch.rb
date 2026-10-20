require 'cocoapods-imy-bin/pod_modes'
require 'cocoapods-imy-bin/component_config'
require 'cocoapods-imy-bin/command/bin/install'

module Pod
  class Command
    class Bin < Command
      class Switch < Bin
        self.summary = '切换单个或全部组件的本地/源码/二进制依赖模式并安装.'
        self.arguments = [
          CLAide::Argument.new('POD', false),
          CLAide::Argument.new('local|source|binary', false)
        ]

        def self.options
          [
            ['--all', '将工程声明的全部组件切换为指定模式'],
            ['--reset', '清除所有本地单组件模式覆盖（恢复 Podfile 默认设置）'],
            ['--no-install', '只保存选择，不执行 pod bin install']
          ].concat(super)
        end

        def initialize(argv)
          @all = argv.flag?('all', false)
          @reset = argv.flag?('reset', false)
          @install = argv.flag?('install', true)
          if @all
            @mode = argv.shift_argument
          elsif !@reset
            @name = argv.shift_argument
            @mode = argv.shift_argument
          end
          super
        end

        def validate!
          super
          root = config.installation_root
          raise Informative, '请在包含 Podfile 的工程目录运行.' unless File.file?(File.join(root, 'Podfile'))
          raise Informative, 'Podfile 必须声明 cocoapods-imy-bin 插件.' unless config.podfile.plugins.key?('cocoapods-imy-bin')
          CBin::PodModes.read(root)

          return if @reset

          unless CBin::PodModes::MODES.include?(@mode)
            raise Informative, '模式必须是 local、source 或 binary.'
          end

          if @all
            validate_all_components!
          else
            raise Informative, '请指定组件名（不含 /subspec）.' unless CBin::PodModes.valid_name?(@name)
            validate_single_component!(@name)
          end
        end

        def run
          root = config.installation_root
          if @reset
            CBin::PodModes.reset(root)
            sync_component_config(root, reset: true)
            UI.puts "已清除本地组件模式覆盖；#{@install ? '开始安装' : '运行 pod bin install 后生效'}."
          elsif @all
            names = target_component_names
            modes = names.each_with_object({}) { |pod_name, acc| acc[pod_name] = @mode }
            CBin::PodModes.write(root, modes)
            sync_component_config(root, modes: modes)
            UI.puts "已将全部组件 (#{names.join(', ')}) 设置为 #{@mode}；#{@install ? '开始安装' : '运行 pod bin install 后生效'}."
          else
            modes = CBin::PodModes.read(root)
            modes[@name] = @mode
            CBin::PodModes.write(root, modes)
            sync_component_config(root, modes: { @name => @mode })
            UI.puts "#{@name} 已设置为 #{@mode}；#{@install ? '开始安装' : '运行 pod bin install 后生效'}."
          end

          if @install
            # 清除缓存的 Podfile，使 Install 重新按更新后的配置表或 .imy-bin-modes.yml 解析。
            config.instance_variable_set(:@podfile, nil)
            command = Install.new(CLAide::ARGV.new([]))
            command.validate!
            command.run
          end
        end

        private

        def sync_component_config(root, modes: {}, reset: false)
          return unless CBin::ComponentConfig.exist?(root)

          payload = CBin::ComponentConfig.read(root)
          return unless payload

          default_mode = payload['defaultMode'] || 'binary'
          payload['components'].each do |entry|
            if reset
              entry['mode'] = default_mode
            elsif modes.key?(entry['name'])
              entry['mode'] = modes[entry['name']]
            end
          end
          CBin::ComponentConfig.write(root, payload)
        end

        def target_component_names
          podfile = config.podfile
          names = podfile.imy_pod_definitions.keys + podfile.dependencies.map(&:root_name)
          names.uniq.sort
        end

        def validate_all_components!
          names = target_component_names
          raise Informative, 'Podfile 中未找到可切换的组件依赖.' if names.empty?

          names.each { |pod_name| validate_single_component!(pod_name) }
        end

        def validate_single_component!(pod_name)
          podfile = config.podfile
          imy_def = podfile.imy_pod_definitions[pod_name]
          hardcoded_local = podfile.local_path_dependency?(pod_name) && !imy_def

          if @mode == 'binary' && hardcoded_local
            raise Informative, "#{pod_name} 使用 :path 本地依赖；请先改为版本化依赖或 imy_pod."
          end

          if @mode == 'local'
            has_local_path = !(imy_def && imy_def['path'].to_s.empty?) && (imy_def || hardcoded_local)
            unless has_local_path
              raise Informative, "#{pod_name} 未声明本地 :path，无法切换为 local 模式."
            end
          end
        end
      end
    end
  end
end
