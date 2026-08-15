# Test::SNMP::Info::Layer2::TPLINK
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

package Test::SNMP::Info::Layer2::TPLINK;

use Test::Class::Most parent => 'My::Test::Class';

use SNMP::Info::Layer2::TPLINK;

sub _base_cache {
  return {
    '_layers'      => 2,
    '_description' => 'Omada Managed Switch',
    '_id'          => '.1.3.6.1.4.1.11863.1',

    # globals
    '_tp_hw_ver'             => 'TL-SG3428X',
    '_tp_sw_ver'             => '1.0.5 Build 20260101',
    '_tp_serial'             => 'TP1234567890',
    '_tp_psu_capacity'       => '150',
    '_tp_psu_remaining_time' => '35',
    '_tp_psu_internal_power' => 'normal',
    '_tp_psu_external_power' => 'notPresent',
    '_b_mac'                 => '00:11:22:33:44:55',

    # table flags
    '_tp_vlan_port_num'  => 1,
    '_tp_vlan_port_pvid' => 1,
    '_tp_vlan_name'      => 1,
    '_tp_vlan_id'        => 1,
    '_tp_vlan_tag'       => 1,
    '_tp_vlan_untag'     => 1,
    '_i_mac'             => 1,
    '_lldp_rman_addr'    => 1,
    '_lldp_rem_sys'      => 1,

    'store' => {
      # VLAN
      'tp_vlan_port_num'  => { 101 => '1/0/1', 102 => '1/0/2', 103 => '1/0/3' },
      'tp_vlan_port_pvid' => { 101 => 10, 102 => 10, 103 => 20 },
      'tp_vlan_name'      => { 10  => 'Users', 20  => 'Servers' },
      'tp_vlan_id'        => { 10  => 10, 20   => 20 },
      'tp_vlan_tag'       => { 10  => '1/0/1-2', 20 => '1/0/3' },
      'tp_vlan_untag'     => { 10  => '1/0/3' },

      # MAC fallback candidates
      'i_mac' => {
        1 => '01:00:5e:00:00:01', # multicast (invalid for base)
        2 => '00:00:00:00:00:00', # invalid
        3 => '00:aa:bb:cc:dd:ee', # valid
      },

      # LLDP rem sys provides full indexes used to normalize short keys
      'lldp_rem_sys' => {
        '100.1.7' => 'upstream-a',
        '101.2.9' => 'upstream-b',
        '102.3.4' => 'upstream-c',
      },

      # Omada short index variant:
      # localPort.remIndex.addrSubtype.addrLen.addr...
      'lldp_rman_addr' => {
        '1.7.1.4.10.0.0.7' => 1,   # IPv4 10.0.0.7
        '2.9.6.6.0.17.34.51.68.85' => 1, # MAC 00:11:22:33:44:55
        '3.4.2.16.32.1.13.184.0.0.0.0.0.0.0.0.0.0.0.1' => 1, # 2001:db8::1
      },
    },
  };
}

sub setup : Tests(setup) {
  my $test = shift;
  $test->SUPER::setup;
  $test->{info}->cache(_base_cache());
}

sub vendor_and_os : Tests(4) {
  my $test = shift;

  can_ok($test->{info}, 'vendor');
  can_ok($test->{info}, 'os');

  is($test->{info}->vendor(), 'tplink', q(Vendor returns 'tplink'));
  is($test->{info}->os(),     'omada',  q(OS returns 'omada' when description matches));
}

sub model_osver_serial : Tests(6) {
  my $test = shift;

  can_ok($test->{info}, 'model');
  can_ok($test->{info}, 'os_ver');
  can_ok($test->{info}, 'serial');

  is($test->{info}->model(),  'TL-SG3428X',            q(Model from tp_hw_ver));
  is($test->{info}->os_ver(), '1.0.5 Build 20260101',  q(OS version from tp_sw_ver));
  is($test->{info}->serial(), 'TP1234567890',          q(Serial from tp_serial));
}

sub mac_resolution : Tests(4) {
  my $test = shift;

  can_ok($test->{info}, 'mac');

  # Uses b_mac when valid
  is($test->{info}->mac(), '00:11:22:33:44:55', q(mac() prefers valid base MAC));

  # Force invalid b_mac; should fall through to i_mac valid entry
  my $cache = _base_cache();
  $cache->{_b_mac} = '01:00:5e:00:00:01'; # multicast -> invalid
  $test->{info}->cache($cache);

  is($test->{info}->mac(), '00:aa:bb:cc:dd:ee', q(mac() falls back to first valid i_mac));

  # All invalid -> undef
  $cache = _base_cache();
  $cache->{_b_mac} = '00:00:00:00:00:00';
  $cache->{store}{i_mac} = {
    1 => '01:00:5e:00:00:01',
    2 => '00:00:00:00:00:00',
  };
  $test->{info}->cache($cache);

  is($test->{info}->mac(), undef, q(mac() returns undef when no valid candidate exists));
}

sub vlan_helpers : Tests(6) {
  my $test = shift;

  can_ok($test->{info}, 'v_name');
  can_ok($test->{info}, 'i_vlan');
  can_ok($test->{info}, 'i_vlan_membership');

  is_deeply(
    $test->{info}->v_name(),
    { 10 => 'Users', 20 => 'Servers' },
    q(v_name returns expected VLAN names)
  );

  is_deeply(
    $test->{info}->i_vlan(),
    { 101 => 10, 102 => 10, 103 => 20 },
    q(i_vlan returns expected PVID map)
  );

  is_deeply(
    $test->{info}->i_vlan_membership(),
    { 101 => [10], 102 => [10], 103 => [10, 20] },
    q(i_vlan_membership returns expected tagged+untagged VLAN sets)
  );
}

sub lldp_addr_normalization : Tests(6) {
  my $test = shift;

  can_ok($test->{info}, 'lldp_ip');
  can_ok($test->{info}, 'lldp_ipv6');
  can_ok($test->{info}, 'lldp_mac');

  is_deeply(
    $test->{info}->lldp_ip(),
    { '100.1.7' => '10.0.0.7' },
    q(lldp_ip normalizes Omada short index to full index)
  );

  is_deeply(
    $test->{info}->lldp_mac(),
    { '101.2.9' => '00:11:22:33:44:55' },
    q(lldp_mac normalizes Omada short index to full index)
  );

  is_deeply(
    $test->{info}->lldp_ipv6(),
    { '102.3.4' => '2001:0db8:0000:0000:0000:0000:0000:0001' },
    q(lldp_ipv6 normalizes Omada short index to full index)
  );
}

sub psu_methods : Tests(8) {
  my $test = shift;

  can_ok($test->{info}, 'psu_capacity');
  can_ok($test->{info}, 'psu_remaining_minutes');
  can_ok($test->{info}, 'psu_internal_power_status');
  can_ok($test->{info}, 'psu_external_power_status');
  can_ok($test->{info}, 'ps1');
  can_ok($test->{info}, 'ps2');

  is($test->{info}->psu_capacity(),          150,         q(psu_capacity returns integer));
  is($test->{info}->psu_remaining_minutes(), 35,          q(psu_remaining_minutes returns integer));
}

1;
