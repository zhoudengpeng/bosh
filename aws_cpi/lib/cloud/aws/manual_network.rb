module Bosh::AwsCloud
  ##
  #
  class ManualNetwork < Network

    attr_reader :subnet

    # create manual network
    # @param [String] name Network name
    # @param [Hash] spec Raw network spec
    def initialize(name, spec)
      super
      if @cloud_properties.nil? || !@cloud_properties.has_key?("subnet")
        raise Bosh::Clouds::CloudError, "subnet required for manual network"
      end
      @subnet = @cloud_properties["subnet"]
    end

    def private_ip
      @ip
    end

    # Configure manual network
    #
    # @param [AWS:EC2] ec2 EC2 client
    # @param [AWS::EC2::Instance] instance EC2 instance to configure
    def configure(ec2, instance)
      # we're actually not configuring anything here, it is done in the
      # create instance call where we pass the IP the instance should have
    end

  end
end