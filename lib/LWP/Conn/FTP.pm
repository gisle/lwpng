package LWP::Conn::FTP;

# $Id$

# Copyright 1997-1998 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

use IO::Socket ();
use LWP::MainLoop qw(mainloop);
use strict;

use vars qw($DEBUG @ISA);
@ISA=qw(IO::Socket::INET);

sub new
{
    my($class, %cnf) = @_;

    my $mgr = delete $cnf{ManagedBy} ||
      Carp::croak("'ManagedBy' is mandatory");
    my $host =   delete $cnf{Host} || delete $cnf{PeerAddr} ||
      Carp::croak("'Host' is mandatory for FTP");

    my $port;
    $port = $1 if $host =~ s/:(\d+)//;
    $port = delete $cnf{Port} || delete $cnf{PeerPort} || $port || 21;

    my $sock = IO::Socket::INET->new(PeerAddr => $host,
				     PeerPort => $port);
    return unless $sock;
    bless $sock, $class;
    
    *$sock->{'lwp_mgr'}  = $mgr;
    *$sock->{'lwp_user'} = delete $cnf{Username} || "anonymous";
    *$sock->{'lwp_pass'} = delete $cnf{Password} || "ftp@";
    *$sock->{'lwp_type'} = "";
    *$sock->{'lwp_rbuf'} = "";
    *$sock->{'lwp_rlim'} = delete $cnf{ReqLimit} || 4;

    if (%cnf && $^W) {
	for (keys %cnf) {
	    warn "Unknown LWP::Conn::HTTP->new attribute '$_' ignored\n";
	}
    }

    $sock->state("Start");
    mainloop->readable($sock);
    mainloop->timeout($sock, 4);
    $sock;
}

sub state
{
    my($self, $state) = @_;
    my $class = "LWP::Conn::FTP::$state";
    bless $self, $class;
}

sub inactive
{
    my $self = shift;
    $self->_error("Timeout");
}


sub server_closed_connection
{
    my $self = shift;
    $self->_error("EOF");
}

sub _error
{
    my($self, $msg) = @_;
    print STDERR "ERROR: $msg: " . $self->message;
    mainloop->forget($self);
    $self->close;
    if (my $data = *$self->{'lwp_data'}) {
	$data->close;
    }
    *$self->{'lwp_mgr'}->connection_closed($self);
}

sub readable
{
    my $self = shift;
    my $buf = \ *$self->{'lwp_rbuf'};
    my $n = sysread($self, $$buf, 512, length($$buf));
    if (!defined($n)) {
	$self->_error("Bad read: $!");
    } elsif ($n == 0) {
	$self->server_closed_connection;
    } else {
	$self->check_rbuf;
    }
}

sub check_rbuf
{
    my $self = shift;
    my $buf = \ *$self->{'lwp_rbuf'};
    if (length $$buf) {
	my @lines = split(/\015?\012/, $$buf);
	if (substr($$buf, -1, 1) ne "\012") {
	    # the last line was not complete
	    *$self->{'lwp_rbuf'} = pop @lines;
	} else {
	    *$self->{'lwp_rbuf'} = "";
	}
	push(@{*$self->{'lwp_lines'}}, @lines);
    }
    $self->parse_response;
}

sub parse_response
{
    my $self = shift;
    my($code, $more, @res);
    while (@{*$self->{'lwp_lines'}}) {
	my $line = shift @{*$self->{'lwp_lines'}};
	if ($line =~ /^(\d\d\d)(-?)/) {
	    $more = $2;
	    if ($code) {
		if ($code ne $1) {
		    push(@res, $line);
		    return $self->reponse_error(\@res);
		}
	    } else {
		$code = $1;
	    }
	} elsif (!$code) {
	    push(@res, $line);
	    return $self->reponse_error(\@res);
	}
	push(@res, $line);
    }
    if ($more) {
	unshift(@{*$self->{'lwp_lines'}}, @res);
    } elsif ($code) {
	*$self->{'lwp_response_code'} = $code;
	*$self->{'lwp_response_mess'} = \@res;
	print STDERR "====>\t", join("\n\t", @res), "\n" if $DEBUG;
	$self->response(substr($code, 0, 1), $code, \@res);
    }
}

sub code
{
    my $self = shift;
    *$self->{'lwp_response_code'} || "000";
}

sub message
{
    my $self = shift;
    wantarray ? @{*$self->{'lwp_response_mess'}}
              : join("\n", @{*$self->{'lwp_response_mess'}}, "");
}

sub response
{
    my($self, $r, $code, $mess) = @_;
    print STDERR "Response $code ignored\n";
}

sub send_cmd
{
    my($self, $cmd, $next_state) = @_;
    if ($DEBUG) {
	my $out = $cmd;
	$out =~ s/^(PASS\s+)(.+)/$1 . "*" x length($2)/e;
	print STDERR "$out\n";
    }
    $cmd .= "\015\012";
    # XXX should really wait for the socket to become writable, but
    # it is very unlikely that it should not be that.
    $self->print($cmd);
    $self->state($next_state) if $next_state;
}

sub activate
{
}

package LWP::Conn::FTP::Start;
use base 'LWP::Conn::FTP';

sub response
{
    my($self, $r) = @_;
    $self->_error("Missing grating") unless $r eq "2";
    *$self->{'lwp_greating'} = $self->message;
    $self->send_cmd("SYST" => "Syst");
}

package LWP::Conn::FTP::Syst;
use base 'LWP::Conn::FTP';

sub response
{
    my($self, $r) = @_;
    if ($r eq "2" && $self->message =~ /UNIX/) {
	print STDERR "Hurray! It is a Unix system\n";
	*$self->{'lwp_unix'}++;
    }
    my $user = *$self->{'lwp_user'};
    $self->send_cmd("USER $user" => "User");
}

