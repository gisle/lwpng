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
    *$sock->{'lwp_type'} = "";
    *$sock->{'lwp_rbuf'} = "";
    *$sock->{'lwp_rlim'} = delete $cnf{ReqLimit} || 4;

    if (%cnf && $^W) {
	for (keys %cnf) {
	    warn "Unknown LWP::Conn::FTP->new attribute '$_' ignored\n";
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


sub error
{
    my($self, $msg) = @_;
    $self->_error("$msg: " . $self->message);
}

sub _error
{
    my($self, $msg) = @_;
    $msg .= "\n" unless substr($msg,-1,1) eq "\n";
    print STDERR "ERROR: $msg";
    mainloop->forget($self);
    $self->close;
    if (my $data = delete *$self->{'lwp_data'}) {
	$data->close;
    }
    *$self->{'lwp_mgr'}->connection_closed($self);
}

sub readable
{
    my $self = shift;
    my $buf = \ *$self->{'lwp_rbuf'};
    my $n = sysread($self, $$buf, 2048, length($$buf));
    if (!defined($n)) {
	$self->_error("Bad read: $!");
    } elsif ($n == 0) {
	$self->_error("EOF");
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
	if ($line =~ /^(\d\d\d)([\-\s])/) {
	    $more = $2 eq "-";
	    if ($code) {
                $more++ if $code ne $1;
	    } else {
		$code = $1;
	    }
	} elsif (!$code) {
	    push(@res, $line);
	    return $self->reponse_error(join("\n", @res));
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

sub response_error
{
    my($self, $bad_response) = @_;
    print STDERR "FTP: Bad server response '$bad_response' ignored\n";
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

sub login_info
{
    my($self, $req) = @_;
    my $url = $req->url;
    my($user,$pass) = $req->authorization_basic;
    $user ||= $url->user || "anonymous";
    $pass ||= $url->password || "nobody@";
    my $acct = $req->header("Account") || "home";
    ($user, $pass, $acct);
}

sub gen_response
{
    my($self, $code, $mess, $more) = @_;
    my $req = delete *$self->{'lwp_req'};
    if (ref($more)) {
	$more->{Server} = *$self->{'lwp_server_product'};
    }
    $req->gen_response($code, $mess, $more);
    $self->activate;
}


package LWP::Conn::FTP::Start;
use base 'LWP::Conn::FTP';

sub response
{
    my($self, $r) = @_;
    $self->error("Bad welcome") unless $r eq "2";
    my $mess = $self->message;
    *$self->{'lwp_greeting'} = $mess;
    # Try to make it into a HTTP product token
    $mess =~ s/^\d+\s+//;
    $mess =~ s/^[\w\.]+\s+//;  # host name
    $mess =~ s/\s+ready\.?\s+$//;
    $mess =~ s/\s+\(Version\s+/\// && $mess =~ s/\)//;
    *$self->{'lwp_server_product'} = $mess;
    $self->send_cmd("SYST" => "Syst");
}


package LWP::Conn::FTP::Syst;
use base 'LWP::Conn::FTP';

sub response
{
    my($self, $r) = @_;
    if ($r eq "2") {
	chomp(my $mess = $self->message);
	*$self->{'lwp_syst'} = $mess;
	$mess =~ s/^\d+\s+//;
	*$self->{'lwp_unix'}++ if $mess =~ /\bUNIX\b/i;
	*$self->{'lwp_server_product'} .= " ($mess)";
    }
    $self->state("Ready");
    $self->activate;
}


package LWP::Conn::FTP::Ready;
use base 'LWP::Conn::FTP';

sub activate
{
    my $self = shift;
    my $req = *$self->{'lwp_mgr'}->get_request;
    unless ($req) {
	*$self->{'lwp_mgr'}->connection_idle($self);
	return;
    }
    *$self->{'lwp_req'} = $req;
    (*$self->{'lwp_user'}, *$self->{'lwp_pass'}, *$self->{'lwp_acct'})
	= $self->login_info($req);
    $self->send_cmd("USER " . *$self->{'lwp_user'} => "User");
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
	$self->login_complete;
    } else {
	$self->cant_login;
    }
}

sub login_complete
{
    my $self = shift;
    $self->state("Inlogged");
    $self->activate;
}

sub cant_login
{
    my $self = shift;
    my $mess = $self->message;
    $mess =~ s/^\d+\s+//;
    chomp($mess);
    $self->state("Ready");
    $self->gen_response(401, $mess,
			{"WWW-Authenticate" => 'Basic realm="FTP"',
			});
    $self->activate;
}


package LWP::Conn::FTP::Pass;
use base 'LWP::Conn::FTP::User';
sub response
{
    my($self, $r) = @_;
    if ($r eq "3") {
	my $acct = *$self->{'lwp_acct'};
	$self->send_cmd("ACCT $acct" => "Acct");
    } elsif ($r eq "2") {
	$self->login_complete;
    } else {
	$self->cant_login;
    }
}


package LWP::Conn::FTP::Acct;
use base 'LWP::Conn::FTP::User';
sub response
{
    my($self, $r) = @_;
    if ($r eq "2") {
	$self->login_complete;
    } else {
	$self->cant_login;
    }
}


package LWP::Conn::Rein;
use base 'LWP::Conn::FTP';

sub response
{
    my($self, $r) = @_;
    if ($r eq "2") {
	$self->send_cmd("USER " . *$self->{'lwp_user'} => "User");
    } else {
	$self->error("Can't reinitialize");
    }
}


package LWP::Conn::FTP::Type;
use base 'LWP::Conn::FTP';

sub response
{
    my($self, $r) = @_;
    if ($r eq "2") {
	$self->state("Inlogged");
	$self->activate;
    } else {
	$self->error("Can't set TYPE");
    }
}


package LWP::Conn::FTP::Inlogged;
use base 'LWP::Conn::FTP';
use LWP::MainLoop qw(mainloop);


sub type
{
    my($self, $type) = @_;
    unless (*$self->{'lwp_type'} eq $type) {
	*$self->{'lwp_type'} = $type;
	$self->send_cmd("TYPE $type" => "Type");
    }
}

sub activate
{
    my $self = shift;
    $self->type("I");  # we always use binary transfer mode

    my $req = *$self->{'lwp_req'};
    unless ($req) {
	$req = *$self->{'lwp_mgr'}->get_request;
	unless ($req) {
	    *$self->{'lwp_mgr'}->connection_idle($self);
	    return;
	}
	*$self->{'lwp_req'} = $req;
	my($user, $pass, $acct) = $self->login_info($req);
	if ($user ne *$self->{'lwp_user'}) {
	    (*$self->{'lwp_user'}, *$self->{'lwp_pass'}, *$self->{'lwp_acct'})
		= ($user, $pass, $acct);
	    $self->send_cmd("REIN" => "Rein");
	    return;
	}
    }

    # We now have a request to perform and is logged in as the correct
    # user.
    my $method = uc($req->method);
    if ($method =~ /^(GET|HEAD|PUT)$/) {
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
    } elsif ($method eq "DELETE") {
	$self->gen_response(501, "Delete not implemented yet");
    } elsif ($method eq "RENAME") {
	$self->gen_response(501, "Delete not implemented yet");
    } elsif ($method eq "TRACE") {
	$self->gen_response(501, "Trace not implemented yet");
    } else {
	$self->gen_response(501, "Method not implemented");
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
	my $req = delete *$self->{'lwp_req'};
	$req->gen_response(200);
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
	$self->send_cmd("RETR $file" => "Retr");
    } else {
	$self->_error("PORT failed");
    }
}

package LWP::Conn::FTP::Retr;
use base 'LWP::Conn::FTP::Inlogged';

sub response
{
    my($self, $r, $code) = @_;
    if ($r eq "1") {
	# info message, ignore
    } elsif ($r eq "2") {
	# we are done.  XXX: Must sync with data_done callback
	$self->state("Inlogged");
	$self->data_done($self->message);
    } elsif ($code eq "550") {
	$self->state("Inlogged");
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
	$self->state("Inlogged");
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

