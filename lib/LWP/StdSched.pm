package LWP::StdSched;
use strict;
use vars qw($DEBUG);

sub new
{
    my($class, $ua) = @_;
    bless {}, $class;
}

sub reschedule
{
    my($self, $ua) = @_;

    my $gconn = 0;   # number of connections
    my $gsconn = 0;  # number of connections to start

    my @idle;
    my @start;

    while (my($netloc, $server) = each %{$ua->{servers}}) {
	my($req,$conn,$iconn, $max_conn) = $server->c_status;
	if ($req && $conn) {
	    # Let's see if any of the existing connections can
	    # absorb the request queue.
	    print STDERR "$netloc->activate_connections\n" if $DEBUG;
	    $server->activate_connections;
	    ($req,$conn,$iconn, $max_conn) = $server->c_status;
	}

	# Calculate how many connections we would like to start for
	# this server
	my $sconn = $req - $conn;       # one connection per request
	my $max_start = $max_conn - $conn;
	$sconn = $max_start if $max_conn && $sconn > $max_start;
	$sconn = 0 if $sconn < 0;
	print STDERR "SCHED $netloc R=$req C=$conn I=$iconn ($max_conn) S=$sconn\n"
	    if $DEBUG;

	$gconn  += $conn;
	$gsconn += $sconn;

	push(@idle,  [$iconn, $server]) if $iconn && !$sconn;
	push(@start, [$sconn, $server]) if $sconn;
    }

    my $conn_limit = $ua->{'max_conn'};
    unless (!$conn_limit) {
	# There is no global limit to care about, so just start all we have
	for (@start) {
	    my($no, $server) = @$_;
	    for (1..$no) {
		print STDERR $server->id, "->create_connection\n" if $DEBUG;
		$server->create_connection;
	    }
	}
	return;
    }

    # must ensure that we don't exceed global conn_limit
    while (@idle &&
	   $gconn + $gsconn > $conn_limit) {
	# we have reached global limit, but have idle connections that
	# we can kill off first
	my($no, $server) = @{ shift(@idle) };
	print STDERR $server->id, "->stop_idle\n" if $DEBUG;
	$server->stop_idle;
	$gconn -= $no;
    }

    # Start server connections until we reach limit.
    # XXX the problem with this approach is that some servers can starve.
  START_UP:
    for (@start) {
	my($no, $server) = @$_;
	for (1..$no) {
	    print STDERR $server->id, "->create_connection\n" if $DEBUG;
	    $server->create_connection;
	    last START_UP if ++$gconn >= $conn_limit;
	}
    }
}

1;
