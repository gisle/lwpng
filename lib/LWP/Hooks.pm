package LWP::Hooks;
use strict;

sub add_hook
{
    my $self = shift;
    my $type = shift;
    push(@{$self->{"${type}_hooks"}}, @_);
    $self;
}

sub remove_hook
{
    my $self = shift;
    my $type = shift;
    my @hooks = @{$self->{"${type}_hooks"}};
    for my $rem (@_) {
	@hooks = grep $_ ne $rem, @hooks;
    }
    @{$self->{"${type}_hooks"}} = @hooks;
    $self;
}

sub clear_hooks
{
    my $self = shift;
    for (@_) {
	delete $self->{"$_\_hooks"};
    }
    $self;
}


sub run_hooks
{
    my $self = shift;
    my $type = shift;
    for my $hook (@{$self->{"${type}_hooks"}}) {
	&$hook($self, @_);
    }
    $self;
}

sub run_hooks_until_failure  # and
{
    my $self = shift;
    my $type = shift;
    my $res = 1;
    for my $hook (@{$self->{"${type}_hooks"}}) {
	$res = &$hook($self, @_);
	last unless $res;
    }
    $res;
}

sub run_hooks_until_success  # or
{
    my $self = shift;
    my $type = shift;
    my $res;
    for my $hook (@{$self->{"${type}_hooks"}}) {
	$res = &$hook($self, @_);
	last if $res;
    }
    $res;
}

1;
