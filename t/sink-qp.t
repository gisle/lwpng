use strict;
eval {
    require LWP::Sink::qp;
};
if ($@) {
    print "1..0\n" if $@ =~ /^Can\'t locate MIME/;  # ::QuotedPrint...
    print $@;
    exit;
}

open(STDERR, ">&STDOUT") || die "Can't dup stdout";

$| = 1;
print "1..1\n";

use LWP::Sink::Buffer;
use LWP::Sink::Monitor;

print "chr(0)..chr(255) --> encode --> decode\n";
my $sink = LWP::Sink::qp::encode->new;
$sink->push(LWP::Sink::Monitor->new);
$sink->push(LWP::Sink::qp::decode->new);
my $b;
$sink->push($b = LWP::Sink::Buffer->new);

for (1..10) {
    for (0..255) {
	$sink->put(chr $_);
    }
}

$sink->close;

print "not " unless $b->buffer eq join("", map chr $_, 0..255) x 10;
print "ok 1\n";
