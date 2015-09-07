shared_examples "a version 4.x virtualbox driver" do |options|
  before do
    raise ArgumentError, "Need virtualbox context to use these shared examples." if !(defined? vbox_context)
  end

  describe "attach_virtual_disks" do
    context "with some disks already in use" do
      before {
        expect(subprocess).to receive(:execute).
          with("VBoxManage", "list", "-l", "hdds", an_instance_of(Hash)).
          and_return(subprocess_result(stdout:
            <<-OUTPUT.gsub(/^ */, '')
              UUID:           e1246c7c-05dd-48c5-aa5b-5ad44ce0c13e
              Parent UUID:    base
              State:          locked read
              Type:           multiattach
              Location:       /home/.vagrant.d/boxes/hashicorp-VAGRANTSLASH-precise64/1.1.0/virtualbox/box-disk1.vmdk
              Storage format: VMDK
              Format variant: dynamic streamOptimized
              Capacity:       81920 MBytes
              Size on disk:   305 MBytes
              Child UUIDs:    1616c5a2-929c-49c1-8f66-08ab44fbc091

              UUID:           1616c5a2-929c-49c1-8f66-08ab44fbc091
              Parent UUID:    e1246c7c-05dd-48c5-aa5b-5ad44ce0c13e
              State:          locked write
              Type:           normal (differencing)
              Auto-Reset:     off
              Location:       /VirtualBox VMs/vagrant_test02_1441657718454_69597/Snapshots/{1616c5a2-929c-49c1-8f66-08ab44fbc091}.vmdk
              Storage format: VMDK
              Format variant: differencing default
              Capacity:       81920 MBytes
              Size on disk:   10 MBytes
              In use by VMs:  vagrant_test02_1441657718454_69597 (UUID: ad89e52f-8e2b-4df7-acc3-a5dacdb0459a)
            OUTPUT
          )
        )
      }

      it "attaches one disk that is already in use" do
        expect(subprocess).to receive(:execute).
          with("VBoxManage", "storageattach", "123",
            "--storagectl", "SATA Controller",
            "--port", "0",
            "--device", "0",
            "--type", "hdd",
            "--medium", "/home/.vagrant.d/boxes/hashicorp-VAGRANTSLASH-precise64/1.1.0/virtualbox/box-disk1.vmdk",
            an_instance_of(Hash)
          ).and_return(subprocess_result(stdout: ""))

        subject.attach_virtual_disks("123",
          [
            {
              :controller => "SATA Controller",
              :port => "0",
              :device => "0",
              :file => "/home/.vagrant.d/boxes/hashicorp-VAGRANTSLASH-precise64/1.1.0/virtualbox/box-disk1.vmdk"
            }
          ]
        )
      end

      it "attaches one disk that is not in use" do
        expect(subprocess).to receive(:execute).
          with("VBoxManage", "storageattach", "123",
            "--storagectl", "SATA Controller",
            "--port", "0",
            "--device", "0",
            "--type", "hdd",
            "--medium", "/test-disk.vmdk",
            "--mtype", "multiattach",
            an_instance_of(Hash)
          ).and_return(subprocess_result(stdout: ""))

        subject.attach_virtual_disks("123",
          [
            {
              :controller => "SATA Controller",
              :port => "0",
              :device => "0",
              :file => "/test-disk.vmdk"
            }
          ]
        )
      end
    end
  end

  describe "get_machine_id" do
    before {
      expect(subprocess).to receive(:execute).
        with("VBoxManage", "list", "vms", an_instance_of(Hash)).
        and_return(subprocess_result(stdout: output))
    }

    context "with list of VMs" do
      let(:output) {
        <<-OUTPUT.gsub(/^ */, '')
          "Another VM" {f6845e8c-1434-4415-b280-964c86ed6fc7}
          "vagrant_test02_1441657718454_69597" {ad89e52f-8e2b-4df7-acc3-a5dacdb0459a}
          "vagrant_test01_1441657738990_91195" {6b9d61f1-e553-4ee9-9ac9-ff5f04614b38}
        OUTPUT
      }

      it "finds a VM" do
        value = subject.get_machine_id("vagrant_test01_1441657738990_91195")

        expect(value).to eq("6b9d61f1-e553-4ee9-9ac9-ff5f04614b38")
      end

      it "does not find a VM" do
        value = subject.get_machine_id("will not be found")

        expect(value).to eq(nil)
      end
    end

    context "with empty output" do
      let(:output) { "" }

      it "returns nil" do
        value = subject.get_machine_id("will not be found")

        expect(value).to eq(nil)
      end
    end
  end

  describe "parse_ovf" do
    context "with OVF with a single disk from hashicorp/precise64" do
      before {
        expect(File).to receive(:open).
          with(an_instance_of(String)).
          and_return(File.open(File.expand_path("single-disk.ovf", File.dirname(__FILE__))))
      }

      it "should have one virtual disk" do
        virtual_disks, doc = subject.parse_ovf("/path/box.ovf")

        expect(virtual_disks).to eq(
          [
            {
              :controller => "SATA Controller",
              :file => "/path/box-disk1.vmdk",
              :port => "0",
              :device => "0"
            }
          ]
        )
      end
    end

    context "with empty OVF" do
      before {
        expect(File).to receive(:open).
          with(an_instance_of(String)).
          and_return(StringIO.new(""))
      }

      it "should not parse correctly" do
        expect { subject.parse_ovf("/path/box.ovf") }.
          to raise_error Vagrant::Errors::VMImportFailure
      end
    end
  end

  describe "read_dhcp_servers" do
    before {
      expect(subprocess).to receive(:execute).
        with("VBoxManage", "list", "dhcpservers", an_instance_of(Hash)).
        and_return(subprocess_result(stdout: output))
    }

    context "with empty output" do
      let(:output) { "" }

      it "returns an empty list" do
        expect(subject.read_dhcp_servers).to eq([])
      end
    end

    context "with a single dhcp server" do
      let(:output) {
        <<-OUTPUT.gsub(/^ */, '')
          NetworkName:    HostInterfaceNetworking-vboxnet0
          IP:             172.28.128.2
          NetworkMask:    255.255.255.0
          lowerIPAddress: 172.28.128.3
          upperIPAddress: 172.28.128.254
          Enabled:        Yes

        OUTPUT
      }


      it "returns a list with one entry describing that server" do
        expect(subject.read_dhcp_servers).to eq([{
          network_name: 'HostInterfaceNetworking-vboxnet0',
          network:      'vboxnet0',
          ip:           '172.28.128.2',
          netmask:      '255.255.255.0',
          lower:        '172.28.128.3',
          upper:        '172.28.128.254',
        }])
      end
    end

    context "with a multiple dhcp servers" do
      let(:output) {
        <<-OUTPUT.gsub(/^ */, '')
          NetworkName:    HostInterfaceNetworking-vboxnet0
          IP:             172.28.128.2
          NetworkMask:    255.255.255.0
          lowerIPAddress: 172.28.128.3
          upperIPAddress: 172.28.128.254
          Enabled:        Yes

          NetworkName:    HostInterfaceNetworking-vboxnet1
          IP:             10.0.0.2
          NetworkMask:    255.255.255.0
          lowerIPAddress: 10.0.0.3
          upperIPAddress: 10.0.0.254
          Enabled:        Yes
        OUTPUT
      }


      it "returns a list with one entry for each server" do
        expect(subject.read_dhcp_servers).to eq([
          {network_name: 'HostInterfaceNetworking-vboxnet0', network: 'vboxnet0', ip: '172.28.128.2', netmask: '255.255.255.0', lower: '172.28.128.3', upper: '172.28.128.254'},
          {network_name: 'HostInterfaceNetworking-vboxnet1', network: 'vboxnet1', ip: '10.0.0.2', netmask: '255.255.255.0', lower: '10.0.0.3', upper: '10.0.0.254'},
        ])
      end
    end
  end

  describe "read_guest_property" do
    it "reads the guest property of the machine referenced by the UUID" do
      key  = "/Foo/Bar"

      expect(subprocess).to receive(:execute).
        with("VBoxManage", "guestproperty", "get", uuid, key, an_instance_of(Hash)).
        and_return(subprocess_result(stdout: "Value: Baz\n"))

      expect(subject.read_guest_property(key)).to eq("Baz")
    end

    it "raises a virtualBoxGuestPropertyNotFound exception when the value is not set" do
      key  = "/Not/There"

      expect(subprocess).to receive(:execute).
        with("VBoxManage", "guestproperty", "get", uuid, key, an_instance_of(Hash)).
        and_return(subprocess_result(stdout: "No value set!"))

      expect { subject.read_guest_property(key) }.
        to raise_error Vagrant::Errors::VirtualBoxGuestPropertyNotFound
    end
  end

  describe "read_guest_ip" do
    it "reads the guest property for the provided adapter number" do
      key = "/VirtualBox/GuestInfo/Net/1/V4/IP"

      expect(subprocess).to receive(:execute).
        with("VBoxManage", "guestproperty", "get", uuid, key, an_instance_of(Hash)).
        and_return(subprocess_result(stdout: "Value: 127.1.2.3"))

      value = subject.read_guest_ip(1)

      expect(value).to eq("127.1.2.3")
    end

    it "does not accept 0.0.0.0 as a valid IP address" do
      key = "/VirtualBox/GuestInfo/Net/1/V4/IP"

      expect(subprocess).to receive(:execute).
        with("VBoxManage", "guestproperty", "get", uuid, key, an_instance_of(Hash)).
        and_return(subprocess_result(stdout: "Value: 0.0.0.0"))

      expect { subject.read_guest_ip(1) }.
        to raise_error Vagrant::Errors::VirtualBoxGuestPropertyNotFound
    end
  end

  describe "read_host_only_interfaces" do
    before {
      expect(subprocess).to receive(:execute).
        with("VBoxManage", "list", "hostonlyifs", an_instance_of(Hash)).
        and_return(subprocess_result(stdout: output))
    }

    context "with empty output" do
      let(:output) { "" }

      it "returns an empty list" do
        expect(subject.read_host_only_interfaces).to eq([])
      end
    end

    context "with a single host only interface" do
      let(:output) {
        <<-OUTPUT.gsub(/^ */, '')
          Name:            vboxnet0
          GUID:            786f6276-656e-4074-8000-0a0027000000
          DHCP:            Disabled
          IPAddress:       172.28.128.1
          NetworkMask:     255.255.255.0
          IPV6Address:
          IPV6NetworkMaskPrefixLength: 0
          HardwareAddress: 0a:00:27:00:00:00
          MediumType:      Ethernet
          Status:          Up
          VBoxNetworkName: HostInterfaceNetworking-vboxnet0

        OUTPUT
      }

      it "returns a list with one entry describing that interface" do
        expect(subject.read_host_only_interfaces).to eq([{
          name:    'vboxnet0',
          ip:      '172.28.128.1',
          netmask: '255.255.255.0',
          status:  'Up',
        }])
      end
    end

    context "with multiple host only interfaces" do
      let(:output) {
        <<-OUTPUT.gsub(/^ */, '')
          Name:            vboxnet0
          GUID:            786f6276-656e-4074-8000-0a0027000000
          DHCP:            Disabled
          IPAddress:       172.28.128.1
          NetworkMask:     255.255.255.0
          IPV6Address:
          IPV6NetworkMaskPrefixLength: 0
          HardwareAddress: 0a:00:27:00:00:00
          MediumType:      Ethernet
          Status:          Up
          VBoxNetworkName: HostInterfaceNetworking-vboxnet0

          Name:            vboxnet1
          GUID:            5764a976-8479-8388-1245-8a0048080840
          DHCP:            Disabled
          IPAddress:       10.0.0.1
          NetworkMask:     255.255.255.0
          IPV6Address:
          IPV6NetworkMaskPrefixLength: 0
          HardwareAddress: 0a:00:27:00:00:01
          MediumType:      Ethernet
          Status:          Up
          VBoxNetworkName: HostInterfaceNetworking-vboxnet1

        OUTPUT
      }

      it "returns a list with one entry for each interface" do
        expect(subject.read_host_only_interfaces).to eq([
          {name: 'vboxnet0', ip: '172.28.128.1', netmask: '255.255.255.0', status: 'Up'},
          {name: 'vboxnet1', ip: '10.0.0.1', netmask: '255.255.255.0', status: 'Up'},
        ])
      end
    end
  end

  describe "remove_dhcp_server" do
    it "removes the dhcp server with the specified network name" do
      expect(subprocess).to receive(:execute).
        with("VBoxManage", "dhcpserver", "remove", "--netname", "HostInterfaceNetworking-vboxnet0", an_instance_of(Hash)).
        and_return(subprocess_result(stdout: ''))

      subject.remove_dhcp_server("HostInterfaceNetworking-vboxnet0")
    end
  end
end
