use strict;

eval {
    require LWP::Sink::deflate;
};
if ($@) {
    print "1..0\n" if $@ =~ /^Can\'t locate Compress/;
    print $@;
    exit;
}

$| = 1;
print "1..4\n";

use LWP::Sink::Buffer;

print "chr(0)..chr(255) --> deflate --> inflate\n";
my $sink = LWP::Sink::deflate::encode->new;
$sink->push(LWP::Sink::deflate::decode->new);
my $b;
$sink->push($b = LWP::Sink::Buffer->new);

for (0..255) {
    $sink->put(chr $_);
}

$sink->close;

print "not " unless $b->buffer eq join("", map chr $_, 0..255);
print "ok 1\n";

#------------------------
my $orig = <<"EOT" x 1000;
Lille Sonja var en stjerne
der hun danset rundt på tjernet,
skjønt det var kun en som klappa
det var Sonjas store Pappa.

EOT

print "Deflating\n";
print "orig size = ", length($orig), "\n";

$sink = LWP::Sink::deflate::encode->new;
$sink->push($b = LWP::Sink::Buffer->new);

my $copy = $orig;
while (length $copy) {
    my $chunk = substr($copy, 0, 20);
    substr($copy, 0, 20) = '';
    $sink->put($chunk);
}
$sink->close;

my $compressed = $b->buffer;
print "compressed size = ", length($compressed), "\n";

# The compressed stuff should be much shorter
print "not " unless length($compressed)*100 < length($orig);
print "ok 2\n";

print "Inflating, feeding one char at a time\n";

$sink = LWP::Sink::deflate::decode->new;
$sink->push($b = LWP::Sink::Buffer->new);

for (unpack("C*", $compressed)) {
    $sink->put(chr $_);
}
undef($sink);

print "not " unless $b->buffer eq $orig;
print "ok 3\n";


print "Inflating, one chunk\n";
$sink = LWP::Sink::deflate::decode->new;
$sink->push($b = LWP::Sink::Buffer->new);
$sink->put($compressed);
$sink->close;

print "not " unless $b->buffer eq $orig;
print "ok 4\n";
