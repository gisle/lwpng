#!/usr/bin/perl

# A server that binds to some port and then prints everything
# received on STDOUT and vica versa.

use LWP::MainLoop qw(mainloop);
use IO::Socket;

$listen = IO::Socket::INET->new(Listen => 5) || die;

$| = 1;

my $port = $listen->sockport;
while (1) {
    print "--- accept connection on port $port ---\n";
    my $conn = $listen->accept;
    next unless $conn;

    mainloop->readable(\*STDIN, sub {
			   my $buf;
			   sysread(STDIN, $buf, 100);
			   if ($buf eq ".\n") {
			       close($conn);
			       mainloop->forget_all;
			       return;
			   }
			   $conn->print($buf);
		       });

    mainloop->readable($conn, sub {
			   my $buf;
			   unless (sysread($conn, $buf, 100)) {
			       close($conn);
			       mainloop->forget_all;
			       return;
			   };
			   print $buf;
		       });
    mainloop->run;
}
