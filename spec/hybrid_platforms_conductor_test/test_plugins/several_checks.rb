module HybridPlatformsConductorTest

  module TestPlugins

    # Test plugin at several levels
    class SeveralChecks < HybridPlatformsConductor::Tests::Test

      class << self

        # Sequences of tests
        # Array< [ Symbol,    String,   String, String  ] >
        # Array< [ test_name, platform, node,   comment ] >
        attr_accessor :runs

      end

      # Check my_test_plugin.rb.sample documentation for signature details.
      def test
        SeveralChecks.runs << [@name, '', '', 'Global test']
      end

      # Check my_test_plugin.rb.sample documentation for signature details.
      def test_on_platform
        SeveralChecks.runs << [@name, @platform.info[:repo_name], '', 'Platform test']
      end

      # Check my_test_plugin.rb.sample documentation for signature details.
      def test_for_node
        SeveralChecks.runs << [@name, @platform.info[:repo_name], @node, 'Node test']
      end

      # Check my_test_plugin.rb.sample documentation for signature details.
      def test_on_node
        { "test_#{@node}.sh" => proc { |stdout, exit_code| SeveralChecks.runs << [@name, @platform.info[:repo_name], @node, "Node SSH test: #{stdout.join("\n")}"] } }
      end

      # Check my_test_plugin.rb.sample documentation for signature details.
      def test_on_check_node(stdout, stderr, exit_status)
        SeveralChecks.runs << [@name, @platform.info[:repo_name], @node, "Node check-node test: #{stdout}"]
      end

    end

  end

end