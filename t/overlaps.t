#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Differences;
use lib 't';
use Test_Netspoc;

my ($title, $topo, $in, $out);

############################################################
# Common topology for multiple tests
############################################################

$topo =  <<'END';
network:Test = { ip = 10.9.1.0/24; }
router:filter = {
 managed;
 model = ASA;
 interface:Test = { ip = 10.9.1.1; hardware = Vlan1; }
 interface:N = { ip = 10.1.1.1; hardware = Vlan2; }
}
network:N = {
 ip = 10.1.1.0/24; 
 host:h1 = {   ip = 10.1.1.10;  }
}
END

############################################################
$title = 'Warn on duplicate and redundant rule';
############################################################

$in = $topo . <<'END';
service:test1a = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = tcp 22;
}
service:test1b = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = tcp 22;
}
service:test2 = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = tcp;
}
END

$out = <<'END';
Warning: Duplicate rules in service:test1b and service:test1a:
  permit src=host:h1; dst=network:Test; prt=tcp 22; of service:test1b
Warning: Redundant rules in service:test1a compared to service:test2:
  permit src=host:h1; dst=network:Test; prt=tcp 22; of service:test1a
< permit src=host:h1; dst=network:Test; prt=tcp; of service:test2
--filter
access-list Vlan2_in extended permit tcp host 10.1.1.10 10.9.1.0 255.255.255.0
access-list Vlan2_in extended deny ip any any
access-group Vlan2_in in interface Vlan2
END

test_warn($title, $in, $out);

############################################################
$title = 'Suppressed warning';
############################################################

$in = $topo . <<'END';
service:test1a = {
 overlaps = service:test2;
 user = host:h1;
 permit src = user; dst = network:Test; prt = tcp 22;
}
service:test1b = {
 overlaps = service:test1a;
 user = host:h1;
 permit src = user; dst = network:Test; prt = tcp 22;
}
service:test2 = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = tcp;
}
END

$out = <<'END';
END

test_warn($title, $in, $out);

############################################################
$title = 'Suppressed warning by protocol modifier';
############################################################

$in = $topo . <<'END';
protocol:ssh = tcp 22, overlaps;
protocol:tcp = tcp, overlaps;
service:test1a = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = protocol:ssh;
}
service:test1b = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = protocol:ssh;
}
service:test2 = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = protocol:tcp;
}
END

$out = <<'END';
END

test_warn($title, $in, $out);

############################################################
$title = "Single protocol won't suppress warning";
############################################################

$in = $topo . <<'END';
protocol:ssh = tcp 22, overlaps;
service:test1a = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = protocol:ssh;
}
service:test1b = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = tcp 22;
}
service:test2 = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = tcp;
}
END

$out = <<'END';
Warning: Duplicate rules in service:test1b and service:test1a:
  permit src=host:h1; dst=network:Test; prt=tcp 22; of service:test1b
Warning: Redundant rules in service:test1a compared to service:test2:
  permit src=host:h1; dst=network:Test; prt=protocol:ssh; of service:test1a
< permit src=host:h1; dst=network:Test; prt=tcp; of service:test2
END

test_warn($title, $in, $out);

############################################################
$title = 'Multiple larger rules, one suppressed';
############################################################

$in = $topo . <<'END';
service:test = {
 overlaps = service:test2;
 user = host:h1, network:N;
 permit src = user; dst = network:Test; prt = tcp 22;
}
service:test2 = {
 user = host:h1;
 permit src = user; dst = network:Test; prt = tcp;
}
END

$out = <<'END';
Warning: Redundant rules in service:test compared to service:test:
  permit src=host:h1; dst=network:Test; prt=tcp 22; of service:test
< permit src=network:N; dst=network:Test; prt=tcp 22; of service:test
END

test_warn($title, $in, $out);

############################################################

done_testing;
