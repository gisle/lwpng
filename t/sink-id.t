print "1..2\n";

use strict;

open(STDERR, ">&STDOUT") || die "Can't dup stdout";

use LWP::Sink::Tee;
use LWP::Sink::Buffer;
use LWP::Sink::Monitor;
use LWP::Sink::identity;
use LWP::Sink::rot13;

my $tee = LWP::Sink::Tee->new;

my $b1 = LWP::Sink::Buffer->new;
my $b2 = LWP::Sink::Buffer->new;

my $f2 = LWP::Sink::rot13->new;
$f2->push(LWP::Sink::Monitor->new("rot13"));
$f2->push($b2);

$tee->append($b1);
$tee->append($f2);

my $sink = LWP::Sink::identity->new(bufsize => 5);
$sink->push(LWP::Sink::Monitor->new("id"));
$sink->push($tee);

# Now we should have a pipeline that looks like this:
#
#                                    +---> buffer (b1)
#                                    |
#  ---> identity ---> mon ---> tee --+
#                                    |
#                                    +---> rot13 ---> mon --> buffer (b2)
#

# Start feeding it data
for (32 .. 126) {
    $sink->put(chr $_);
}

undef($sink);
$b1 = $b1->buffer;
$b2 = $b2->buffer;


my $t1 = q( !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~);
my $t2 = q( !"#$%&'()*+,-./0123456789:;<=>?@NOPQRSTUVWXYZABCDEFGHIJKLM[\]^_`nopqrstuvwxyzabcdefghijklm{|}~);

#print "B1=$b1\nB2=$b2\n";

print "not " if $b1 ne $t1;
print "ok 1\n";

print "not " if $b2 ne $t2;
print "ok 2\n";