package LWP::Conn::FTP::User;
use base 'LWP::Conn::FTP';

sub response
{
    my($self, $r) = @_;
    if ($r eq "3") {
	my $pass = *$self->{'lwp_pass'};
	$self->send_cmd("PASS $pass" => "Pass");
    } elsif ($r eq "2") {
	$self->state("Ready");
	$self->activate;
    } else {
	$self->_error("Can't login");
    }
}

package LWP::Conn::FTP::Pass;
use base 'LWP::Conn::FTP';
sub response
{
    my($self, $r) = @_;
    if ($r eq "2") {
	$self->state("Ready");
	$self->activate;
    } else {
	$self->_error("Can't send password");
    }
}


package LWP::Conn::FTP::Type;
use base 'LWP::Conn::FTP';

sub response
{
    my($self, $r) = @_;
    if ($r eq "2") {
	$self->state("Ready");
	$self->activate;
    } else {
	$self->_error("Can't change type");
    }
}


package LWP::Conn::FTP::Ready;
use base 'LWP::Conn::FTP';
use LWP::MainLoop qw(mainloop);

sub activate
{
    my $self = shift;

    unless (*$self->{'lwp_type'} eq "I") {
	*$self->{'lwp_type'} = "I";
	$self->send_cmd("TYPE I" => "Type");
	return;
    }

    my $req = *$self->{'lwp_mgr'}->get_request;
    return unless $req;

    *$self->{'lwp_file'} = $req->url->path;

    my @cwd = qw();
    if (@cwd) {
	@{*$self->{'lwp_cwd'}} = @cwd;
	$self->state("Cwd");
	$self->cwd;
	return;
    } else {
	$self->cwd_done;
    }
}

sub cwd_done
{
    # now we want to actually try to fetch the file
    # we could start by running SIZE, MDTM and such to get header
    # information and also to check if the file is there.
    my $self = shift;
    my $data = IO::Socket::INET->new(Listen => 1,
				     LocalAddr => $self->sockhost,
                                    );
    *$self->{'lwp_done'} = 0;
    if ($data) {
	my $port = $data->sockport;
	$port = ($port >> 8) . "," . ($port & 0xFF);
	$port = join(",", split(/\./, $data->sockhost)) . ",$port";
	$self->send_cmd("PORT $port" => "Port");
	bless $data, "LWP::Conn::FTP::Data::Listen";  # whow!!
	mainloop->readable($data);
	*$data->{'lwp_ftp'} = $self;
	*$self->{'lwp_data'} = $data;
    } else {
	$self->_error("Can't create passive data socket");
    }
}

sub data
{
    my($self, $data) = @_;
    print "DATA: $self $data\n";
}

sub data_done
{
    my $self = shift;
    print "DATA DONE\n";
    if (++*$self->{'lwp_done'} == 2) {
	print "The second one...\n";
	$self->activate;
    }
}

package LWP::Conn::FTP::Port;
use base 'LWP::Conn::FTP';

sub response
{
    my($self, $r) = @_;
    if ($r eq "2") {
	my $file = *$self->{'lwp_file'};
	$self->send_cmd("RETR $file" => "RETR");
    } else {
	$self->_error("PORT failed");
    }
}

package LWP::Conn::FTP::RETR;
use base 'LWP::Conn::FTP::Ready';

sub response
{
    my($self, $r, $code) = @_;
    if ($r eq "1") {
	# info message, ignore
    } elsif ($r eq "2") {
	# we are done.  XXX: Must sync with data_done callback
	$self->state("Ready");
	$self->data_done($self->message);
    } elsif ($code eq "550") {
	$self->state("Ready");
	delete(*$self->{'lwp_data'})->close;
	$self->activate;
    } else {
	$self->_error("RETR");
    }
}

package LWP::Conn::FTP::Cwd;
use base 'LWP::Conn::FTP';

sub cwd
{
    my $self = shift;
    my $dir = shift @{*$self->{'lwp_cwd'}};
    if ($dir) {
	if ($dir eq "..") {
	    $self->send_cmd("CDUP");
	} else {
	    $self->send_cmd("CWD $dir");
	}
    } else {
	$self->state("Ready");
	$self->cwd_done;
    }
}

sub response
{
    my($self, $r) = @_;
    if ($r eq "2") {
	$self->cwd;
    } else {
	$self->_error("Can't CWD");
    }
}


package LWP::Conn::FTP::Data::Listen;
use base 'IO::Socket::INET';

use LWP::MainLoop qw(mainloop);

sub readable
{
    my $self = shift;
    if (my $data = $self->accept) {
	mainloop->readable($data);
	bless $data, "LWP::Conn::FTP::Data";
	my $ftp = *$self->{'lwp_ftp'};
	*$data->{'lwp_ftp'} = $ftp;
	*$ftp->{'lwp_data'} = $data;
    } else {
	*$self->{'lwp_ftp'}->_error("Can't accept");
    }
    mainloop->forget($self);
    $self->close;
}

sub close
{
    my $self = shift;
    mainloop->forget($self);
    $self->SUPER::close;
}

package LWP::Conn::FTP::Data;
use base 'LWP::Conn::FTP::Data::Listen';

sub readable
{
    my $self = shift;
    my $buf = "";
    my $n = sysread($self, $buf, 2048);
    if ($n) {
	*$self->{'lwp_ftp'}->data($buf);
    } else {
	if (defined $n) {
	    *$self->{'lwp_ftp'}->data_done();
	} else {
	    *$self->{'lwp_ftp'}->_error("Data connection error: $!");
	}
	$self->close;
    }
}

1;

