#!/usr/bin/perl

# A server that binds to some port and then prints everything
# received on STDOUT and forwards STDIN to the net.

use LWP::MainLoop qw(readable forget_all run);
use IO::Socket;

$| = 1;

$listen = IO::Socket::INET->new(Listen => 5) || die "Can't bind: $!";

my $port = $listen->sockport;
while (1) {
    print "--- accept connection on port $port ---\n";
    my $conn = $listen->accept;
    next unless $conn;

    readable(\*STDIN,
	     sub {
		 my $buf;
		 sysread(STDIN, $buf, 100);
		 $buf =~ s,\\\n$,,;
		 if ($buf eq ".\n") {
		     close($conn);
		     forget_all();
		     return;
		 }
		 $buf =~ s,\n,\015\012,g;
		 $conn->print($buf);
	     });

    readable($conn,
	     sub {
		 my $buf;
		 unless (sysread($conn, $buf, 100)) {
		     close($conn);
		     forget_all;
		     return;
		 };
		 $buf =~ s,\r,<CR>,g;
		 $buf =~ s,\n,<LF>\n,g;
		 $buf =~ s,\t,<TAB>,g;
		 print $buf;
	     });
    run();  # returns when no events are pending, i.e. after forget_all()
}
