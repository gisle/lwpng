package LWP::Authen::basic;
use strict;

require MIME::Base64;

sub authenticate
{
    my($class, $req, $res, $proxy, $auth_param) = @_;

    my($user, $pass);
    ($user, $pass) = $req->login($auth_param->{realm},
				 $req->url, $proxy);
    unless (defined $user and defined $pass) {
	$res->push_header("Client-Warning", "No username or password given");
	return "ABORT";
    }
    return $class->new($user, $pass);
}

sub new
{
    my $class = shift;
    my $auth;
    my $self = bless \$auth, $class;
    $self->login(@_) if @_;
    $self;
}

sub set_authorization
{
    my($self, $req) = @_;
    return unless defined($$self);
    $req->header("Authorization" => $$self);
}

sub set_proxy_authorization
{
    my($self, $req) = @_;
    return unless defined($$self);
    $req->header("Proxy-Authorization" => $$self);
}

sub login
{
    my $self = shift;
    my $old = $$self;
    if (@_) {
	my $user = shift;
	unless (defined $user) {
	    $$self = undef;
	} else {
	    die "Username can't contain ':'" if $user =~ /:/;
	    my $pass = shift;
	    $pass = "" unless defined $pass;
	    $$self = "Basic " . MIME::Base64::encode("$user:$pass", "");
	}
    }
    return unless defined $old;
    $old =~ s/^Basic\s+//;
    split(/:/, MIME::Base64::decode($old), 2);
}

1;
