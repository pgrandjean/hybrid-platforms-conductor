require 'cleanroom'
require 'git'
require 'hybrid_platforms_conductor/plugins'

module HybridPlatformsConductor

  # Object used to access the whole configuration
  class Config

    include LoggerHelpers, Cleanroom

    class << self
      # Array<Symbol>: List of mixin initializers to call
      attr_accessor :mixin_initializers
    end
    @mixin_initializers = []

    # Directory of the definition of the platforms
    #   String
    attr_reader :hybrid_platforms_dir
    expose :hybrid_platforms_dir

    # List of platforms repository directories, per platform type
    #   Hash<Symbol, Array<String> >
    attr_reader :platform_dirs

    # List of expected failures info. Each info has the following properties:
    # * *nodes_selectors_stack* (Array<Object>): Stack of nodes selectors impacted by this expected failure
    # * *tests* (Array<Symbol>): List of tests impacted by this expected failre
    # * *reason* (String): Reason for this expected failure
    # Array<Hash,Symbol,Object>
    attr_reader :expected_failures

    # Constructor
    #
    # Parameters::
    # * *logger* (Logger): Logger to be used [default = Logger.new(STDOUT)]
    # * *logger_stderr* (Logger): Logger to be used for stderr [default = Logger.new(STDERR)]
    def initialize(logger: Logger.new(STDOUT), logger_stderr: Logger.new(STDERR))
      init_loggers(logger, logger_stderr)
      # Stack of the nodes selectors scopes
      # Array< Object >
      @nodes_selectors_stack = []
      @hybrid_platforms_dir = File.expand_path(ENV['hpc_platforms'].nil? ? '.' : ENV['hpc_platforms'])
      # List of OS image directories, per image name
      # Hash<Symbol, String>
      @os_images = {}
      # Directory in which platforms are cloned
      @git_platforms_dir = "#{@hybrid_platforms_dir}/cloned_platforms"
      # List of platforms repository directories, per platform type
      # Hash<Symbol, Array<String> >
      @platform_dirs = {}
      # Plugin ID of the tests provisioner
      # Symbol
      @tests_provisioner = :docker
      # List of expected failures info. Each info has the following properties:
      # * *nodes_selectors_stack* (Array<Object>): Stack of nodes selectors impacted by this expected failure
      # * *tests* (Array<Symbol>): List of tests impacted by this expected failre
      # * *reason* (String): Reason for this expected failure
      # Array<Hash,Symbol,Object>
      @expected_failures = []
      # Make sure plugins can decorate our DSL with their owns additions as well
      # Therefore we parse all possible plugin types
      Dir.glob("#{__dir__}/hpc_plugins/*").each do |plugin_dir|
        Plugins.new(File.basename(plugin_dir).to_sym, logger: @logger, logger_stderr: @logger_stderr)
      end
      # Call initializers if needed
      Config.mixin_initializers.each do |mixin_init_method|
        self.send(mixin_init_method)
      end
      include_config_from "#{@hybrid_platforms_dir}/hpc_config.rb"
    end

    # Include configuration from a DSL config file
    #
    # Parameters::
    # * *dsl_file* (String): Path to the DSL file
    def include_config_from(dsl_file)
      log_debug "Include config from #{dsl_file}"
      self.evaluate_file(dsl_file)
    end
    expose :include_config_from

    # Register a new OS image
    #
    # Parameters::
    # * *image* (Symbol): Name of the Docker image
    # * *dir* (String): Directory containing the Dockerfile defining the image
    def os_image(image, dir)
      raise "OS image #{image} already defined to #{@os_images[image]}" if @os_images.key?(image)
      @os_images[image] = dir
    end
    expose :os_image

    # Set which provisioner should be used for tests
    #
    # Parameters::
    # * *provisioner* (Symbol): Plugin ID of the provisioner to be used for tests
    def tests_provisioner(provisioner)
      @tests_provisioner = provisioner
    end
    expose :tests_provisioner

    # Limit the scope of configuration to a given set of nodes
    #
    # Parameters::
    # * *nodes_selectors* (Object): Nodes selectors, as defined by the NodesHandler#select_nodes method (check its signature for details)
    # Proc: DSL code called in the context of those selected nodes
    def for_nodes(nodes_selectors)
      @nodes_selectors_stack << nodes_selectors
      begin
        yield
      ensure
        @nodes_selectors_stack.pop
      end
    end
    expose :for_nodes

    # Mark some tests as expected failures.
    #
    # Parameters::
    # * *tests* (Symbol or Array<Symbol>): List of tests expected to fail.
    # * *reason* (String): Descriptive reason for the failure
    def expect_tests_to_fail(tests, reason)
      @expected_failures << {
        tests: tests.is_a?(Array) ? tests : [tests],
        nodes_selectors_stack: current_nodes_selectors_stack,
        reason: reason
      }
    end
    expose :expect_tests_to_fail

    # Get the current nodes selector stack.
    #
    # Result::
    # * Array<Object>: Nodes selectors stack
    def current_nodes_selectors_stack
      @nodes_selectors_stack.clone
    end

    # Get the list of known Docker images
    #
    # Result::
    # * Array<Symbol>: List of known Docker images
    def known_os_images
      @os_images.keys
    end

    # Get the directory containing a Docker image
    #
    # Parameters::
    # * *image* (Symbol): Image name
    # Result::
    # * String: Directory containing the Dockerfile of the image
    def os_image_dir(image)
      @os_images[image]
    end

    # Name of the provisioner to be used for tests
    #
    # Result::
    # * Symbol: Provisioner to be used for tests
    def tests_provisioner_id
      @tests_provisioner
    end

  end

end