describe HybridPlatformsConductor::HpcPlugins::PlatformHandler::ServerlessChef do

  context 'when checking services deployment' do

    # Simulate a packaging of a given repository
    #
    # Parameters::
    # * *repository* (String): The repository we package
    # * *env* (String): The environment for which this repository is packaged [default: 'prod']
    # * *service* (String): The service being packaged in this repository [default: 'test_policy']
    # * *gems* (Array<String, String>): The [<name>, <version>] gems info to be installed as generated by the packaging [default: []]
    def mock_package(
      repository,
      env: 'prod',
      service: 'test_policy',
      gems: []
    )
      package_dir = "#{repository}/dist/#{env}/#{service}"
      FileUtils.mkdir_p package_dir
      File.write("#{package_dir}/gems.json", gems.to_json)
    end

    # Get expected actions to deploy a service on a given node
    #
    # Parameters::
    # * *repository* (String): Platform repository
    # * *check_mode* (Boolean): Are we expected check-mode? [default: false]
    # * *sudo* (String): sudo prefix command [default: 'sudo -u root ']
    # * *env* (String): Environment expected to be packaged [default: 'prod']
    # * *policy* (String): Expected policy to be packaged [default: 'test_policy']
    # * *node* (String): Expected node to be deployed [default: 'node']
    # * *gems_install_cmds* (Array<String>): Expected gem install commands [default: []]
    # Result::
    # * Array: Expected actions
    def expected_actions_to_deploy_chef(
      repository,
      check_mode: false,
      sudo: 'sudo -u root -E ',
      env: 'prod',
      policy: 'test_policy',
      node: 'node',
      gems_install_cmds: []
    )
      [
        {
          remote_bash: [
            'set -e',
            'set -o pipefail',
            "if [ -n \"$(command -v apt)\" ]; then #{sudo}apt update && #{sudo}apt install -y curl build-essential ; else #{sudo}yum groupinstall 'Development Tools' && #{sudo}yum install -y curl ; fi",
            'mkdir -p ./hpc_deploy',
            'rm -rf ./hpc_deploy/tmp',
            'mkdir -p ./hpc_deploy/tmp',
            'curl --location https://omnitruck.chef.io/install.sh --output ./hpc_deploy/install.sh',
            'chmod a+x ./hpc_deploy/install.sh',
            "#{sudo}TMPDIR=./hpc_deploy/tmp ./hpc_deploy/install.sh -d /opt/artefacts -v 17.0 -s once"
          ]
        },
        {
          scp: { "#{repository}/dist/#{env}/#{policy}" => './hpc_deploy' },
          remote_bash: [
            'set -e',
            "cd ./hpc_deploy/#{policy}"
          ] +
            gems_install_cmds.map { |gem_install_cmd| "#{sudo}SSL_CERT_DIR=/etc/ssl/certs /opt/chef/embedded/bin/#{gem_install_cmd}" } +
            [
              "#{sudo}SSL_CERT_DIR=/etc/ssl/certs /opt/chef/bin/chef-client --local-mode --chef-license accept --json-attributes nodes/#{node}.json#{check_mode ? ' --why-run' : ''}",
              'cd ..',
              "#{sudo}rm -rf ./hpc_deploy/#{policy}"
            ]
        }
      ]
    end

    context 'with an empty platform' do

      it 'prepares for deploy' do
        with_serverless_chef_platforms('empty') do |platform|
          platform.prepare_for_deploy(
            services: {},
            secrets: {},
            local_environment: false,
            why_run: false
          )
        end
      end

      it 'prepares for deploy in why-run mode' do
        with_serverless_chef_platforms('empty') do |platform|
          platform.prepare_for_deploy(
            services: {},
            secrets: {},
            local_environment: false,
            why_run: true
          )
        end
      end

      it 'prepares for deploy in local mode' do
        with_serverless_chef_platforms('empty') do |platform|
          platform.prepare_for_deploy(
            services: {},
            secrets: {},
            local_environment: true,
            why_run: false
          )
        end
      end

    end

    context 'with a platform having 1 node' do

      it 'returns actions to deploy on this node' do
        with_serverless_chef_platforms('1_node') do |platform, repository|
          mock_package(repository)
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: false)).to eq expected_actions_to_deploy_chef(repository)
        end
      end

      it 'returns actions to deploy on this node with gems to be installed' do
        with_serverless_chef_platforms('1_node') do |platform, repository|
          mock_package(
            repository,
            gems: [
              ['my_gem_1', '0.0.1'],
              ['my_gem_2', '0.0.2'],
              ['my_gem_3', '~> 1.3']
            ]
          )
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: false)).to eq expected_actions_to_deploy_chef(
            repository,
            gems_install_cmds: [
              'gem install my_gem_1 --version "0.0.1"',
              'gem install my_gem_2 --version "0.0.2"',
              'gem install my_gem_3 --version "~> 1.3"'
            ]
          )
        end
      end

      it 'returns actions to deploy on this node with node attributes setup from metadata' do
        with_serverless_chef_platforms('1_node') do |platform, repository|
          test_nodes_handler.override_metadata_of 'node', :new_metadata, 'new_value'
          mock_package(repository)
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: false)).to eq expected_actions_to_deploy_chef(repository)
          attributes_file = "#{repository}/dist/prod/test_policy/nodes/node.json"
          expect(File.exist?(attributes_file)).to eq true
          expect(JSON.parse(File.read(attributes_file))).to eq(
            'description' => 'Single test node',
            'image' => 'debian_9',
            'new_metadata' => 'new_value',
            'private_ips' => ['172.16.0.1'],
            'property_1' => { 'property_11' => 'value11' },
            'property_2' => 'value2'
          )
        end
      end

      it 'returns actions to deploy on this node with secrets' do
        with_serverless_chef_platforms('1_node') do |platform, repository|
          mock_package(repository)
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: { 'my_secret' => 'secret_value' },
            local_environment: false,
            why_run: false
          )
          expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: false)).to eq expected_actions_to_deploy_chef(repository)
        end
      end

      it 'returns actions to deploy on this node in why-run mode' do
        with_serverless_chef_platforms('1_node') do |platform, repository|
          mock_package(repository)
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: false,
            why_run: true
          )
          expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: true)).to eq expected_actions_to_deploy_chef(repository, check_mode: true)
        end
      end

      it 'returns actions to deploy on this node using local mode' do
        with_serverless_chef_platforms('1_node') do |platform, repository|
          mock_package(repository, env: 'local')
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: true,
            why_run: false
          )
          expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: false)).to eq expected_actions_to_deploy_chef(repository, env: 'local')
        end
      end

      it 'returns actions to deploy on this node in why-run mode and local mode' do
        with_serverless_chef_platforms('1_node') do |platform, repository|
          mock_package(repository, env: 'local')
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: true,
            why_run: true
          )
          expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: true)).to eq expected_actions_to_deploy_chef(repository, env: 'local', check_mode: true)
        end
      end

      it 'returns actions to deploy on this node using root user' do
        with_serverless_chef_platforms('1_node') do |platform, repository|
          test_actions_executor.connector(:ssh).ssh_user = 'root'
          mock_package(repository)
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: false)).to eq expected_actions_to_deploy_chef(repository, sudo: '')
        end
      end

      it 'fails with a nice message when chef_versions.yml is missing' do
        with_serverless_chef_platforms('1_node') do |platform, repository|
          mock_package(repository)
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          File.unlink("#{repository}/chef_versions.yml")
          expect { platform.actions_to_deploy_on('node', 'test_policy', use_why_run: false) }.to raise_error "Missing file #{repository}/chef_versions.yml specifying the Chef Infra Client version to be deployed"
        end
      end

    end

    context 'with a platform having 1 local node' do

      it 'returns actions to deploy on this node' do
        with_serverless_chef_platforms('1_local_node') do |platform, repository|
          mock_package(repository)
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          with_cmd_runner_mocked [
            ['whoami', proc { [0, 'test_user', ''] }]
          ] do
            expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: false)).to eq expected_actions_to_deploy_chef(repository)
          end
        end
      end

      it 'returns actions to deploy on this node as root' do
        with_serverless_chef_platforms('1_local_node') do |platform, repository|
          mock_package(repository)
          platform.prepare_for_deploy(
            services: { 'node' => %w[test_policy] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          with_cmd_runner_mocked [
            ['whoami', proc { [0, 'root', ''] }]
          ] do
            expect(platform.actions_to_deploy_on('node', 'test_policy', use_why_run: false)).to eq expected_actions_to_deploy_chef(repository, sudo: '')
          end
        end
      end

    end

    context 'with a platform having several nodes' do

      it 'deploys services declared on 1 node on another node if asked' do
        with_serverless_chef_platforms('several_nodes') do |platform, repository|
          mock_package(repository, service: 'test_policy_1')
          platform.prepare_for_deploy(
            services: { 'node2' => %w[test_policy_1] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          expect(platform.actions_to_deploy_on('node2', 'test_policy_1', use_why_run: false)).to eq expected_actions_to_deploy_chef(repository, policy: 'test_policy_1', node: 'node2')
        end
      end

      it 'deploys using the local chef workstation when use_local_chef is set' do
        with_serverless_chef_platforms('several_nodes') do |platform, repository|
          mock_package(repository, service: 'test_policy_1')
          platform.prepare_for_deploy(
            services: { 'local' => %w[test_policy_1] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          expect(platform.actions_to_deploy_on('local', 'test_policy_1', use_why_run: false)).to eq [
            {
              bash: [
                'set -e',
                "cd #{repository}/dist/prod/test_policy_1",
                'sudo SSL_CERT_DIR=/etc/ssl/certs /opt/chef-workstation/bin/chef-client --local-mode --chef-license accept --json-attributes nodes/local.json'
              ]
            }
          ]
        end
      end

      it 'deploys using the local chef workstation with gems to be installed when use_local_chef is set' do
        with_serverless_chef_platforms('several_nodes') do |platform, repository|
          mock_package(
            repository,
            service: 'test_policy_1',
            gems: [
              ['my_gem_1', '0.0.1'],
              ['my_gem_2', '0.0.2'],
              ['my_gem_3', '~> 1.3']
            ]
          )
          platform.prepare_for_deploy(
            services: { 'local' => %w[test_policy_1] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          expect(platform.actions_to_deploy_on('local', 'test_policy_1', use_why_run: false)).to eq [
            {
              bash: [
                'set -e',
                "cd #{repository}/dist/prod/test_policy_1",
                'sudo SSL_CERT_DIR=/etc/ssl/certs /opt/chef-workstation/bin/chef gem install my_gem_1 --version "0.0.1"',
                'sudo SSL_CERT_DIR=/etc/ssl/certs /opt/chef-workstation/bin/chef gem install my_gem_2 --version "0.0.2"',
                'sudo SSL_CERT_DIR=/etc/ssl/certs /opt/chef-workstation/bin/chef gem install my_gem_3 --version "~> 1.3"',
                'sudo SSL_CERT_DIR=/etc/ssl/certs /opt/chef-workstation/bin/chef-client --local-mode --chef-license accept --json-attributes nodes/local.json'
              ]
            }
          ]
        end
      end

    end

    context 'with 2 platforms' do

      it 'deploys a service on a node belonging to another platform' do
        with_serverless_chef_platforms({ 'p1' => '1_node', 'p2' => 'several_nodes' }) do |repositories|
          platform_1, repository_1 = repositories.find { |platform, _repository| platform.name == 'p1' }
          mock_package(repository_1, service: 'test_policy_1')
          platform_1.prepare_for_deploy(
            services: { 'node2' => %w[test_policy_1] },
            secrets: {},
            local_environment: false,
            why_run: false
          )
          expect(platform_1.actions_to_deploy_on('node2', 'test_policy_1', use_why_run: false)).to eq expected_actions_to_deploy_chef(repository_1, policy: 'test_policy_1', node: 'node2')
        end
      end

    end

  end

end
