# SNMP::Info::Layer2::TPLINK
#
# Copyright (c) 2026
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
#     * Neither the name of the copyright owner nor the names of contributors
#       may be used to endorse or promote products derived from this software
#       without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package SNMP::Info::Layer2::TPLINK;

use strict;
use warnings;
use Exporter;
use SNMP::Info::Layer2;

@SNMP::Info::Layer2::TPLINK::ISA       = qw/SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer2::TPLINK::EXPORT_OK = qw//;

our ( $VERSION, %FUNCS, %GLOBALS, %MIBS, %MUNGE );

$VERSION = '3.975000';

%GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS,
    # TP-Link system identity/version
    'tp_hw_ver' => 'tpSysInfoHwVersion',
    'tp_sw_ver' => 'tpSysInfoSwVersion',
);

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,

    # TP-Link VLAN (vendor dot1q mib)
    'tp_vlan_port_num' => 'vlanPortNumber',
    'tp_vlan_port_pvid'=> 'vlanPortPvid',
    'tp_vlan_name'     => 'dot1qVlanDescription',
    'tp_vlan_id'       => 'dot1qVlanId',
    'tp_vlan_tag'      => 'vlanTagPortMemberAdd',
    'tp_vlan_untag'    => 'vlanUntagPortMemberAdd',
);

%MIBS = (
    %SNMP::Info::Layer2::MIBS,

    # TP-Link/Omada
    'TPLINK-SYSINFO-MIB'    => 'tpSysInfoHwVersion',
    'TPLINK-DOT1Q-VLAN-MIB' => 'dot1qVlanId',
);

%MUNGE = (
    %SNMP::Info::Layer2::MUNGE,
);

sub vendor { return 'tplink' }

sub os {
    my $tplink = shift;
    my $descr  = $tplink->description() || '';
    return 'omada' if $descr =~ /omada/i;
    return 'tplink';
}

sub model {
    my $tplink = shift;

    my $hw = $tplink->tp_hw_ver();
    return $hw if defined $hw && length $hw;

    my $m = eval { $tplink->SUPER::model() };
    return $m if defined $m && length $m;

    my $descr = $tplink->description() || '';
    return $descr if length $descr;

    return;
}

sub os_ver {
    my $tplink = shift;

    my $sw = $tplink->tp_sw_ver();
    return $sw if defined $sw && length $sw;

    my $ov = eval { $tplink->SUPER::os_ver() };
    return $ov if defined $ov && length $ov;

    my $descr = $tplink->description() || '';
    return $1 if $descr =~ /\b(?:firmware|software|version|ver)\s*[: ]\s*([0-9][0-9A-Za-z.\-_ ]+)/i;

    return;
}

sub _valid_mac {
    my $mac = shift;
    return unless defined $mac;
    return unless $mac =~ /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i;
    return unless lc($mac) ne '00:00:00:00:00:00';
    return unless (hex((split /:/, $mac)[0]) & 1) == 0; # no multicast bit
    return lc $mac;
}

sub mac {
    my $tplink = shift;

    my $mac = eval { $tplink->SUPER::mac() };
    $mac = _valid_mac($mac);
    return $mac if defined $mac;

    $mac = _valid_mac( $tplink->b_mac() );
    return $mac if defined $mac;

    my $i_mac = $tplink->i_mac() || {};
    foreach my $iid (sort { $a <=> $b } keys %$i_mac) {
        $mac = _valid_mac( $i_mac->{$iid} );
        return $mac if defined $mac;
    }

    return;
}

# -- LLDP quirks -----------------------------------------------------------
# Omada variants may return lldpRemManAddr index without timeMark.
# We attempt to normalize to full key (timeMark.localPort.remIndex) so c_ip
# aligns with c_if/c_port. If unresolved, we skip that address row.

sub _lldp_short_to_full_index_map {
    my ($tplink, $partial) = @_;
    my %map;

    # Build map from whatever full-index LLDP rem tables are available.
    # Keep newest timeMark for same short localPort.remIndex key.
    my @methods = qw(
        lldp_rem_pid
        lldp_rem_sys
        lldp_rem_pdesc
        lldp_rem_port
        lldp_rem_desc
    );

    for my $m (@methods) {
        next unless $tplink->can($m);
        my $h = $tplink->$m($partial) || {};

        for my $full_idx (keys %$h) {
            my ($tm, $lp, $ri) = split /\./, $full_idx, 4;
            next unless defined $tm && defined $lp && defined $ri;
            next unless $tm =~ /^\d+$/ && $lp =~ /^\d+$/ && $ri =~ /^\d+$/;

            my $short = "$lp.$ri";

            if (!exists $map{$short}) {
                $map{$short} = $full_idx;
                next;
            }

            my ($old_tm) = split /\./, $map{$short}, 2;
            $map{$short} = $full_idx if $tm > $old_tm;
        }
    }

    return \%map;
}

