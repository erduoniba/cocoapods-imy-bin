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

    def self.normalize_entry(entry, default_mode: 'binary', filename: FILENAME)
      unless entry.is_a?(Hash)
        raise Pod::Informative, "配置表 #{filename} 中的组件项必须是对象."
      end
      name = entry['name'].to_s.strip
      mode = (entry['mode'] || default_mode || 'binary').to_s.strip
      version = entry['version']&.to_s&.strip
      local_path = entry['path']&.to_s&.strip
      git_url = entry['git']&.to_s&.strip
      branch = entry['branch']&.to_s&.strip
      tag = entry['tag']&.to_s&.strip
      commit = entry['commit']&.to_s&.strip
      targets = entry['targets']
      targets = targets.map { |t| t.to_s.strip }.reject(&:empty?) if targets.is_a?(Array)
      enabled = entry.key?('enabled') ? !!entry['enabled'] : true

      unless CBin::PodModes.valid_name?(name) && CBin::PodModes::MODES.include?(mode)
        raise Pod::Informative, "配置表 #{filename} 中组件 #{name.inspect} 的名称或模式 #{mode.inspect} 无效."
      end
      if enabled && mode == 'local' && local_path.to_s.empty?
        raise Pod::Informative, "配置表 #{filename} 中组件 #{name} 为 local 模式，但未配置本地 path."
      end
      if enabled && mode == 'branch' && git_url.to_s.empty? && branch.to_s.empty? && tag.to_s.empty? && commit.to_s.empty?
        raise Pod::Informative, "配置表 #{filename} 中组件 #{name} 为 branch 模式，但未配置 git 或 branch/tag."
      end

      {
        'name' => name,
        'version' => (version && !version.empty?) ? version : nil,
        'mode' => mode,
        'path' => (local_path && !local_path.empty?) ? local_path : nil,
        'git' => (git_url && !git_url.empty?) ? git_url : nil,
        'branch' => (branch && !branch.empty?) ? branch : nil,
        'tag' => (tag && !tag.empty?) ? tag : nil,
        'commit' => (commit && !commit.empty?) ? commit : nil,
        'targets' => (targets && !targets.empty?) ? targets : nil,
        'enabled' => enabled
      }.compact
    end

    def self.validate!(payload, filename: FILENAME)
      unless payload.is_a?(Hash) && (payload['components'].is_a?(Array) || payload['columns'].is_a?(Array))
        raise Pod::Informative, "配置表 #{filename} 格式无效，缺少 components 或 columns 数组."
      end

      default_mode = (payload['defaultMode'] || 'binary').to_s
      default_mode = 'binary' unless CBin::PodModes::MODES.include?(default_mode)

      # 支持版本列（columns）概念与 activeColumn 解析
      columns = payload['columns']
      active_column = (ENV['IMY_BIN_CONFIG_COLUMN'] || payload['activeColumn']).to_s.strip
      normalized_columns = nil

      if columns.is_a?(Array) && !columns.empty?
        seen_cols = []
        normalized_columns = columns.map do |col|
          unless col.is_a?(Hash) && col['name']
            raise Pod::Informative, "配置表 #{filename} 中的版本列必须是包含 name 的对象."
          end
          col_name = col['name'].to_s.strip
          raise Pod::Informative, "配置表 #{filename} 重复声明版本列 #{col_name}." if seen_cols.include?(col_name)
          seen_cols << col_name

          col_desc = col['description']&.to_s&.strip
          col_components = (col['components'].is_a?(Array) ? col['components'] : []).map do |entry|
            normalize_entry(entry, default_mode: default_mode, filename: filename)
          end
          {
            'name' => col_name,
            'description' => (col_desc && !col_desc.empty?) ? col_desc : nil,
            'createdAt' => col['createdAt'],
            'updatedAt' => col['updatedAt'],
            'components' => col_components
          }.compact
        end

        active_column = normalized_columns.first['name'] if active_column.empty?
        active_col = normalized_columns.find { |c| c['name'] == active_column }
        if active_col && (payload['components'].nil? || payload['components'].empty?)
          raw_components = active_col['components']
        else
          raw_components = payload['components'] || (active_col ? active_col['components'] : [])
        end
      else
        raw_components = payload['components'] || []
      end

      seen = []
      normalized_components = raw_components.map do |entry|
        normalized = normalize_entry(entry, default_mode: default_mode, filename: filename)
        name = normalized['name']
        raise Pod::Informative, "配置表 #{filename} 重复声明组件 #{name}." if seen.include?(name)
        seen << name
        normalized
      end

      result = {
        'version' => payload['version'] || 1,
        'project' => (payload['project'] || File.basename(File.expand_path(filename).sub(/\/#{Regexp.escape(FILENAME)}\z/, ''))).to_s,
        'environment' => (payload['environment'] || 'dev').to_s,
        'defaultMode' => default_mode,
        'updatedAt' => (payload['updatedAt'] || Time.now.utc.iso8601).to_s,
        'components' => normalized_components
      }
      result['activeColumn'] = active_column unless active_column.empty?
      result['columns'] = normalized_columns if normalized_columns
      result
    end

    def self.bootstrap_from_workspace(project_root, default_mode: 'binary')
      root_path = Pathname.new(File.expand_path(project_root.to_s))
      is_example = root_path.basename.to_s.casecmp('example').zero?
      self_spec_file = is_example ? Dir.glob(File.join(root_path.dirname.to_s, '*.podspec')).sort.first : nil
      self_spec = self_spec_file ? Pod::Specification.from_file(self_spec_file) : nil
      self_pod_name = self_spec&.root&.name
      declared_dep_names = self_spec ? self_spec.dependencies.map(&:root_name) : nil

      workspace_dir = is_example ? root_path.dirname.dirname : root_path.dirname
      components = []

      if workspace_dir.directory?
        workspace_dir.children.sort.each do |child|
          next unless child.directory?
          next if child == root_path || (is_example && child == root_path.dirname)
          next if EXCLUDED_DIRS.include?(child.basename.to_s) || child.basename.to_s.start_with?('.')

          podspec_file = Dir.glob(File.join(child.to_s, '*.podspec')).sort.first
          next unless podspec_file

          spec = Pod::Specification.from_file(podspec_file)
          next if self_pod_name && spec.root.name == self_pod_name

          rel_path = child.relative_path_from(root_path).to_s
          enabled = declared_dep_names ? declared_dep_names.include?(spec.root.name) : true
          components << {
            'name' => spec.root.name,
            'version' => spec.version.to_s,
            'mode' => default_mode,
            'path' => rel_path,
            'enabled' => enabled
          }
        rescue StandardError
          next
        end
      end

      sorted_components = components.sort_by { |item| item['name'] }
      default_col_name = '1.0.0'
      now = Time.now.utc.iso8601

      {
        'version' => 1,
        'project' => is_example && self_pod_name ? "#{self_pod_name}_Example" : root_path.basename.to_s,
        'environment' => 'dev',
        'defaultMode' => default_mode,
        'updatedAt' => now,
        'activeColumn' => default_col_name,
        'columns' => [
          {
            'name' => default_col_name,
            'description' => '默认 App 版本列',
            'createdAt' => now,
            'updatedAt' => now,
            'components' => sorted_components
          }
        ],
        'components' => sorted_components
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
