#!/usr/bin/perl

use strict;
use Test::More;
use Test::Differences;
use lib 't';
use Test_Netspoc;

my ($title, $in, $out, $head);

############################################################
$title = 'Check for owners with duplicate alias names';
############################################################

$in = <<END;
owner:xx = {
 alias = X Quadrat;
 admins = a\@b.c;
}

owner:x2 = {
 alias = X Quadrat;
 admins = a\@b.c;
}
END

$out = <<END;
Error: Name conflict between owners
 - owner:xx with alias 'X Quadrat'
 - owner:x2 with alias 'X Quadrat'
Error: Topology seems to be empty
Aborted
END

eq_or_diff(compile_err($in), $out, $title);

############################################################
$title = 'Check for owners with conflicting name and alias name';
############################################################

$in = <<END;
owner:y = {
 alias = z;
 admins = a\@b.c;
}

owner:z = {
 admins = a\@b.c;
}
END

$out = <<END;
Error: Name conflict between owners
 - owner:z
 - owner:y with alias 'z'
Error: Topology seems to be empty
Aborted
END

eq_or_diff(compile_err($in), $out, $title);

############################################################
$title = 'Owner at bridged network';
############################################################

$in = <<END;
owner:xx = {
 admins = a\@b.c;
}

area:all = { owner = xx; anchor = network:VLAN_40_41/40; }

network:VLAN_40_41/40 = { ip = 10.2.1.96/28; }

router:asa = {
 managed;
 model = ASA;

 interface:VLAN_40_41/40 = { hardware = outside; }
 interface:VLAN_40_41/41 = { hardware = inside; }
 interface:VLAN_40_41 = { ip = 10.2.1.99; hardware = device; }
}

network:VLAN_40_41/41 = { ip = 10.2.1.96/28; }

service:test = {
 user = network:VLAN_40_41/40;
 permit src = user; 
        dst = interface:asa.VLAN_40_41; 
        prt = ip;
}
END

$out = '';

eq_or_diff(compile_err($in), $out, $title);

############################################################
done_testing;