sub _lldp_normalize_index {
    my ($tplink, $index, $idx_map) = @_;
    return unless defined $index;

    # already full: timeMark.localPort.remIndex
    return $index if $index =~ /^\d+\.\d+\.\d+$/;

    # short: localPort.remIndex
    if ($index =~ /^\d+\.\d+$/) {
        return $idx_map->{$index};
    }

    return;
}

sub _lldp_addr_index {
    my $tplink = shift;
    my $idx    = shift;

    my @oids = split /\./, $idx;
    return unless @oids >= 4;

    my ($index, $proto, @addr_oids);

    # Standard LLDP-MIB index:
    # timeMark.localPort.remIndex.addrSubtype.addrLen.addr...
    if (@oids >= 6) {
        my @t = @oids;
        my $std_index = join '.', splice(@t, 0, 3);
        my $std_proto = shift @t;
        my $std_len   = shift @t;

        if (defined $std_proto && $std_proto =~ /^(1|2|6)$/
            && defined $std_len && @t >= $std_len)
        {
            @t = @t[0 .. $std_len - 1] if $std_len > 0;
            ($index, $proto, @addr_oids) = ($std_index, $std_proto, @t);
        }
    }

    # Omada variant:
    # localPort.remIndex.addrSubtype.addrLen.addr...
    if (!defined $proto && @oids >= 5) {
        my @t = @oids;
        my $short_index = join '.', splice(@t, 0, 2);
        my $short_proto = shift @t;
        my $short_len   = shift @t;

        return unless defined $short_proto && $short_proto =~ /^(1|2|6)$/;
        return unless defined $short_len   && @t >= $short_len;

        @t = @t[0 .. $short_len - 1] if $short_len > 0;
        ($index, $proto, @addr_oids) = ($short_index, $short_proto, @t);
    }

    return unless defined $index && defined $proto;

    if ($proto == 1) {        # IPv4
        return unless @addr_oids == 4;
        return ($index, $proto, join '.', @addr_oids);
    }
    elsif ($proto == 2) {     # IPv6
        return ($index, $proto, join ':', unpack '(H4)*', pack('C*', @addr_oids));
    }
    elsif ($proto == 6) {     # MAC
        return ($index, $proto, join ':', map { sprintf "%02x", $_ } @addr_oids);
    }

    return;
}

sub lldp_ip {
    my $tplink  = shift;
    my $partial = shift;

    my $rman_addr = $tplink->lldp_rman_addr($partial) || {};
    return $tplink->SUPER::lldp_ip($partial) unless scalar keys %$rman_addr;

    my $idx_map = $tplink->_lldp_short_to_full_index_map($partial);
    my %lldp_ip;

    foreach my $key (keys %$rman_addr) {
        my ($index, $proto, $addr) = $tplink->_lldp_addr_index($key);
        next unless defined $index && $proto == 1;

        my $full = $tplink->_lldp_normalize_index($index, $idx_map);
        next unless defined $full;

        $lldp_ip{$full} = $addr;
    }

    return scalar(keys %lldp_ip) ? \%lldp_ip : $tplink->SUPER::lldp_ip($partial);
}

sub lldp_ipv6 {
    my $tplink  = shift;
    my $partial = shift;

    my $rman_addr = $tplink->lldp_rman_addr($partial) || {};
    return $tplink->SUPER::lldp_ipv6($partial) unless scalar keys %$rman_addr;

    my $idx_map = $tplink->_lldp_short_to_full_index_map($partial);
    my %lldp_ipv6;

    foreach my $key (keys %$rman_addr) {
        my ($index, $proto, $addr) = $tplink->_lldp_addr_index($key);
        next unless defined $index && $proto == 2;

        my $full = $tplink->_lldp_normalize_index($index, $idx_map);
        next unless defined $full;

        $lldp_ipv6{$full} = $addr;
    }

    return scalar(keys %lldp_ipv6) ? \%lldp_ipv6 : $tplink->SUPER::lldp_ipv6($partial);
}

