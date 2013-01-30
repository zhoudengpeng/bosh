require "spec_helper"

describe Bosh::AwsCloud::InstanceManager do

  let(:registry) { double("registry", :endpoint => "http://...", :update_settings => nil) }
  let(:instance_id) { "i-xxxxxxxx" }
  let(:instance) { double("fake_instance", :id => instance_id, :elastic_ip => nil) }
  let(:region) { mock_ec2 }
  let(:im) { Bosh::AwsCloud::InstanceManager.new(region, registry) }

  describe "#create" do

    let(:agent_id) { "agent-id" }
    let(:stemcell_id) { "stemcell-id" }
    let(:resource_pool) { {"instance_type" => "m1.small"} }
    let(:network_spec) { {"default" => {"type" => "dynamic"}} }
    let(:disk_locality) { nil }
    let(:environment) { nil }
    let(:options) { {"aws" => {"region" => "us-east-1"}} }
    let(:this_zone) { "us-east-1a" }
    let(:az_selector) { double("az_selector", :common_availability_zone => this_zone) }
    let(:instances) { double("instances") }

    let(:im) {
      im = Bosh::AwsCloud::InstanceManager.new(region, registry, az_selector)
      im.stub_chain(:stemcell, :root_device_name).and_return("/dev/foo")
      im.stub(:generate_unique_name).and_return("unique-id")
      im.stub(:wait_resource)
      im.stub(:user_data).and_return("user data as json")
      im
    }

    before do
      region.stub(:instances).and_return(instances)
    end

    it "passes dns servers in ec2 user data when present" do
      im = Bosh::AwsCloud::InstanceManager.new(region, registry, az_selector)
      im.stub_chain(:stemcell, :root_device_name).and_return("/dev/foo")
      im.stub(:wait_resource)

      registry.stub(:endpoint).and_return("registry endpoint")
      fake_network_configurator = mock("network_configurator", :vpc? => false, :security_groups => [])
      fake_network_configurator.stub(:configure)

      Bosh::AwsCloud::NetworkConfigurator.stub(:new).and_return(fake_network_configurator)

      instances.should_receive(:create) do |params|
        params[:user_data].should == Yajl::Encoder.encode({
                                                              "registry" => {
                                                                  "endpoint" => "registry endpoint"
                                                              },
                                                              "dns" => {
                                                                  "nameserver" => %w[1.2.3.4 4.5.6.7]
                                                              }
                                                          })
        instance
      end

      network_spec = {"default" => {"type" => "vip"}, "foo" => {"type" => "manual", "dns" => %w[1.2.3.4 4.5.6.7]}}

      im.create(agent_id, stemcell_id, resource_pool, network_spec, disk_locality, environment, options)
    end

    it "should set the count instance parameter to 1"

    it "creates the instance with correct security group" do

      instances.should_receive(:create) do |params|
        params[:availability_zone].should == this_zone
        instance
      end
      im.create(agent_id, stemcell_id, resource_pool, network_spec, disk_locality, environment, options)
    end

    context "vpc" do
      it "should create an instance in a subnet when a manual network is used" do
        subnet_id = "subnet-xxxxxx"
        private_ip = "1.2.3.4"
        fake_aws_subnet = double("aws_subnet", :id => subnet_id, :availability_zone_name => this_zone)

        instances.should_receive(:create) do |params|
          params[:private_ip_address].should == private_ip
          params[:subnet].should == fake_aws_subnet
          instance
        end
        region.stub_chain(:subnets, :[]).and_return(fake_aws_subnet)

        network_spec = {"default" => {"type" => "manual", "ip" => private_ip, "cloud_properties" => {"subnet" => subnet_id}}}

        im.create(agent_id, stemcell_id, resource_pool, network_spec, disk_locality, environment, options)
      end
    end

    context "ec2" do
      it "should create an instance with parameters for dynamic network" do
        instances.should_receive(:create) do |params|
          params[:image_id].should == stemcell_id
          params[:instance_type].should == resource_pool["instance_type"]
          params[:availability_zone].should == this_zone
          params[:security_groups].should == []
          params.should_not have_key("subnet")
          instance
        end

        registry.stub(:update_settings)

        im.create(agent_id, stemcell_id, resource_pool, network_spec, disk_locality, environment, options)
      end

      it "should only add the az option if it is present" do

        instances.should_receive(:create) do |params|
          params.should_not have_key(:availability_zone)
          instance
        end
        az_selector.stub(:common_availability_zone).and_return(nil)

        im.create(agent_id, stemcell_id, resource_pool, network_spec, disk_locality, environment, options)
      end
    end
  end

  describe "#set_key_name_parameter" do
    it "should set the key name instance parameter to the first non-null argument" do
      instance_manager = described_class.new(region, registry)

      instance_manager.set_key_name_parameter("foo", nil)
      instance_manager.instance_params[:key_name].should == "foo"

      instance_manager.set_key_name_parameter(nil, "bar")
      instance_manager.instance_params[:key_name].should == "bar"
    end

    it "should not have a key name instance parameter if it receives only null arguments" do
      instance_manager = described_class.new(region, registry)

      instance_manager.set_key_name_parameter(nil, nil)
      instance_manager.instance_params.keys.should_not include(:key_name)
    end
  end

  describe "#terminate" do
    it "should terminate an instance given the id" do
      instance.should_receive(:terminate)
      registry.should_receive(:delete_settings).with(instance_id)

      region.stub(:instances).and_return({instance_id => instance})
      im.stub(:wait_resource)

      im.terminate(instance_id)
    end

    it "should ignore AWS::EC2::Errors::InvalidInstanceID::NotFound exception from wait_resource" do
      instance.should_receive(:terminate)
      registry.should_receive(:delete_settings).with(instance_id)

      region.stub(:instances).and_return({instance_id => instance})
      im.stub(:wait_resource).and_raise AWS::EC2::Errors::InvalidInstanceID::NotFound

      expect {
        im.terminate(instance_id)
      }.to_not raise_error
    end
  end

  describe "#reboot" do
    it "should reboot the instance" do
      instance.should_receive(:reboot)

      region.stub(:instances).and_return({instance_id => instance})

      im.reboot(instance_id)
    end
  end

end