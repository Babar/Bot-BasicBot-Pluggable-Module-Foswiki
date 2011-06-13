package Bot::BasicBot::Pluggable::Module::Foswiki;

use strict;
use warnings;
use Bot::BasicBot::Pluggable::Module;
use Regexp::Assemble ();
use LWP::UserAgent   ();
use HTTP::Status     ();
use POSIX qw( strftime );
use URI::Title qw(title);

our @ISA     = qw(Bot::BasicBot::Pluggable::Module);
our $VERSION = '0.01';

my $cmds = qr/add|list|remove|delete|help/;

sub init {
    my $self = shift;
    $self->config(
        {
            user_log_link => 'http://irclogs.foswiki.org/bin/irclogger_log/',
            user_log_date_format => '%Y-%m-%d,%a',
        }
    );
}

sub told {
    my ( $self, $mess ) = @_;
    my $bot = $self->bot();

    # ignore people we ignore
    return if $bot->ignore_nick( $mess->{who} );

    my $body = $mess->{body};
    return if !$body;
    my $pattern = $self->_get_pattern();
    return
      if $body !~ /^\s*foswiki\W+($cmds)\W*(.*)/io
          && $body !~ /^\s*!?(logtime)\W*(.*)/i
          && $body !~ $pattern;

    # grab the parameter list
    my ( $command, @args ) = ( $1 || 'help', split /\s+/, $2 || '' );

    # compute the reply
    my $reply;
    if ( $command =~ /^add$/i ) {
        $reply = $self->_add_pattern(@args);
    }
    elsif ( $command =~ /^(?:remove|delete)$/i ) {
        $reply = $self->_remove_pattern(@args);
    }
    elsif ( $command =~ /^list$/i ) {
        $reply = $self->_list_patterns(@args);
    }
    elsif ( $command =~ /^help$/i ) {
        $reply = $self->help(@args);
    }
    elsif ( $command =~ /^logtime$/i ) {
        my $channel = $args[0] || $mess->{channel};
        $channel = '' if $channel eq 'msg';
        $reply = $self->_logtime($channel);
    }
    else {    # means matched pattern
        $reply = $self->_replace_patterns( $body, @args );
    }
    return $reply;

}

sub emoted {
    my ( $self, $mess, $prio ) = @_;
    return $self->told($mess) if $prio == 2;
}

sub _replace_patterns {
    my ( $self, $body, @args ) = @_;
    my @reply;

    # Find the pattern back in the list
    my $pattern  = $self->_get_pattern();
    my $patterns = $self->_get_patterns();
    while ( $body =~ /$pattern/ ) {
        my $found = 0;
      PATTERN:
        for my $item (@$patterns) {
            if ( my @params = $body =~ $item->{pattern} ) {
                my $reply = $item->{reply} || '';
                $reply =~ s/\$param(\d+)/$params[$1-1] || ''/ge;
                my $title = title($reply);
                $title =~ s/ < \w+ < Foswiki$//;
                push @reply, "$reply - $title";
                $body =~ s/$item->{pattern}//;
                $found++;
                last PATTERN;
            }
        }
        last unless $found;    # Prevent looping forever
    }
    return join " ", @reply;
}

sub _add_pattern {
    my ( $self, $key, $pattern, $reply ) = @_;
    my $patterns = $self->_get_patterns();
    push @$patterns,
      {
        key     => $key,
        pattern => $pattern,
        reply   => $reply,
      };
    $self->set( 'foswiki_patterns', $patterns );
    $self->{patterns} = $patterns;
    $self->_get_pattern(1);    # Refresh pattern cache
    return "Added Foswiki pattern $key (" . @$patterns . ' total).';
}

sub _remove_pattern {
    my ( $self, $key ) = @_;
    my $patterns = $self->_get_patterns();
    my $found    = 0;
    for my $item ( 0 .. $#{$patterns} ) {
        if ( $patterns->[$item]->{key} eq $key ) {
            splice @$patterns, $item, 1;
            $found++;
            last;
        }
    }
    return "No such pattern $key. Not removed." unless $found;
    $self->set( 'foswiki_patterns', $patterns );
    $self->{patterns} = $patterns;
    $self->_get_pattern(1);    # Refresh pattern cache
    return "Removed Foswiki pattern $key (" . @$patterns . ' total).';
}

sub _get_patterns {
    my $self = shift;
    return $self->{patterns} ||= $self->get('foswiki_patterns') || [];
}

sub _get_pattern {
    my ( $self, $refresh ) = @_;
    return $self->{pattern} if $self->{pattern} && !$refresh;

    # Build one RE from all patterns, for speed
    my $patterns = $self->_get_patterns();
    my $ra       = Regexp::Assemble->new();
    for my $item (@$patterns) {
        $ra->add( $item->{pattern} );
    }
    return $self->{pattern} = $ra->re;
}