sub lldp_mac {
    my $tplink  = shift;
    my $partial = shift;

    my $rman_addr = $tplink->lldp_rman_addr($partial) || {};
    return $tplink->SUPER::lldp_mac($partial) unless scalar keys %$rman_addr;

    my $idx_map = $tplink->_lldp_short_to_full_index_map($partial);
    my %lldp_mac;

    foreach my $key (keys %$rman_addr) {
        my ($index, $proto, $addr) = $tplink->_lldp_addr_index($key);
        next unless defined $index && $proto == 6;

        my $full = $tplink->_lldp_normalize_index($index, $idx_map);
        next unless defined $full;

        $lldp_mac{$full} = $addr;
    }

    return scalar(keys %lldp_mac) ? \%lldp_mac : $tplink->SUPER::lldp_mac($partial);
}

sub lldp_addr {
    my $tplink  = shift;
    my $partial = shift;

    my $rman_addr = $tplink->lldp_rman_addr($partial) || {};
    return $tplink->SUPER::lldp_addr($partial) unless scalar keys %$rman_addr;

    my $idx_map = $tplink->_lldp_short_to_full_index_map($partial);
    my %lldp_addr;

    foreach my $key (keys %$rman_addr) {
        my ($index, $proto, $addr) = $tplink->_lldp_addr_index($key);
        next unless defined $index;

        my $full = $tplink->_lldp_normalize_index($index, $idx_map);
        next unless defined $full;

        $lldp_addr{$full} = $addr;
    }

    return scalar(keys %lldp_addr) ? \%lldp_addr : $tplink->SUPER::lldp_addr($partial);
}

# -- VLAN helpers ----------------------------------------------------------

sub _trim {
    my $v = shift;
    return '' unless defined $v;
    $v =~ s/^\s+//;
    $v =~ s/\s+$//;
    return $v;
}

sub _tp_port_token_to_ifindex {
    my $tplink = shift;
    my $map    = shift; # ifIndex => "1/0/x"
    my %rev;

    foreach my $iid (keys %$map) {
        my $token = _trim($map->{$iid});
        next unless length $token;
        $rev{$token} = $iid;
    }

    return \%rev;
}

sub _expand_port_list_tokens {
    my $list = shift;
    $list = _trim($list);
    return [] unless length $list;

    my @out;
    foreach my $part (split /\s*,\s*/, $list) {
        next unless length $part;

        # 1/0/9-28
        if ($part =~ m{^(\d+/\d+)/(\d+)-(\d+)$}) {
            my ($prefix, $a, $b) = ($1, $2, $3);
            my ($start, $end) = $a <= $b ? ($a, $b) : ($b, $a);
            push @out, map { "${prefix}/$_" } ($start .. $end);
            next;
        }

        # 1/0/5
        if ($part =~ m{^\d+/\d+/\d+$}) {
            push @out, $part;
            next;
        }

        # Unknown format - keep token as-is (best effort)
        push @out, $part;
    }

    return \@out;
}

# VLAN names keyed by VLAN ID.
sub v_name {
    my $tplink = shift;

    my $names = $tplink->tp_vlan_name() || {};
    my $ids   = $tplink->tp_vlan_id()   || {};

    my %v_name;

    foreach my $vid (keys %$ids) {
        # Some agents return value==vid; keys are the index we want.
        my $v = $ids->{$vid};
        my $id = ($vid =~ /^\d+$/) ? $vid : $v;
        next unless defined $id && $id =~ /^\d+$/;
        $v_name{$id} = "VLAN$id" unless exists $v_name{$id};
    }

    foreach my $vid (keys %$names) {
        next unless $vid =~ /^\d+$/;
        my $name = _trim($names->{$vid});
        $v_name{$vid} = length $name ? $name : "VLAN$vid";
    }

    return scalar(keys %v_name) ? \%v_name : $tplink->SUPER::v_name();
}

# Access VLAN (PVID) per interface index.
sub i_vlan {
    my $tplink  = shift;
    my $partial = shift;

    my $pvid = $tplink->tp_vlan_port_pvid($partial) || {};
    return $tplink->SUPER::i_vlan($partial) unless scalar keys %$pvid;

    my %i_vlan;
    foreach my $iid (keys %$pvid) {
        my $vid = $pvid->{$iid};
        next unless defined $vid && $vid =~ /^\d+$/;
        $i_vlan{$iid} = $vid;
    }

    return scalar(keys %i_vlan) ? \%i_vlan : $tplink->SUPER::i_vlan($partial);
}

