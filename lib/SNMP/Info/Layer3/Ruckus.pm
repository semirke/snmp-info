# SNMP::Info::Layer3::Ruckus
# $Id$
#
# Copyright (c) 2013 Eric Miller
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the University of California, Santa Cruz nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR # ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package SNMP::Info::Layer3::Ruckus;

use strict;
use Exporter;
use SNMP::Info::Layer3;
use SNMP::Info::LLDP;

@SNMP::Info::Layer3::Ruckus::ISA       = qw/SNMP::Info::LLDP SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::Ruckus::EXPORT_OK = qw//;

our ($VERSION, %FUNCS, %GLOBALS, %MIBS, %MUNGE);

$VERSION = '3.67';

%MIBS = (
    %SNMP::Info::Layer3::MIBS,
    %SNMP::Info::LLDP::MIBS,
    "RUCKUS-ZD-SYSTEM-MIB" => "ruckusZDSystemSerialNumber",
    
);

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS,
    %SNMP::Info::LLDP::GLOBALS,
    'ruckuse_serial' => 'ruckusZDSystemSerialNumber',
);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS,
    %SNMP::Info::LLDP::FUNCS,
);

%MUNGE = (
    %SNMP::Info::Layer3::MUNGE,
    %SNMP::Info::LLDP::MUNGE,

);

sub layers {
    return '00000111';
}

sub os {
    my $ruckus = shift;
#    my %osmap = ( 'alcatel-lucent' => 'aos-w', );
#    return $osmap{ $ruckus->vendor() } || 'airos';
    return "ruckusOS";
}

sub v_name {
    my $ruckus = shift;
    my $partial = shift;

    return $ruckus->ruckus_v_name($partial);
}


sub vendor {
    my $ruckus  = shift;
    my $id     = $ruckus->id() || 'undef';
    my %oidmap = ( 25053 => 'ruckus', );
    $id = $1 if ( defined($id) && $id =~ /^\.1\.3\.6\.1\.4\.1\.(\d+)/ );

    if ( defined($id) and exists( $oidmap{$id} ) ) {
	return $oidmap{$id};
    }
    else {
	return 'ruckus';
    }
}

sub os_ver {
    my $ruckus = shift;
    my $descr = $ruckus->description();
    return unless defined $descr;

    if ( $descr =~ m/Version\s+(\d+\.\d+\.\d+\.\d+)/ ) {
	return $1;
    }

    return;
}

sub model {
    my $ruckus = shift;
    my $id    = $ruckus->id();
    return unless defined $id;
    my $model = &SNMP::translateObj($id);
    return $id unless defined $model;

    return $model;
}


sub serial {
    my $ruckus = shift;

    return $ruckus->ruckus_serial();
}


1;

__END__

=head1 NAME

SNMP::Info::Layer3::Ruckus - SNMP Interface to Ruckus wireless switches

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

    my $ruckus = new SNMP::Info(
			  AutoSpecify => 1,
			  Debug       => 1,
			  DestHost    => 'myswitch',
			  Community   => 'public',
			  Version     => 2
			)

    or die "Can't connect to DestHost.\n";

    my $class = $ruckus->class();
    print " Using device sub class : $class\n";

=head1 DESCRIPTION

SNMP::Info::Layer3::Ruckus is a subclass of SNMP::Info that provides an
interface to Ruckus wireless switches.  The Ruckus platform utilizes
intelligent wireless switches which control thin access points.  The thin
access points themselves are unable to be polled for end station information.

