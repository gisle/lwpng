package LWP::Authen::digest;
use strict;

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
	$res->push_header("Client-Warning", "Stale nonce, should use '$auth_param->{nonce}'");
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
    my @h;
    push(@h, ["username" => $user]);
    my $pass = $self->{password};

    my $realm = $self->{realm};
    $realm = "" unless defined $realm;
    push(@h, ["realm" => $realm]);

    push(@h, ["nonce" => $self->{nonce}]);
    push(@h, ["uri"   => $req->url->full_path]);
    push(@h, ["response" => "AAAA"]); # XXXX
    push(@h, ["_algorithm" => $self->{algorithm}]) if $self->{algorithm};
    #push(@h, ["cnonce" => "CCCC"]);
    push(@h, ["opaque" => $self->{opaque}]) if exists $self->{opaque};
    
    push(@h, ["_qop" => "auth"]); #XXX
    push(@h, ["_nc" => sprintf "%08x", ++$self->{nonce_count}]);

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

1;