# VLAN membership per interface index (tagged + untagged sets).
# Returns: { ifIndex => [ vlan_ids... ] }
sub i_vlan_membership {
    my $tplink  = shift;
    my $partial = shift;

    my $port_num = $tplink->tp_vlan_port_num($partial) || {};
    my $tag_tbl  = $tplink->tp_vlan_tag($partial)      || {};
    my $unt_tbl  = $tplink->tp_vlan_untag($partial)    || {};

    return $tplink->SUPER::i_vlan_membership($partial)
        unless scalar(keys %$port_num) && (scalar(keys %$tag_tbl) || scalar(keys %$unt_tbl));

    my $token_to_iid = $tplink->_tp_port_token_to_ifindex($port_num);
    my %member; # iid => { vid => 1 }

    foreach my $vid (keys %$tag_tbl) {
        next unless $vid =~ /^\d+$/;
        my $tokens = _expand_port_list_tokens($tag_tbl->{$vid});
        foreach my $tok (@$tokens) {
            my $iid = $token_to_iid->{$tok};
            next unless defined $iid;
            $member{$iid}{$vid} = 1;
        }
    }

    foreach my $vid (keys %$unt_tbl) {
        next unless $vid =~ /^\d+$/;
        my $tokens = _expand_port_list_tokens($unt_tbl->{$vid});
        foreach my $tok (@$tokens) {
            my $iid = $token_to_iid->{$tok};
            next unless defined $iid;
            $member{$iid}{$vid} = 1;
        }
    }

    my %out;
    foreach my $iid (keys %member) {
        my @vids = sort { $a <=> $b } keys %{ $member{$iid} || {} };
        $out{$iid} = \@vids if @vids;
    }

    return scalar(keys %out) ? \%out : $tplink->SUPER::i_vlan_membership($partial);
}

1;

__END__

=head1 NAME

SNMP::Info::Layer2::TPLINK - SNMP Interface for TP-Link / Omada Layer 2 devices

=head1 AUTHOR

Your Team / Contributors

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you.
 my $tp = new SNMP::Info(
     AutoSpecify => 1,
     Debug       => 1,
     DestHost    => 'myswitch',
     Community   => 'public',
     Version     => 2
 ) or die "Can't connect to host.\n";

 print "Class: " . $tp->class . "\n";

=head1 DESCRIPTION

Provides abstraction to configuration and topology information from TP-Link
(and Omada-managed) Layer 2 devices through SNMP.

This class adds:

=over

=item *

System/version parsing via TPLINK-SYSINFO-MIB.

=item *

Robust base MAC resolution (SUPER -> BRIDGE-MIB -> interface MAC fallback).

=item *

LLDP remote management address index normalization for Omada variants that
may omit C<lldpRemTimeMark> in C<lldpRemManAddrTable> indexing.

=item *

VLAN name/access/membership data via TPLINK-DOT1Q-VLAN-MIB when Q-BRIDGE-MIB
tables are absent.

=back

All TP-Link-specific logic is best-effort and falls back to inherited
SNMP::Info::Layer2 behavior when vendor tables are not present.

=head1 INHERITED CLASSES

=over

=item SNMP::Info::Layer2

=back

=head1 REQUIRED MIBS

=over

=item TPLINK-SYSINFO-MIB

=item TPLINK-DOT1Q-VLAN-MIB

=back

=head1 GLOBALS

=head2 Overrides

=over

=item vendor()

Returns C<tplink>.

=item os()

Returns C<omada> when detected in description, otherwise C<tplink>.

=item os_ver()

Returns software version string from C<tpSysInfoSwVersion> when available.

=item model()

Returns hardware/model string from C<tpSysInfoHwVersion> when available.

=item mac()

Returns stable chassis/base MAC using inherited logic with safe fallback.

=back

=head1 TABLE METHODS

=head2 Overrides

=over

=item lldp_ip(), lldp_ipv6(), lldp_mac(), lldp_addr()

Handles Omada LLDP remote management address index variant.

=item v_name()

VLAN ID to VLAN name map from TP-Link VLAN table.

=item i_vlan()

Access VLAN (PVID) per interface.

=item i_vlan_membership()

VLAN memberships per interface from tagged/untagged member strings.

=back

=cut

