#!/local/bin/perl 

# This is a simple command line UA that can run several requests
# in parallell.  The commands are:
#
#     get <url>      : spool request
#     s              : stop all requests
#     s <url>        : stop requests for this server
#     p              : print state of UA
#     c <url>        : set up connection to this host
#     cp <key> <val> : set connection parameters
#     q              : quit
#
#     de             : toggle event loop debugging
#     dc             : toggle connection debugging
#


use LWP::UA;
$ua = LWP::UA->new;

$ua->conn_param(ReqLimit    => 3,
                ReqPending  => 1,
		Timeout     => 30,
		IdleTimeout => 10);

require LWP::Request;
require LWP::Conn::HTTP;

use LWP::MainLoop qw(empty one_event readable);

readable(\*STDIN, \&cmd);

while (!empty) {
    one_event();
}
exit;

sub cmd
{
    my $cmd;
    my $n = sysread(STDIN, $cmd, 512);
    chomp($cmd);
    eval {
	if ($cmd eq "q") {
	    exit;
	} elsif ($cmd eq "p") {
	    print $ua->as_string;
	} elsif ($cmd eq "dc") {
	    $LWP::Conn::HTTP::DEBUG = !$LWP::Conn::HTTP::DEBUG;
	    print "Connection debug is ",
	          ($LWP::Conn::HTTP::DEBUG ? "on" : "off"), "\n";
	} elsif ($cmd eq "de") {
	    $LWP::EventLoop::DEBUG = !$LWP::EventLoop::DEBUG;
	    print "Eventlopp debug is ",
	          ($LWP::EventLoop::DEBUG ? "on" : "off"), "\n";
	} elsif ($cmd =~ /^(get|GET)\s+(\S+)/) {
	    $ua->spool(LWP::Request->new(GET => $2));
	} elsif ($cmd =~ /^c\s+(\S+)/) {
	    $ua->server($1)->create_connection;
	} elsif ($cmd =~ /^cp\s+(.*)/) {
	    $ua->conn_param(split(' ', $1));
	} elsif ($cmd eq "s") {
	    $ua->stop;
	} elsif ($cmd =~ /^s\s+(\S+)/) {
	    $ua->server($1)->stop;
	} else {
	    print "Unknown command '$cmd'\n";
	}
    };
    print STDERR $@ if $@;
}
