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

	# Calculate how many connections we would like to start for
	# this server
	my $sconn = $req - $conn;       # one connection per request
	$sconn = 0 if $sconn < 0;
	$sconn = $max_conn if $max_conn && $sconn > $max_conn;
	print "SCHED $netloc $req $conn $iconn ($max_conn) $sconn\n"
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
	$server->stop_idle;
	$gconn -= $no;
    }

    # Start servers until we reach limit.  The problem with this
    # approach is that some servers can starve (XXX).
  START_UP:
    for (@start) {
	my($no, $server) = @$_;
	for (1..$no) {
	    $server->create_connection;
	    last START_UP if ++$gconn >= $conn_limit;
	}
    }
}

1;
