package LWP::Authen::digest;
use strict;

# Based on <draft-ietf-http-authentication-01>

require MD5;

sub authenticate
{
    my($class, $req, $res, $proxy, $auth_param) = @_;

    return if $auth_param->{algorithm} &&
	      $auth_param->{algorithm} !~ /^MD5(-sess)?$/;

    if ($auth_param->{stale} && uc($auth_param->{stale}) eq "TRUE") {
	# XXX need a reference to the current $auth object so that
	# we can update it with the new nonce and don't have to
	# ask the user for a username/password again.
	$res->push_header("Client-Warning",
			  "Stale nonce, should use '$auth_param->{nonce}'");
    }

    my($user, $pass);
    ($user, $pass) = $req->login($auth_param->{realm},
				 $req->url, $proxy);

    unless (defined $user and defined $pass) {
	$res->push_header("Client-Warning", "No username or password given");
	return "ABORT";
    }

    return $class->new(%$auth_param,
		       username => $user,
                       password => $pass,
		      );
}

sub new
{
    my $class = shift;
    my $self = bless { @_ }, $class;
    $self;
}

sub _set_authorization
{
    my($self, $header, $req) = @_;
    my $user = $self->{username};
    return unless defined $user;
    my $pass = $self->{password};

    my $realm = $self->{realm};
    $realm = "" unless defined $realm;

    my $algorithm = lc($self->{algorithm} || "md5");
    my %qops = map {$_ => 1} split(/\s*,\s*/, lc($self->{qop} || ""));
    my $qop = "";
    if ($req->has_content && $qops{'auth-int'}) {
	$qop = "auth-int";
    } elsif ($qops{auth}) {
	$qop = "auth";
    }
    
    my $uri = $req->url->full_path;
    my $nonce = $self->{nonce};  $nonce = "" unless defined $nonce;
    my $nc = sprintf "%08x", ++$self->{nonce_count};
    my $cnonce = sprintf "%x", rand(0xFFFFFF)+1;  # +1 ensures always TRUE

    my $a1;
    if ($algorithm eq "md5") {
	# A1 = unq(username-value) ":" unq(realm-value) ":" passwd
	$a1 = MD5->hexhash("$user:$realm:$pass");
    } elsif ($algorithm eq "md5-sess") {
	# The following A1 value should only be computed once
	$a1 = $self->{'A1'};
	unless ($a1) {
	    # A1 = H( unq(username-value) ":" unq(realm-value) ":" passwd )
	    #         ":" unq(nonce-value) ":" unq(cnonce-value)
	    $a1 = MD5->hexhash("$user:$realm:$pass") . ":$nonce:$cnonce";
	    $a1 = MD5->hexhash($a1);
	    $self->{'A1'} = $a1;
	}
    } else {
	return;
    }

    my $a2 = $req->method . ":" . $uri;
    $a2 .= MD5->hexhash($req->content) if $qop eq "auth-int";
    $a2 = MD5->hexhash($a2);

    # at this point $a1 is really H(A1) and $a2 is H(A2)

    my $response;
    if ($qop eq "auth" || $qop eq "auth-int") {
	#  KD(H(A1), unq(nonce-value)
	#            :" nc-value
	#            ":" unq(cnonce-value)
	#            ":" unq(qop-value)
	#            ":" H(A2)
	#    )
	$response = MD5->hexhash("$a1:$nonce:$nc:$cnonce:$qop:$a2");
    } else {
	# compatibility with RFC 2069
	# KD ( H(A1), unq(nonce-value) ":" H(A2) )
	$response = MD5->hexhash("$a1:$nonce:$a2");
	undef($cnonce);
    }

    my @h;
    push(@h, ["username" => $user],
	     ["realm"    => $realm],
	     ["nonce"    => $nonce],
	     ["uri"      => $uri],
             ["response" => $response]);
    push(@h, ["_algorithm" => $self->{algorithm}]) if $self->{algorithm};
    push(@h, ["cnonce"   => $cnonce]) if $cnonce;
    push(@h, ["opaque"   => $self->{opaque}]) if exists $self->{opaque};
    
    if ($self->{qop}) {
	push(@h, ["_qop" => $qop]);
	push(@h, ["_nc"  => $nc]);
    }

    my $h = "Digest " . join(", ",
			     map {
				 my($k,$v) = @$_;
				 unless ($k =~ s/^_//) {
				     $v =~ s/([\\\"])/\\$1/g;
				     $v = qq("$v");
				 }
				 "$k=$v";
                             } @h);
    
    $req->header($header => $h);
}

sub set_authorization
{
    shift->_set_authorization("Authorization", @_);
}

sub set_proxy_authorization
{
    shift->_set_authorization("Proxy-Authorization", @_);
}

sub login
{
    my $self = shift;
    my @old = ($self->{username}, $self->{password});
    if (@_) {
	my $user = shift;
	unless (defined $user) {
	    delete $self->{username};
	    delete $self->{password};
	} else {
	    $self->{username} = $user;
	    my $pass = shift;
	    $pass = "" unless defined $pass;
	    $self->{password} = $pass;
	}
    }
    wantarray ? @old : \@old;
}

sub nonce
{
    my $self = shift;
    my $old = $self->{'nonce'};
    if (@_) {
	$self->{'nonce'} = shift;
	delete $self->{'nonce_count'};
    }
    $old;
}

package HTTP::Message;

sub has_content
{
    my $self = shift;
    return 0 unless defined($self->{_content});
    return undef if ref($self->{_content});
    return length $self->{_content};
}

1;
