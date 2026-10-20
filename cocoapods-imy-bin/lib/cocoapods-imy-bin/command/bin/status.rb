require 'json'
require 'cocoapods-imy-bin/pod_modes'
require 'cocoapods-imy-bin/managed_policy'

module Pod
  class Command
    class Bin < Command
      class Status < Bin
        self.summary = '查看当前工程各组件的依赖模式与锁定状态.'

        def self.options
          [
            ['--json', '以 JSON 格式输出状态，供工具或客户端解析']
          ].concat(super)
        end

        def initialize(argv)
          @json = argv.flag?('json', false)
          super
        end

        def validate!
          super
          root = config.installation_root
          raise Informative, '请在包含 Podfile 的工程目录运行.' unless File.file?(File.join(root, 'Podfile'))
        end

        def run
          payload = status_payload
          if @json
            UI.puts JSON.pretty_generate(payload)
          else
            print_table(payload)
          end
          payload
        end

        def status_payload
          root = config.installation_root
          podfile = config.podfile
          overrides = CBin::PodModes.read(root)
          effective_overrides = podfile.effective_mode_overrides
          lockfile_path = Pathname.new(File.join(root.to_s, 'Podfile.lock'))
          lockfile = lockfile_path.file? ? Lockfile.from_file(lockfile_path) : nil

          names = (podfile.imy_pod_definitions.keys + podfile.dependencies.map(&:root_name)).uniq.sort
          components = names.map do |name|
            imy_def = podfile.imy_pod_definitions[name] || {}
            dep = podfile.dependencies.find { |d| d.root_name == name }
            declared_version = imy_def['version']
            if declared_version.to_s.empty? && dep && !dep.external_source
              declared_version = dep.requirement.to_s
            end
            local_path = imy_def['path'] || dep&.external_source&.dig(:path)&.to_s
            effective_mode = podfile.effective_mode_for_pod(name, effective_overrides)

            {
              'name' => name,
              'declared_version' => declared_version,
              'locked_version' => lockfile&.version(name)&.to_s,
              'mode' => effective_mode,
              'override_mode' => overrides[name],
              'local_path' => local_path,
              'supports_local' => !local_path.to_s.empty?,
              'locked_source' => locked_source_kind(lockfile, name)
            }
          end

          {
            'project_root' => root.to_s,
            'default_mode' => podfile.use_binaries? ? 'binary' : 'source',
            'managed_policy_project' => podfile.imy_bin_managed_policy_project,
            'components' => components
          }
        end

        private

        def locked_source_kind(lockfile, name)
          return nil unless lockfile

          ext = lockfile.internal_data['EXTERNAL SOURCES'] || {}
          return 'local' if ext[name].is_a?(Hash) && (ext[name][:path] || ext[name]['path'])

          repo = lockfile.spec_repo(name)
          return nil unless repo

          binary_url = CBin.config.binary_repo_url.to_s
          code_url = CBin.config.code_repo_url.to_s
          if !binary_url.empty? && (repo == binary_url || repo.include?('binary'))
            'binary'
          elsif !code_url.empty? && (repo == code_url || repo.include?('source'))
            'source'
          else
            repo
          end
        end

        def print_table(payload)
          UI.puts "默认模式: #{payload['default_mode']}"
          headers = %w[组件 声明版本 锁定版本 当前模式 本地路径]
          rows = payload['components'].map do |item|
            [
              item['name'],
              item['declared_version'] || '-',
              item['locked_version'] || '-',
              item['override_mode'] ? "#{item['mode']} (override)" : item['mode'],
              item['local_path'] || '-'
            ]
          end
          widths = headers.each_index.map do |idx|
            ([headers[idx]] + rows.map { |r| r[idx].to_s }).map(&:length).max
          end
          fmt = widths.map { |w| "%-#{w}s" }.join('  ')
          UI.puts format(fmt, *headers)
          UI.puts widths.map { |w| '-' * w }.join('  ')
          rows.each { |row| UI.puts format(fmt, *row) }
        end
      end
    end
  end
end
