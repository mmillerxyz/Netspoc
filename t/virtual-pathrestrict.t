#!/usr/bin/perl

use strict;
use Test::More;
use Test::Differences;
use lib 't';
use Test_Netspoc;

my ($title, $in, $out1, $out2, $out3, $head1, $head2, $head3);

############################################################
$title = 'Implicit pathrestriction with 3 virtual interfaces';
############################################################

$in = <<END;
network:a = { ip = 10.1.1.0/24;}
network:x = { ip = 10.3.3.0/24;}

router:r1 = {
 managed;
 model = IOS, FW;
 interface:a = {ip = 10.1.1.1; hardware = E1;}
 interface:x = {ip = 10.3.3.1; hardware = E3;}
 interface:b = {ip = 10.2.2.1; virtual = {ip = 10.2.2.9;} hardware = E2;}
}

router:r2 = {
 managed;
 model = IOS, FW;
 interface:a = {ip = 10.1.1.2; hardware = E4;}
 interface:b = {ip = 10.2.2.2; virtual = {ip = 10.2.2.9;} hardware = E5;}
}

router:r3 = {
 managed;
 model = IOS, FW;
 interface:a = {ip = 10.1.1.3; hardware = E6;}
 interface:b = {ip = 10.2.2.3; virtual = {ip = 10.2.2.9;} hardware = E7;}
}

network:b  = { ip = 10.2.2.0/24; }

service:test = {
 user = network:a;
 permit src = user; dst = network:x, network:b; prt = ip;
}
END

$out1 = <<END;
ip access-list extended E1_in
 deny ip any host 10.3.3.1
 deny ip any host 10.2.2.9
 deny ip any host 10.2.2.1
 permit ip 10.1.1.0 0.0.0.255 10.3.3.0 0.0.0.255
 permit ip 10.1.1.0 0.0.0.255 10.2.2.0 0.0.0.255
 deny ip any any
END

$out2 = <<END;
ip access-list extended E4_in
 deny ip any host 10.2.2.9
 deny ip any host 10.2.2.2
 permit ip 10.1.1.0 0.0.0.255 10.2.2.0 0.0.0.255
 deny ip any any
END

$head1 = (split /\n/, $out1)[0];
$head2 = (split /\n/, $out2)[0];

eq_or_diff(get_block(compile($in), $head1, $head2), $out1.$out2, $title);

############################################################
$title = 'Extra pathrestriction at 2 virtual interface';
############################################################

$in = <<END;
network:u = { ip = 10.9.9.0/24; }

router:g = {
 managed;
 model = IOS, FW;
 interface:u = {ip = 10.9.9.1; hardware = F0;}
 interface:a = {ip = 10.1.1.9; hardware = F1;}
}

network:a = { ip = 10.1.1.0/24;}

router:r1 = {
 managed;
 model = IOS, FW;
 interface:a = {ip = 10.1.1.1; hardware = E1;}
 interface:b = {ip = 10.2.2.1; virtual = {ip = 10.2.2.9;} hardware = E2;}
}

router:r2 = {
 managed;
 model = IOS, FW;
 interface:a = {ip = 10.1.1.2; hardware = E4;}
 interface:b = {ip = 10.2.2.2; virtual = {ip = 10.2.2.9;} hardware = E5;}
}

network:b  = { ip = 10.2.2.0/24; }

pathrestriction:p = interface:r1.a, interface:r1.b.virtual;

service:test = {
 user = network:u;
 permit src = user; dst = network:b; prt = ip;
}
END

$out1 = <<END;
ip route 10.2.2.0 255.255.255.0 10.1.1.2
END

$out2 = <<END;
ip access-list extended E1_in
 deny ip any any
END

$out3 = <<END;
ip access-list extended E4_in
 deny ip any host 10.2.2.9
 deny ip any host 10.2.2.2
 permit ip 10.9.9.0 0.0.0.255 10.2.2.0 0.0.0.255
 deny ip any any
END

$head1 = (split /\n/, $out1)[0];
$head2 = (split /\n/, $out2)[0];
$head3 = (split /\n/, $out3)[0];

eq_or_diff(get_block(compile($in), $head1, $head2, $head3), $out1.$out2.$out3, $title);

############################################################
$title = 'No extra pathrestriction with 3 virtual interfaces';
############################################################

$in = <<END;
network:a = { ip = 10.1.1.0/24;}

router:r1 = {
 managed;
 model = IOS, FW;
 interface:a = {ip = 10.1.1.1; hardware = E1;}
 interface:b = {ip = 10.2.2.1; virtual = {ip = 10.2.2.9;} hardware = E2;}
}

router:r2 = {
 managed;
 model = IOS, FW;
 interface:a = {ip = 10.1.1.2; hardware = E4;}
 interface:b = {ip = 10.2.2.2; virtual = {ip = 10.2.2.9;} hardware = E5;}
}

router:r3 = {
 managed;
 model = IOS, FW;
 interface:a = {ip = 10.1.1.3; hardware = E6;}
 interface:b = {ip = 10.2.2.3; virtual = {ip = 10.2.2.9;} hardware = E7;}
}

network:b  = { ip = 10.2.2.0/24; }

pathrestriction:p = interface:r1.a, interface:r1.b.virtual;
END

$out1 = <<END;
Error: Pathrestriction not supported for group of 3 or more virtual interfaces
 interface:r1.b.virtual,interface:r2.b.virtual,interface:r3.b.virtual
END

eq_or_diff(compile_err($in), $out1, $title);

############################################################
$title = 'Follow implicit pathrestriction at unmanaged virtual interface';
############################################################

# Doppelte ACL-Zeile für virtuelle IP vermeiden an
# - Crosslink-Interface zu unmanaged Gerät
# - mit virtueller IP auch an dem unmanged Gerät

$in = <<END;
network:M = { ip = 10.1.0.0/24;}

router:F = {
 managed;
 model = ASA;
 interface:M = {ip = 10.1.0.1; hardware = inside;}
 interface:A = {ip = 10.2.1.129; hardware = o1; routing = manual;}
 interface:B = {ip = 10.2.1.18; hardware = o2; routing = manual;}
}

network:A = {ip = 10.2.1.128/30;}

router:Z = {
 interface:A = {ip = 10.2.1.130;}
 interface:c = {ip = 10.2.6.166;}
 interface:K = {ip = 10.9.32.3; virtual = {ip = 10.9.32.1;}}
}

network:B = {ip = 10.2.1.16/30;} 

router:L = {
 managed;
 model = IOS;
 interface:B = {ip = 10.2.1.17; hardware = Ethernet1; no_in_acl; routing = manual;}
 interface:c  = {ip = 10.2.6.165; hardware = Ethernet2;}
 interface:K = {ip = 10.9.32.2; virtual = {ip = 10.9.32.1;} 
                hardware = Ethernet0;}
}

network:c  = {ip = 10.2.6.164/30;}
network:K = { ip = 10.9.32.0/21;}

pathrestriction:4 = interface:Z.A, interface:L.B;

service:x = {
 user = interface:L.K.virtual, interface:Z.K.virtual;
 permit src = network:M; dst = user; prt = icmp 17;
}
END

$out1 = <<END;
ip access-list extended Ethernet2_in
 permit icmp 10.1.0.0 0.0.0.255 host 10.9.32.1 17
 deny ip any any
END

$head1 = (split /\n/, $out1)[0];

eq_or_diff(get_block(compile($in), $head1), $out1, $title);

############################################################
done_testing;
