print "1..3\n";


$LWP::EventLoop::DEBUG++;
use LWP::MainLoop qw(after forget run);

after(3, sub { print "ok 2\n"; });
after(1, sub { print "ok 1\n"; });
$last = after(7, sub { print "not ok 3\n"; });
forget($last);
run;
print "ok 3\n";
