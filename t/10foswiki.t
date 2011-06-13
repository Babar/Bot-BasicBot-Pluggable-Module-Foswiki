use strict;
use warnings;
use Test::More;
use Bot::BasicBot::Pluggable;
use POSIX qw( strftime );

# create a mock bot
my $bot;
{
    $SIG{__WARN__} = sub {
        warn @_
          unless $_[0] =~
m#^Loading Foswiki from Bot/BasicBot/Pluggable/Module/Foswiki.pm at \S+ line \d+\.$#;
    };

    $bot = Bot::BasicBot::Pluggable->new(
        store       => 'Memory',
        nick        => 'bam',
        ignore_nick => 'ignore_me',
    );
}
$bot->load('Foswiki');

my $helptext        = Bot::BasicBot::Pluggable::Module::Foswiki->help();
my $helpadd         = Bot::BasicBot::Pluggable::Module::Foswiki->help('add');
my $wikiItem1234    = 'http://foswiki.org/Tasks/Item1234 - Item1234: MathModePlugin\'s latex2img not executable';
my $irclogs_foswiki = strftime(
'http://irclogs.foswiki.org/bin/irclogger_log/foswiki\?date=%Y-%m-%d,%a&sel=\d+#l\d+',
    gmtime()
);

sub test_said {
    my ( $bot, $msg ) = @_;
    my @reply;
    my %default = (
        who        => 'Babar',
        channel    => '#zlonkbam',
        reply_hook => sub { push @reply, $_[1]; },    # $_[1] is the reply text
    );
    for my $key ( keys %default ) {
        $msg->{$key} = $default{$key} unless exists $msg->{$key};
    }
    $msg->{address} = 'msg' if $msg->{channel} eq 'msg';
    unless ( $msg->{raw_body} ) {
        $msg->{raw_body} =
          exists $msg->{address} && $msg->{address} ne 'msg'
          ? $msg->{address} . ': ' . $msg->{body}
          : $msg->{body};
    }
    $bot->said($msg);
    return unless @reply;
    return join "\n", @reply;
}

# test the told() method
my @tests = (
    [ { 'body' => 'hello bam', } => undef ],
    [
        {
            'body'    => 'welcome here',
            'address' => 'bam',
        } => undef
    ],
    [
        {
            'body'    => 'hi bam',
            'channel' => 'msg',
        } => undef
    ],
    [ { 'body' => 'foswiki bam blonk zlonk', } => undef ],
    [
        {
            'body'    => 'foswiki help',
            'channel' => 'msg',
        } => $helptext
    ],
    [
        {
            'body'    => 'foswiki help add',
            'channel' => 'msg',
        } => $helpadd
    ],
    [
        {
            'body' =>
'foswiki add item Item:?(\d+) http://foswiki.org/Tasks/Item$param1',
            'channel' => 'msg',
        } => 'Added Foswiki pattern item (1 total).',
    ],
    [
        {
            'body'    => 'foswiki add blonk blurp zlonk',
            'channel' => 'msg',
        } => 'Added Foswiki pattern blonk (2 total).',
    ],
    [
        {
            'body'    => 'foswiki list',
            'channel' => 'msg',
        } => 'Currently watching 2 patterns: item, blonk',
    ],
    [
        {
            'body'    => 'foswiki list blonk',
            'channel' => 'msg',
        } => 'Key: blonk, Pattern: blurp, Reply: zlonk',
    ],
    [
        {
            'body'    => 'foswiki delete blonk',
            'channel' => 'msg',
        } => 'Removed Foswiki pattern blonk (1 total).',
    ],
    [
        {
            'body'    => 'foswiki add blonk blonk zlonk',
            'channel' => 'msg',
        } => 'Added Foswiki pattern blonk (2 total).',
    ],
    [
        {
            'body'    => 'foswiki remove blonk',
            'channel' => 'msg',
        } => 'Removed Foswiki pattern blonk (1 total).',
    ],
    [
        {
            'body'    => 'foswiki remove blonk',
            'channel' => 'msg',
        } => 'No such pattern blonk. Not removed.',
    ],
    [
        {
            'body'    => 'blonk Item:1234',
            'channel' => 'msg',
        } => $wikiItem1234,
    ],
    [
        {
            'body'    => 'blonk Item:1234',
            'channel' => 'msg',
        } => $wikiItem1234,
    ],
    [
        {
            'body'    => 'blonk Item:1234 Item1234',
            'channel' => 'msg',
        } => "$wikiItem1234 $wikiItem1234",
    ],

    # Now test logtime
    [
        {
            'body'    => 'logtime',
            'channel' => '#foswiki',
        } => qr/^$irclogs_foswiki \(channel #foswiki\)$/,
    ],
    [
        { 'body' => '!logtime #foswiki', } =>
          qr/^$irclogs_foswiki \(channel #foswiki\)$/,
    ],
    [
        {
            'body'    => 'logtime #foswiki',
            'channel' => 'msg',
        } => qr/^$irclogs_foswiki \(channel #foswiki\)$/,
    ],
);

plan tests => scalar @tests;

for my $t (@tests) {

    if ( ref( $t->[1] ) eq 'Regexp' ) {
        like( test_said( $bot, $t->[0] ),
            $t->[1],
            qq{Answer to "$t->[0]->{raw_body}" on channel $t->[0]->{channel}} );
    }
    else {
        is( test_said( $bot, $t->[0] ),
            $t->[1],
            qq{Answer to "$t->[0]->{raw_body}" on channel $t->[0]->{channel}} );
    }
}
$bot->shutdown();
