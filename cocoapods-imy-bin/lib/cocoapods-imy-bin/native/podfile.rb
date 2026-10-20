

require 'cocoapods'
require 'cocoapods-imy-bin/native/podfile_env'
require 'cocoapods-imy-bin/pod_modes'
require 'cocoapods-imy-bin/component_config'
require 'cocoapods-imy-bin/managed_policy'

module Pod
  class Podfile
    # TREAT_DEVELOPMENTS_AS_NORMAL = 'treat_developments_as_normal'.freeze

    module DSL
      def allow_prerelease!
        set_internal_hash_value(ALLOW_PRERELEASE, true)
      end

      def use_binaries!(flag = true)
        set_internal_hash_value(USE_BINARIES, flag)
      end

      def use_binaries_with_spec_selector!(&block)
        raise Informative, '必须提供选择需要二进制组件的 block !' unless block_given?

        set_internal_hash_value(USE_BINARIES_SELECTOR, block)
      end

      def set_use_source_pods(pods)
        hash_pods_use_source = get_internal_hash_value(USE_SOURCE_PODS) || []
        hash_pods_use_source += Array(pods)
        set_internal_hash_value(USE_SOURCE_PODS, hash_pods_use_source)
      end

      # 0 dev
      # 1 debug_iphoneos
      # 2 release_iphoneos
      # 需要在podfile_env 先定义  CONFIGURATION_ENV
      def set_configuration_env(env = "dev")
        set_internal_hash_value(CONFIGURATION_ENV, env)
      end

      # 声明一个同时支持版本化依赖（source/binary）与本地路径开发（local）的组件。
      # 例如：imy_pod 'HDStaticPod', '0.1.11', :path => '../HDStaticPod'
      def imy_pod(name, *requirements)
        valid_bin_plugin
        raise Informative, '请指定组件名称.' if name.to_s.empty?

        options = requirements.last.is_a?(Hash) ? requirements.pop.dup : {}
        local_path = options.delete(:path) || options.delete('path')
        version = requirements.first
        root_name = Specification.root_name(name)

        if (config_entry = component_config_entry(root_name))
          return if config_entry['enabled'] == false

          version = config_entry['version'] if config_entry['version'] && !config_entry['version'].empty?
          local_path = config_entry['path'] if config_entry['path'] && !config_entry['path'].empty?
          component_config_modes[root_name] = config_entry['mode'] if config_entry['mode']
        end

        imy_pod_definitions[root_name] = {
          'name' => root_name,
          'version' => version&.to_s,
          'path' => local_path&.to_s
        }

        mode = binary_mode_overrides[root_name] || component_config_modes[root_name] || ENV['IMY_POD_MODE']
        if mode == 'local'
          raise Informative, "#{root_name} 未声明本地 :path，无法使用 local 模式." if local_path.to_s.empty?

          pod(name, options.merge(:path => local_path))
        else
          args = []
          args << version if version && !version.to_s.empty?
          args.concat(requirements.drop(1)) if requirements.size > 1
          args << options unless options.empty?
          pod(name, *args)
        end
      end

      # 从配置表（.imy-bin-config.json，若未生成则从工作区组件推导）加载全部组件依赖，保持 Podfile 零修改、无冲突。
      def imy_bin_config_dependencies
        valid_bin_plugin
        root = defined_in_file ? defined_in_file.dirname : Pod::Config.instance.installation_root
        default_mode = use_binaries? ? 'binary' : 'source'
        config = CBin::ComponentConfig.load_or_bootstrap(root, default_mode: default_mode)
        config['components'].each do |entry|
          next if entry['enabled'] == false

          name = entry['name']
          version = entry['version']
          local_path = entry['path']
          component_config_modes[name] = entry['mode'] if entry['mode']
          args = []
          args << version if version && !version.empty?
          args << { :path => local_path } if local_path && !local_path.empty?
          imy_pod(name, *args)
        end
      end

      # The platform owns version/mode decisions; only validated data is passed to CocoaPods DSL.
      def imy_bin_dependencies(target_name, project:)
        root = defined_in_file ? defined_in_file.dirname : Pod::Config.instance.installation_root
        policy = CBin::ManagedPolicy.read(root, project: project)
        if @imy_bin_managed_policy_project && @imy_bin_managed_policy_project != project
          raise Informative, '一个 Podfile 只能管理一个平台工程.'
        end
        @imy_bin_managed_policy_project = project
        target = policy['targets'].find { |entry| entry['name'] == target_name }
        raise Informative, "策略 #{policy['revision']} 中没有 target #{target_name}." unless target
        modes = managed_policy_modes
        target['dependencies'].each do |entry|
          previous = modes[entry['name']]
          if previous && previous != entry['mode']
            raise Informative, "#{entry['name']} 在不同 target 中的模式冲突."
          end
          modes[entry['name']] = entry['mode']
          pod(entry['name'], entry['version'])
        end
      end
    end

    alias old_plugins plugins
    def plugins
      if ENV[USE_PLUGINS]
        env_plugins = ENV[USE_PLUGINS].split(',').each_with_object({}) do |name, result|
          result[name] = {}
        end
        env_plugins.merge!(old_plugins)
      else
        old_plugins
      end
    end

    def use_binaries_selector
      get_internal_hash_value(USE_BINARIES_SELECTOR, nil)
    end

    def allow_prerelease?
      get_internal_hash_value(ALLOW_PRERELEASE, false) || ENV[ALLOW_PRERELEASE] == 'true'
    end

    def use_binaries?
      get_internal_hash_value(USE_BINARIES, false) || ENV[USE_BINARIES] == 'true'
    end

    def use_source_pods
      get_internal_hash_value(USE_SOURCE_PODS, []) + String(ENV[USE_SOURCE_PODS]).split('|').uniq
    end

    def binary_mode_overrides
      project_root = defined_in_file ? defined_in_file.dirname : Pod::Config.instance.installation_root
      CBin::ManagedPolicy.ci? ? {} : CBin::PodModes.read(project_root)
    end

    attr_reader :imy_bin_managed_policy_project

    def managed_policy_modes
      @imy_bin_managed_policy_modes ||= {}
    end

    def component_config_modes
      @imy_bin_component_config_modes ||= begin
        project_root = defined_in_file ? defined_in_file.dirname : Pod::Config.instance.installation_root
        CBin::ComponentConfig.modes_map(project_root)
      end
    end

    def component_config_entry(name)
      project_root = defined_in_file ? defined_in_file.dirname : Pod::Config.instance.installation_root
      config = CBin::ComponentConfig.read(project_root)
      return nil unless config

      config['components'].find { |item| item['name'] == name }
    end

    def imy_pod_definitions
      @imy_pod_definitions ||= {}
    end

    def effective_mode_for_pod(name, overrides = effective_mode_overrides)
      root_name = Specification.root_name(name)
      return 'local' if local_path_dependency?(root_name)

      mode = overrides[root_name]
      return mode if mode

      return 'source' unless ([name, root_name] & use_source_pods).empty?

      use_binaries? ? 'binary' : 'source'
    end

    def effective_mode_overrides
      managed_policy_modes.merge(component_config_modes).merge(binary_mode_overrides)
    end

    def use_binary_for_spec?(rspec, overrides = effective_mode_overrides)
      name = rspec.root.name
      return false if local_path_dependency?(name)

      mode = overrides[name]
      return mode == 'binary' if mode

      !!(([rspec.name, name] & use_source_pods).empty? &&
        (use_binaries? || use_binaries_selector) &&
        (use_binaries_selector.nil? || use_binaries_selector.call(rspec.spec)))
    end

    def local_path_dependency?(name)
      dependencies.any? { |dependency|
        dependency.root_name == name && dependency.external_source&.key?(:path)
      }
    end

    def configuration_env
      get_internal_hash_value(CONFIGURATION_ENV, "dev") ||  ENV[CONFIGURATION_ENV] == "dev"
    end

    private

    def valid_bin_plugin
      unless plugins.keys.include?('cocoapods-imy-bin')
        raise Pod::Informative, 'You should add `plugin \'cocoapods-imy-bin\'` before using its DSL'
      end
    end

    # set_hash_value 有 key 限制
    def set_internal_hash_value(key, value)
      valid_bin_plugin

      internal_hash[key] = value
    end

    def get_internal_hash_value(key, default = nil)
      internal_hash.fetch(key, default)
    end
  end
end
