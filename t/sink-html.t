
eval { require HTML::Parser; };
if ($@) {
    print "1..0\n";
    print $@;
    exit;
};

$| = 1;
print "1..2\n";

my %count;
{
    package MyParser;
    require HTML::Parser;
    @ISA=qw(HTML::Parser);

    sub start
    {
	my($self, $tag) = @_;
	print "START[$tag]\n";
	$count{$tag}++;
    }

    sub end
    {
	my($self, $tag) = @_;
	print "  END[$tag]\n";
	$count{"/$tag"}++;
    }
}

use LWP::Sink::HTML;

my $sink = LWP::Sink::HTML->new(MyParser->new);

$sink->put("<head><title>LWP</title>");
$sink->put("</");
$sink->put("head");
$sink->put(">\n");

$sink->put("<body><a href='http://www.linpro.no/lwp/'");
$sink->put(">libwww-perl home</a");
$sink->put("> and <a href='http://www.perl.org'>perl home</a></body>\n");

$sink->close;

print "not " unless ref($sink->parser) eq "MyParser";
print "ok 1\n";

#eval {
#    require Data::Dumper;
#    print Data::Dumper::Dumper(\%count);
#};

print "not " unless $count{a} == 2 &&
                    $count{"/a"} == 2 &&
                    keys(%count) == 8;
print "ok 2\n";
