package LWP::EventLoop;

require Exporter;
@ISA=qw(Exporter);

@EXPORT=qw(MainLoop);

use Tk ();

#my $top = new MainWindow;
#$top->withdraw;

$no = 0;

sub readable
{
    my $f = shift;
    Tk->fileevent($f, 'readable', @_);
    $no++;
}

sub cancel_readable
{
    Tk->fileevent($_[0], 'readable', '');
    $no--;
}

sub writable
{
    my $f = shift;
    Tk->fileevent($f, 'writable', @_);
    $no++;
}

sub cancel_writable
{
     Tk->fileevent($_[0], 'writable', '');
     $no--;
}

sub after
{
    my($sec) = shift;
    Tk->after($sec*1000, @_);
}

sub MainLoop
{
    Tk::DoOneEvent(0) until $no == 0;
}

1;