This class emulates bridge functionality for the wireless switch. This enables
end station MAC addresses collection and correlation to the thin access point
the end station is using for communication.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above.

 my $ruckus = new SNMP::Info::Layer3::Ruckus(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item F<WLSR-AP-MIB>

=item F<WLSX-IFEXT-MIB>

=item F<WLSX-POE-MIB>

=item F<WLSX-SWITCH-MIB>

=item F<WLSX-SYSTEMEXT-MIB>

=item F<WLSX-USER-MIB>

=item F<WLSX-WLAN-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info::Layer3/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $ruckus->model()

Returns model type.  Cross references $ruckus->id() with product IDs in the
Ruckus MIB.

=item $ruckus->vendor()

Returns 'ruckus'

=item $ruckus->os()

Returns 'airos'

=item $ruckus->os_ver()

Returns the software version extracted from C<sysDescr>

=back

=head2 Overrides

=over

=item $ruckus->layers()

Returns 00000111.  Class emulates Layer 2 and Layer 3functionality for
Thin APs through proprietary MIBs.

=item $ruckus->serial()

Returns the device serial number extracted
from C<wlsxSwitchLicenseSerialNumber> or C<wlsxSysExtLicenseSerialNumber>

=back

=head2 Globals imported from SNMP::Info::Layer3

See L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=item $ruckus->i_80211channel()

Returns reference to hash.  Current operating frequency channel of the radio
interface.

(C<wlanAPRadioChannel>)

=item $ruckus->dot11_cur_tx_pwr_mw()

Returns reference to hash.  Current transmit power, in milliwatts, of the
radio interface.

(C<wlanAPRadioTransmitPower>)

=item $ruckus->i_ssidlist()

Returns reference to hash.  SSID's recognized by the radio interface.

(C<wlanAPESSID>)

=item $ruckus->i_ssidbcast()

Returns reference to hash.  Indicates whether the SSID is broadcast, true or
false.

(C<wlsrHideSSID>)

=item $ruckus->i_ssidmac()

With the same keys as i_ssidlist, returns the Basic service set
identification (BSSID), MAC address, the AP is using for the SSID.

=item $ruckus->cd11_mac()

Returns client radio interface MAC addresses.

=item $ruckus->cd11_sigqual()

Returns client signal quality.

=item $ruckus->cd11_txrate()

Returns to hash of arrays.  Client transmission speed in Mbs.

=item $ruckus->cd11_rxbyte()

Total bytes received by the wireless client.

=item $ruckus->cd11_txbyte()

Total bytes transmitted by the wireless client.

=item $ruckus->cd11_rxpkt()

Total packets received by the wireless client.

=item $ruckus->cd11_txpkt()

Total packets transmitted by the wireless client.

=back

=head2 Overrides

=over

=item $ruckus->i_index()

Returns reference to map of IIDs to Interface index.

Extends C<ifIndex> to support APs as device interfaces.

=item $ruckus->interfaces()

Returns reference to map of IIDs to ports.  Thin APs are implemented as
device interfaces.  The thin AP MAC address and radio number
(C<wlanAPRadioNumber>) are combined as the port identifier.

=item $ruckus->i_name()

Interface name.  Returns (C<ifName>) for Ethernet interfaces and
(C<wlanAPRadioAPName>) for AP interfaces.

=item $ruckus->i_description()

Returns reference to map of IIDs to interface descriptions.  Returns
C<ifDescr> for Ethernet interfaces and the Fully Qualified Location Name
(C<wlanAPFQLN>) for AP interfaces.

=item $ruckus->i_type()

Returns reference to map of IIDs to interface types.  Returns
C<ifType> for Ethernet interfaces and C<wlanAPRadioType> for AP
interfaces.

=item $ruckus->i_up()

Returns reference to map of IIDs to link status of the interface.  Returns
C<ifOperStatus> for Ethernet interfaces and C<wlanAPStatus> for AP
interfaces.

=item $ruckus->i_up_admin()

Returns reference to map of IIDs to administrative status of the interface.
Returns C<ifAdminStatus> for Ethernet interfaces and C<wlanAPStatus>
for AP interfaces.

=item $ruckus->i_mac()

Interface MAC address.  Returns interface MAC address for Ethernet
interfaces of ports and APs.

=item $ruckus->i_duplex()

Returns reference to map of IIDs to current link duplex.  Ethernet interfaces
only.

=item $ruckus->v_index()

Returns VLAN IDs.

=item $ruckus->v_name()

Human-entered name for vlans.

=item $ruckus->i_vlan()

Returns reference to map of IIDs to VLAN ID of the interface.

=item $ruckus->i_vlan_membership()

Returns reference to hash of arrays: key = C<ifIndex>, value = array of VLAN
IDs.  These are the VLANs for which the port is a member.

=item $ruckus->i_vlan_membership_untagged()

Returns reference to hash of arrays: key = C<ifIndex>, value = array of VLAN
IDs.  These are the VLANs which are members of the untagged egress list for
the port.

=item $ruckus->bp_index()

Augments the bridge MIB by returning reference to a hash containing the
index mapping of BSSID to device port (AP).

=item $ruckus->fw_port()

Augments the bridge MIB by including the BSSID a wireless end station is
communicating through (C<nUserApBSSID>).

=item $ruckus->fw_mac()

Augments the bridge MIB by including the wireless end station MAC
(C<nUserApBSSID>) as extracted from the IID.

=item $ruckus->qb_fw_vlan()

Augments the bridge MIB by including wireless end station VLANs
(C<nUserCurrentVlan>).

=back

=head2 Pseudo F<ENTITY-MIB> information

These methods emulate F<ENTITY-MIB> Physical Table methods using
F<WLSX-WLAN-MIB> and F<WLSX-SYSTEMEXT-MIB>.  APs are included as
subcomponents of the wireless controller.

=over

=item $ruckus->e_index()

Returns reference to hash.  Key: IID and Value: Integer. The index for APs is
created with an integer representation of the last three octets of the
AP MAC address.

=item $ruckus->e_class()

Returns reference to hash.  Key: IID, Value: General hardware type.  Returns
'ap' for wireless access points.

=item $ruckus->e_name()

More computer friendly name of entity.  Name is 'WLAN Controller' for the
chassis, Card # for modules, or 'AP'.

=item $ruckus->e_descr()

Returns reference to hash.  Key: IID, Value: Human friendly name.

=item $ruckus->e_model()

Returns reference to hash.  Key: IID, Value: Model name.

=item $ruckus->e_type()

Returns reference to hash.  Key: IID, Value: Type of component.

=item $ruckus->e_hwver()

Returns reference to hash.  Key: IID, Value: Hardware revision.

=item $ruckus->e_swver()

Returns reference to hash.  Key: IID, Value: Software revision.

=item $ruckus->e_vendor()

Returns reference to hash.  Key: IID, Value: ruckus.

=item $ruckus->e_serial()

Returns reference to hash.  Key: IID, Value: Serial number.

=item $ruckus->e_pos()

Returns reference to hash.  Key: IID, Value: The relative position among all
entities sharing the same parent. Chassis cards are ordered to come before
APs.

=item $ruckus->e_parent()

Returns reference to hash.  Key: IID, Value: The value of e_index() for the
entity which 'contains' this entity.

=back

=head2 Power Over Ethernet Port Table

These methods emulate the F<POWER-ETHERNET-MIB> Power Source Entity (PSE)
Port Table C<pethPsePortTable> methods using the F<WLSX-POE-MIB> Power
over Ethernet Port Table C<wlsxPsePortTable>.

=over

=item $ruckus->peth_port_ifindex()

Creates an index of module.port to align with the indexing of the
C<wlsxPsePortTable> with a value of C<ifIndex>.  The module defaults 1
if otherwise unknown.

=item $ruckus->peth_port_admin()

Administrative status: is this port permitted to deliver power?

C<wlsxPsePortAdminStatus>

=item $ruckus->peth_port_status()

Current status: is this port delivering power.

=item $ruckus->peth_port_class()

Device class: if status is delivering power, this represents the 802.3af
class of the device being powered.

=item $ruckus->peth_port_neg_power()

The power, in milliwatts, that has been committed to this port.
This value is derived from the 802.3af class of the device being
powered.

=item $ruckus->peth_port_power()

The power, in milliwatts, that the port is delivering.

=back

=head2 Power Over Ethernet Module Table

These methods emulate the F<POWER-ETHERNET-MIB> Main Power Source Entity
(PSE) Table C<pethMainPseTable> methods using the F<WLSX-POE-MIB> Power
over Ethernet Port Table C<wlsxPseSlotTable>.

=over

=item $ruckus->peth_power_watts()

The power supply's capacity, in watts.

=item $ruckus->peth_power_status()

The power supply's operational status.

=item $ruckus->peth_power_consumption()

How much power, in watts, this power supply has been committed to
deliver.

=back

=head2 Arp Cache Table Augmentation

The controller has knowledge of MAC->IP mappings for wireless clients.
Augmenting the arp cache data with these MAC->IP mappings enables visibility
for stations that only communicate locally.  We also capture the AP MAC->IP
mappings.

=over

=item $ruckus->at_paddr()

Adds MAC addresses extracted from the index of C<nUserApBSSID>.

=item $ruckus->at_netaddr()

Adds IP addresses extracted from the index of C<nUserApBSSID>.

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=head1 Data Munging Callback Subroutines

=over

=item $ruckus->munge_ruckus_fqln()

Remove nulls encoded as '\.0' from the Fully Qualified Location Name
(C<wlanAPFQLN>).

=back

=cut
