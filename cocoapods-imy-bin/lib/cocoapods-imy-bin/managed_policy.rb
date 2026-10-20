require 'json'
require 'net/http'
require 'pathname'
require 'tempfile'
require 'uri'
require 'cocoapods-imy-bin/pod_modes'

module CBin
  module ManagedPolicy
    FILENAME = '.imy-bin-policy.json'.freeze
    REVISION_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    def self.path(project_root)
      File.join(project_root.to_s, FILENAME)
    end

    def self.ci?
      ENV['CI'] == 'true'
    end

    def self.validate!(payload, project:, revision: nil)
      unless payload.is_a?(Hash) && payload['project'] == project &&
             REVISION_PATTERN.match?(payload['revision'].to_s) &&
             (!revision || revision == payload['revision']) &&
             payload['targets'].is_a?(Array) && payload['targets'].length.between?(1, 100)
        raise Pod::Informative, '平台策略的工程、版本或 targets 无效.'
      end

      names_by_component = {}
      target_names = []
      payload['targets'].each do |target|
        name = target['name'] if target.is_a?(Hash)
        dependencies = target['dependencies'] if target.is_a?(Hash)
        unless CBin::PodModes.valid_name?(name) && dependencies.is_a?(Array) && dependencies.size <= 500
          raise Pod::Informative, '平台策略的 target 或依赖列表无效.'
        end
        raise Pod::Informative, "重复的 target: #{name}" if target_names.include?(name)
        target_names << name
        seen = []
        dependencies.each do |dependency|
          component = dependency['name'] if dependency.is_a?(Hash)
          version = dependency['version'] if dependency.is_a?(Hash)
          mode = dependency['mode'] if dependency.is_a?(Hash)
          unless CBin::PodModes.valid_name?(component) && CBin::PodModes.valid_name?(version) &&
                 CBin::PodModes::REMOTE_MODES.include?(mode)
            raise Pod::Informative, "#{name} 的组件、版本或模式无效."
          end
          raise Pod::Informative, "#{name} 重复声明 #{component}." if seen.include?(component)
          seen << component
          previous = names_by_component[component]
          current = [version, mode]
          if previous && previous != current
            raise Pod::Informative, "#{component} 在不同 target 中存在冲突的版本或模式."
          end
          names_by_component[component] = current
        end
      end
      payload
    end

    def self.read(project_root, project:, revision: nil)
      filename = path(project_root)
      raise Pod::Informative, "未找到策略快照 #{filename}，请先运行 pod bin sync." unless File.file?(filename)
      expected = revision || (ENV['IMY_BIN_POLICY_REVISION'] if ci?)
      if ci? && !REVISION_PATTERN.match?(expected.to_s)
        raise Pod::Informative, 'CI 必须指定 IMY_BIN_POLICY_REVISION 并先同步该版本.'
      end
      validate!(JSON.parse(File.read(filename)), project: project, revision: expected)
    rescue JSON::ParserError => error
      raise Pod::Informative, "无法解析平台策略: #{error.message}"
    end

    def self.verify_lockfile!(project_root, project:, source_repo:, binary_repo:, mode_overrides: {})
      policy = read(project_root, project: project)
      filename = Pathname.new(File.join(project_root.to_s, 'Podfile.lock'))
      raise Pod::Informative, '未找到 Podfile.lock，无法验证平台策略.' unless filename.file?
      lockfile = Pod::Lockfile.from_file(filename)
      policy['targets'].flat_map { |target| target['dependencies'] }.uniq.each do |dependency|
        name = dependency['name']
        version = dependency['version']
        expected_mode = mode_overrides.fetch(name, dependency['mode'])
        expected_repo = expected_mode == 'binary' ? binary_repo : source_repo
        actual_version = lockfile.version(name)&.to_s
        actual_repo = lockfile.spec_repo(name)
        unless actual_version == version && actual_repo == expected_repo
          raise Pod::Informative, "#{name} 的锁定结果与平台策略不符: " \
            "期望 #{version} (#{expected_mode})，实际 #{actual_version || '缺失'} (#{actual_repo || '本地/未知'})."
        end
      end
      true
    end

    def self.sync(project_root, project:, revision:, server:, token:)
      raise Pod::Informative, '组件工程目录必须包含 Podfile.' unless File.file?(File.join(project_root, 'Podfile'))
      raise Pod::Informative, '无效的工程标识.' unless CBin::PodModes.valid_name?(project)
      if ci? && !REVISION_PATTERN.match?(revision.to_s)
        raise Pod::Informative, 'CI 必须指定 IMY_BIN_POLICY_REVISION.'
      end
      if token.to_s.empty? || token.to_s.match?(/[\x00-\x1f\x7f]/)
        raise Pod::Informative, '平台访问令牌为空或包含控制字符.'
      end
      uri = URI.parse(server.to_s)
      unless uri.is_a?(URI::HTTP) && uri.host && !uri.userinfo && !uri.query && !uri.fragment &&
             (uri.scheme == 'https' || %w[localhost 127.0.0.1 ::1].include?(uri.host))
        raise Pod::Informative, '平台地址必须是 HTTPS（仅本机例外）且不能包含凭据或查询参数.'
      end
      endpoint = revision || 'active'
      unless endpoint == 'active' || REVISION_PATTERN.match?(endpoint)
        raise Pod::Informative, '无效的策略版本.'
      end
      uri.path = "#{uri.path.chomp('/')}/api/v1/projects/#{project}/policies/#{endpoint}"
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{token}"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                 open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        raise Pod::Informative, "平台策略请求失败 (HTTP #{response.code})."
      end
      payload = validate!(JSON.parse(response.body), project: project, revision: revision)
      Tempfile.create(['.imy-bin-policy-', '.tmp'], project_root.to_s) do |file|
        file.write(JSON.generate(payload))
        file.flush
        File.rename(file.path, path(project_root))
      end
      payload
    rescue URI::InvalidURIError, ArgumentError => error
      raise Pod::Informative, "平台地址或配置无效: #{error.message}"
    rescue SocketError, Timeout::Error, EOFError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH => error
      raise Pod::Informative, "无法连接平台，策略快照未更新: #{error.message}" if ci? || !File.file?(path(project_root))
      Pod::UI.warn "平台不可用，继续使用上次固定策略快照: #{error.message}"
      read(project_root, project: project, revision: revision)
    rescue JSON::ParserError => error
      raise Pod::Informative, "平台返回无效 JSON: #{error.message}"
    end
  end
end
