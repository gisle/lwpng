$| = 1;
print "1..2\n";

use LWP::Sink::IO;

open(IO, ">&STDOUT") || die;

$sink = LWP::Sink::IO->new(*IO);

$sink->put("ok 1\n");
$sink->flush;
$sink->close;
undef($sink);

# Try to tie it too
use LWP::Sink::Buffer;
tie *STDOUT, "LWP::Sink::IO" or die;
#use LWP::Sink::Monitor; tied(*STDOUT)->push(LWP::Sink::Monitor->new);
tied(*STDOUT)->push($b = LWP::Sink::Buffer->new);

print "This is";
print " a test\n";

untie(*STDOUT);

print "not " unless ${$b->buffer_ref} eq "This is a test\n";
print "ok 2\n";
