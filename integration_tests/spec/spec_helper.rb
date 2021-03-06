require "fileutils"
require "digest/sha1"
require "tmpdir"
require "tempfile"
require "set"
require "yaml"
require "nats/client"
require "sandbox"
require "deployments"
require "redis"
require "restclient"
require "director"

ASSETS_DIR = File.expand_path("../assets", __FILE__)

TEST_RELEASE_TEMPLATE = File.join(ASSETS_DIR, "test_release_template")
TEST_RELEASE_DIR = File.join(ASSETS_DIR, "test_release")

CLOUD_DIR      = "/tmp/bosh_test_cloud"
CLI_DIR        = File.expand_path("../../../cli", __FILE__)
BOSH_CACHE_DIR = Dir.mktmpdir
BOSH_WORK_DIR  = File.join(ASSETS_DIR, "bosh_work_dir")
BOSH_CONFIG    = File.join(ASSETS_DIR, "bosh_config.yml")

module Bosh
  module Spec
    module IntegrationTest
      class CliUsage; end
      class HealthMonitor; end
    end
  end
end

RSpec.configure do |c|
  c.before(:each) do |example|
    reset_sandbox(example)
    cleanup_bosh
    FileUtils.rm_rf(TEST_RELEASE_DIR)
    FileUtils.cp_r(TEST_RELEASE_TEMPLATE, TEST_RELEASE_DIR, :preserve => true)
  end

  c.after(:each) do |example|
    save_task_logs(example)
  end

  c.filter_run :focus => true if ENV["FOCUS"]
end

def spec_asset(name)
  File.expand_path("../assets/#{name}", __FILE__)
end

def start_sandbox
  puts "Starting sandboxed environment for BOSH tests..."
  Bosh::Spec::Sandbox.start
end

def stop_sandbox
  puts "\nStopping sandboxed environment for BOSH tests..."
  Bosh::Spec::Sandbox.stop
  cleanup_bosh
end

def reset_sandbox(example)
  desc = example ? example.example.metadata[:description] : ""
  Bosh::Spec::Sandbox.reset(desc)
end

def save_task_logs(example)
  desc = example ? example.example.metadata[:description] : ""
  Bosh::Spec::Sandbox.save_task_logs(desc)
end

def yaml_file(name, object)
  f = Tempfile.new(name)
  f.write(YAML.dump(object))
  f.close
  f
end

def director_version
  version = `(git show-ref --head --hash=8 2> /dev/null || echo 00000000)`
  "Ver: #{Bosh::Director::VERSION} (#{version.lines.first.strip})"
end

def run_bosh(cmd, work_dir = nil)
  Dir.chdir(work_dir || BOSH_WORK_DIR) do
    `bundle exec bosh -n -c #{BOSH_CONFIG} -C #{BOSH_CACHE_DIR} #{cmd}`
  end
end

def cleanup_bosh
  [
   BOSH_CONFIG,
   CLOUD_DIR,
   BOSH_CACHE_DIR,
   TEST_RELEASE_DIR,
  ].each do |item|
    FileUtils.rm_rf(item)
  end
end

start_sandbox
at_exit do
  begin
    if $!
      status = $!.is_a?(::SystemExit) ? $!.status : 1
    else
      status = 0
    end
    stop_sandbox
  ensure
    exit status
  end
end