sub _list_patterns {
    my ( $self, $key ) = @_;
    my $patterns = $self->_get_patterns();
    my @list;
    for my $item (@$patterns) {
        if ( $key && $item->{key} eq $key ) {
            return join( ", ",
                map { ucfirst($_) . ': ' . $item->{$_} }
                  qw(key pattern reply) );
        }
        else {
            push @list, $item->{key};
        }
    }
    return 'Currently watching ' . @list . ' patterns: ' . join( ", ", @list );
}

sub _get_ua {
    my $self = shift;
    return $self->{ua} if $self->{ua};
    my $ua = LWP::UserAgent->new();
    $ua->agent("Bot/BasicBot/Pluggable/Module/Foswiki/$VERSION");
    $ua->env_proxy();
    return $self->{ua} = $ua;
}

sub _logtime {
    my ( $self, $channel ) = @_;

    return 'No channel specified, try: logtime <channel>' unless $channel;
    $channel =~ s/#//;

    my $logDate = strftime( $self->get('user_log_date_format'), gmtime() );
    my $reply = $self->get('user_log_link') . $channel . "?date=$logDate";

    my $ua       = $self->_get_ua;
    my $response = $ua->get($reply);
    return "Couldn't get $reply: " . $response->status_line()
      unless $response->is_success();
    my $content = $response->decoded_content;
    if ( defined $content ) {
        return "Cannot find any logs for channel #$channel"
          if $content =~ m/^Cannot list channel/;
        my $sel = $content;
        $sel =~ s/.*\?date=$logDate&sel=([0-9l#]+)'/$1/s;
        $sel =~ s/([0-9l#]+).*/$1/s;
        $reply .= "&sel=$sel" if $sel ne "<html";
    }
    else {
        $reply = "Unable to load the current log: $reply";
    }
    $reply .= " (channel #$channel)";
    return $reply;

}

sub help {
    my ( $self, $command ) = @_;
    my %help = (
        default =>
q{foswiki add key pattern action, foswiki delete key, foswiki list, foswiki help <command>},
        add =>
q{foswiki add key Something(\S+) http://url/$param1 -- Adds a new pattern match, and replaces $param1 with the matched value},
        list   => q{foswiki list -- Displays get the list of active patterns},
        delete => q{foswiki delete key - Remove the associated key},
        remove => q{foswiki remove key - Remove the associated key},
    );
    return $help{ $command || 'default' };
}

1;

__END__

=head1 NAME

Bot::BasicBot::Pluggable::Module::Foswiki - IRC module for basic TML

=head1 SYNOPSIS

    <@you> I opened Item1234, can somebody please have a look?
    <+bot> http://foswiki.org/Tasks/Item1234 - Item1234: Some bug

=head1 DESCRIPTION

This module is an attempt to migrate some of the functionnalities we had when
running FoswikiBot with mozbot. Mozbot had been discontinued for a long time,
and it's using L<Net::IRC> which is also dead, hence this attempt to migrate, and
enhance.

=head1 CONFIGURATION

For the moment, only the logtime functionnality is configurable, rest being
administered live.

=head2 user_log_link

The base URL where the logs are accessible. Defaults to
"http://irclogs.foswiki.org/bin/irclogger_log/".

=head2 user_log_date_format

The date format used by the logger. Defaults to "%Y-%m-%d,%a".

=head1 IRC USAGE

The robot replies to requests in the following form:

    foswiki <subcommand> [args]
    [!]logtime

=head2 Commands

The robot understand the following subcommands:

=over 4

=item * add <key> <pattern> <reply>

    <@you> foswiki add WikiWord ([A-Z]+[A-Za-z]+[A-Z]+[A-Za-z0-9./]*) http://foswiki.org/$param1
    <+bot> Added Foswiki pattern WikiWord (1 total).

Adds a new pattern, indexed by <key>, matching <pattern>, and replying <reply>
when the <pattern> is matched.

=item * delete <key>

    <@you> foswiki delete WikiWord
    <+bot> Removed Foswiki pattern WikiWord (0 total).

Removes the pattern indexed by <key> from the matchlist.

=item * remove <key>

remove is an alias for delete

=item * list [ <key> ]

    <@you> foswiki list WikiWord
    <+bot> Currently watching 1 patterns: WikiWord
    <@you> foswiki list WikiWord
    <+bot> Key Foswiki, Pattern: ([A-Z]+[A-Za-z]+[A-Z]+[A-Za-z0-9./]*), Reply: http://foswiki.org/$param1

Lists the current patterns, if no <key> is provided, or prints out the key,
pattern and reply for a given <key>

=item * logtime

    < you> logtime
    < bot> http://irclogs.foswiki.org/bin/irclogger_log/foswiki?date=2011-06-13,Mon&sel=284#l280 (channel #foswiki)

Prints out the current position in the logs, for easy access.
Can also be invoked with a starting bang, for compatibility.

=back

=head1 AUTHOR

Olivier "Babar" Raginel, C<< <babar@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-bot-basicbot-pluggable-module-foswiki@rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/>. I will be notified, and
then you'll automatically be notified of progress on your bug as I
make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2011 Olivier "Babar" Raginel, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Bot::BasicBot::Pluggable>, L<Regexp::Assemble>

=cut
