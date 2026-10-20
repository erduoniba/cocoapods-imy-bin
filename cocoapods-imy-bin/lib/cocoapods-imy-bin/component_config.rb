require 'fileutils'
require 'json'
require 'pathname'
require 'tempfile'
require 'time'
require 'cocoapods-imy-bin/pod_modes'

module CBin
  module ComponentConfig
    FILENAME = '.imy-bin-config.json'.freeze
    EXCLUDED_DIRS = %w[.git .build Pods DerivedData cocoapods-imy-bin-fork binary-server .imy-infra .imy-pods node_modules Example].freeze

    def self.path(project_root)
      File.join(project_root.to_s, FILENAME)
    end

    def self.exist?(project_root)
      File.file?(path(project_root))
    end

    def self.read(project_root)
      filename = path(project_root)
      return nil unless File.file?(filename)

      payload = JSON.parse(File.read(filename))
      validate!(payload, filename: filename)
    rescue JSON::ParserError => error
      raise Pod::Informative, "无法解析配置表 #{filename}: #{error.message}"
    end

    def self.validate!(payload, filename: FILENAME)
      unless payload.is_a?(Hash) && payload['components'].is_a?(Array)
        raise Pod::Informative, "配置表 #{filename} 格式无效，缺少 components 数组."
      end

      seen = []
      normalized_components = payload['components'].map do |entry|
        unless entry.is_a?(Hash)
          raise Pod::Informative, "配置表 #{filename} 中的组件项必须是对象."
        end
        name = entry['name'].to_s.strip
        mode = (entry['mode'] || payload['defaultMode'] || 'binary').to_s.strip
        version = entry['version']&.to_s&.strip
        local_path = entry['path']&.to_s&.strip
        enabled = entry.key?('enabled') ? !!entry['enabled'] : true

        unless CBin::PodModes.valid_name?(name) && CBin::PodModes::MODES.include?(mode)
          raise Pod::Informative, "配置表 #{filename} 中组件 #{name.inspect} 的名称或模式 #{mode.inspect} 无效."
        end
        raise Pod::Informative, "配置表 #{filename} 重复声明组件 #{name}." if seen.include?(name)
        if enabled && mode == 'local' && local_path.to_s.empty?
          raise Pod::Informative, "配置表 #{filename} 中组件 #{name} 为 local 模式，但未配置本地 path."
        end

        seen << name
        {
          'name' => name,
          'version' => (version && !version.empty?) ? version : nil,
          'mode' => mode,
          'path' => (local_path && !local_path.empty?) ? local_path : nil,
          'enabled' => enabled
        }.compact
      end

      default_mode = (payload['defaultMode'] || 'binary').to_s
      default_mode = 'binary' unless CBin::PodModes::MODES.include?(default_mode)

      {
        'version' => payload['version'] || 1,
        'project' => (payload['project'] || File.basename(File.expand_path(filename).sub(/\/#{Regexp.escape(FILENAME)}\z/, ''))).to_s,
        'environment' => (payload['environment'] || 'dev').to_s,
        'defaultMode' => default_mode,
        'updatedAt' => (payload['updatedAt'] || Time.now.utc.iso8601).to_s,
        'components' => normalized_components
      }
    end

    def self.bootstrap_from_workspace(project_root, default_mode: 'binary')
      root_path = Pathname.new(File.expand_path(project_root.to_s))
      parent_path = root_path.dirname
      components = []

      if parent_path.directory?
        parent_path.children.sort.each do |child|
          next unless child.directory?
          next if child == root_path
          next if EXCLUDED_DIRS.include?(child.basename.to_s) || child.basename.to_s.start_with?('.')

          podspec_file = Dir.glob(File.join(child.to_s, '*.podspec')).sort.first
          next unless podspec_file

          spec = Pod::Specification.from_file(podspec_file)
          rel_path = child.relative_path_from(root_path).to_s
          components << {
            'name' => spec.root.name,
            'version' => spec.version.to_s,
            'mode' => default_mode,
            'path' => rel_path,
            'enabled' => true
          }
        rescue StandardError
          next
        end
      end

      {
        'version' => 1,
        'project' => root_path.basename.to_s,
        'environment' => 'dev',
        'defaultMode' => default_mode,
        'updatedAt' => Time.now.utc.iso8601,
        'components' => components.sort_by { |item| item['name'] }
      }
    end

    def self.load_or_bootstrap(project_root, default_mode: 'binary')
      read(project_root) || bootstrap_from_workspace(project_root, default_mode: default_mode)
    end

    def self.write(project_root, payload)
      validated = validate!(payload)
      validated['updatedAt'] = Time.now.utc.iso8601
      filename = path(project_root)
      Tempfile.create(['.imy-bin-config-', '.tmp'], project_root.to_s) do |file|
        file.write(JSON.pretty_generate(validated) + "\n")
        file.flush
        File.rename(file.path, filename)
      end
      validated
    end

    def self.modes_map(project_root)
      config = read(project_root)
      return {} unless config

      config['components'].each_with_object({}) do |entry, result|
        next if entry['enabled'] == false
        result[entry['name']] = entry['mode'] if entry['mode']
      end
    end
  end
end
