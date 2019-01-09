require 'hybrid_platforms_conductor/cmd_runner'

module HybridPlatformsConductor

  module Tests

    module Plugins

      # Check that all executables run correctly, from an environment/installation point of view.
      class Executables < Tests::Test

        # Check my_test_plugin.rb.sample documentation for signature details.
        def test
          example_host = NodesHandler.new.platforms.first.known_hostnames.first
        	[
            "#{CmdRunner.executables_prefix}check-node --host-name #{example_host} --show-commands",
            "#{CmdRunner.executables_prefix}deploy --host-name #{example_host} --show-commands --why-run",
            "#{CmdRunner.executables_prefix}dump_nodes_json --help",
            "#{CmdRunner.executables_prefix}free_ips",
            "#{CmdRunner.executables_prefix}free_veids",
            "#{CmdRunner.executables_prefix}last_deploys --host-name #{example_host} --show-commands",
            "#{CmdRunner.executables_prefix}report --host-name #{example_host} --format mediawiki",
            "#{CmdRunner.executables_prefix}ssh_config",
            "#{CmdRunner.executables_prefix}ssh_run --host-name #{example_host} --show-commands --interactive",
            "#{CmdRunner.executables_prefix}setup --help",
            "#{CmdRunner.executables_prefix}test --help",
            "#{CmdRunner.executables_prefix}topograph --from \"--host-name #{example_host}\" --to \"--host-name #{example_host}\" --skip-run --output graphviz:graph.gv && rm graph.gv"
          ].each do |cmd|
            stdout = `#{cmd} 2>&1`
            exit_status = $?.exitstatus
            assert_equal(exit_status, 0, "Command #{cmd} returned code #{exit_status}:\n#{stdout}")
          end
        end

      end

    end

  end

end
